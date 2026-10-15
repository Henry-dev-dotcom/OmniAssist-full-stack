"""Generic workspace-scoped repository for synchronized entities (decision 0003).

One instance per table. Subclasses add domain rules through `check` (before a write)
and `after_write` (same transaction, after the row changed). Every write appends to the
sync change feed in the caller's transaction, like the task repository does.
"""

import json
import uuid
from typing import Any

from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.common.errors import DomainError, ErrorCode
from src.domain.common.ids import new_uuid7
from src.domain.sync.repository import record_change


class RecordRepo:
    def __init__(
        self,
        *,
        table: str,
        entity_type: str,
        columns: tuple[str, ...],
        updatable: tuple[str, ...],
        out: type[BaseModel],
        casts: dict[str, str] | None = None,
        extra_select: str = "",
        label: str = "Record",
    ) -> None:
        self.table = table
        self.entity_type = entity_type
        self.columns = columns  # stored columns besides id, workspace_id, version, updated_at
        self.updatable = updatable
        self.out = out
        self.casts = casts or {}
        self.extra_select = extra_select  # computed columns, e.g. dependency arrays
        self.not_found = DomainError(ErrorCode.NOT_FOUND, f"{label} not found.")

    # --- hooks -------------------------------------------------------------------------

    async def check(
        self,
        s: AsyncSession,
        workspace_id: uuid.UUID,
        entity_id: uuid.UUID,
        values: dict[str, Any],
        current: dict[str, Any] | None,
    ) -> dict[str, Any]:
        """Validate links and rules; may return adjusted values. `current` is None on create."""
        return values

    async def after_write(
        self,
        s: AsyncSession,
        row: dict[str, Any],
        values: dict[str, Any],
        before: dict[str, Any] | None,
        actor_id: uuid.UUID | None,
    ) -> None:
        """Side effects that must commit with the row (history, dependencies).
        `before` is None on create."""

    # --- queries -----------------------------------------------------------------------

    def _select(self) -> str:
        cols = ", ".join(f"r.{c}" for c in ("id", "workspace_id", *self.columns))
        return f"SELECT {cols}, r.version, r.updated_at{self.extra_select} FROM {self.table} r"

    def payload(self, row: dict[str, Any], keys: set[str] | None = None) -> dict[str, Any]:
        return self.out.model_validate(row).model_dump(mode="json", include=keys)

    async def get_in_workspace(
        self, s: AsyncSession, entity_id: uuid.UUID, workspace_id: uuid.UUID
    ) -> dict[str, Any] | None:
        row = await s.execute(
            text(
                f"{self._select()} WHERE r.id = :id AND r.workspace_id = :w "
                "AND r.deleted_at IS NULL"
            ),
            {"id": entity_id, "w": workspace_id},
        )
        found = row.mappings().first()
        return dict(found) if found else None

    async def get_for_user(
        self, s: AsyncSession, entity_id: uuid.UUID, user_id: uuid.UUID
    ) -> dict[str, Any] | None:
        """The row only if the user belongs to its workspace; same answer for missing."""
        row = await s.execute(
            text(
                f"""SELECT r.workspace_id FROM {self.table} r
                JOIN workspace_members m ON m.workspace_id = r.workspace_id
                WHERE r.id = :id AND m.user_id = :u AND r.deleted_at IS NULL"""
            ),
            {"id": entity_id, "u": user_id},
        )
        ws = row.scalar_one_or_none()
        return None if ws is None else await self.get_in_workspace(s, entity_id, ws)

    async def list_rows(
        self,
        s: AsyncSession,
        workspace_id: uuid.UUID,
        filters: dict[str, Any] | None = None,
        order: str = "r.updated_at DESC",
    ) -> list[dict[str, Any]]:
        where = ["r.workspace_id = :w", "r.deleted_at IS NULL"]
        params: dict[str, Any] = {"w": workspace_id}
        for key, value in (filters or {}).items():
            if value is not None:
                assert key in self.columns, key  # never interpolate untrusted names
                where.append(f"r.{key} = :f_{key}")
                params[f"f_{key}"] = value
        rows = await s.execute(
            text(f"{self._select()} WHERE {' AND '.join(where)} ORDER BY {order}"), params
        )
        return [dict(r) for r in rows.mappings()]

    # --- writes --------------------------------------------------------------------------

    def _param(self, key: str) -> str:
        cast = self.casts.get(key)
        return f"CAST(:{key} AS {cast})" if cast else f":{key}"

    def _bind(self, values: dict[str, Any]) -> dict[str, Any]:
        return {
            k: json.dumps(v) if self.casts.get(k) == "jsonb" and v is not None else v
            for k, v in values.items()
        }

    async def create(
        self, s: AsyncSession, values: dict[str, Any], actor_id: uuid.UUID | None = None
    ) -> dict[str, Any]:
        """Callers commit."""
        values = {**values, "id": values.get("id") or new_uuid7()}
        values = await self.check(s, values["workspace_id"], values["id"], values, None)
        cols = ["id", "workspace_id", *[c for c in self.columns if c in values]]
        try:
            async with s.begin_nested():
                await s.execute(
                    text(
                        f"INSERT INTO {self.table} ({', '.join(cols)}) "
                        f"VALUES ({', '.join(self._param(c) for c in cols)})"
                    ),
                    self._bind({c: values[c] for c in cols}),
                )
        except IntegrityError:
            raise DomainError(
                ErrorCode.VALIDATION_ERROR, f"{self.entity_type} values are invalid or duplicate."
            ) from None
        row = await self.get_in_workspace(s, values["id"], values["workspace_id"])
        assert row is not None
        await self.after_write(s, row, values, None, actor_id)
        row = await self.get_in_workspace(s, values["id"], values["workspace_id"])
        assert row is not None
        await record_change(
            s, row["workspace_id"], self.entity_type, row["id"], "create", row["version"],
            self.payload(row),
        )  # fmt: skip
        return row

    async def update(
        self,
        s: AsyncSession,
        entity_id: uuid.UUID,
        workspace_id: uuid.UUID,
        changes: dict[str, Any],
        actor_id: uuid.UUID | None = None,
    ) -> dict[str, Any]:
        current = await self.get_in_workspace(s, entity_id, workspace_id)
        if current is None:
            raise self.not_found
        changes = await self.check(s, workspace_id, entity_id, changes, current)
        sets = ["version = version + 1", "updated_at = now()"]
        sets += [f"{k} = {self._param(k)}" for k in self.updatable if k in changes]
        try:
            async with s.begin_nested():
                await s.execute(
                    text(f"UPDATE {self.table} SET {', '.join(sets)} WHERE id = :id"),
                    {**self._bind({k: changes[k] for k in self.updatable if k in changes}),
                     "id": entity_id},
                )  # fmt: skip
        except IntegrityError:
            raise DomainError(
                ErrorCode.VALIDATION_ERROR, f"{self.entity_type} values are inconsistent."
            ) from None
        row = await self.get_in_workspace(s, entity_id, workspace_id)
        assert row is not None
        await self.after_write(s, row, changes, current, actor_id)
        row = await self.get_in_workspace(s, entity_id, workspace_id)
        assert row is not None
        keys = set(changes) & set(self.out.model_fields)
        await record_change(
            s, workspace_id, self.entity_type, entity_id, "update", row["version"],
            self.payload(row, keys),
        )  # fmt: skip
        return row

    async def tombstone(self, s: AsyncSession, entity_id: uuid.UUID) -> None:
        row = await s.execute(
            text(
                f"UPDATE {self.table} SET deleted_at = now(), version = version + 1, "
                "updated_at = now() WHERE id = :id RETURNING workspace_id, version"
            ),
            {"id": entity_id},
        )
        r = row.mappings().one()
        await record_change(
            s, r["workspace_id"], self.entity_type, entity_id, "delete", r["version"], None
        )


async def require_in_workspace(
    s: AsyncSession, table: str, entity_id: uuid.UUID | None, workspace_id: uuid.UUID, what: str
) -> None:
    """A linked record must exist, be live, and share the workspace (Spec 4.3)."""
    if entity_id is None:
        return
    row = await s.execute(
        text(f"SELECT 1 FROM {table} WHERE id = :id AND workspace_id = :w AND deleted_at IS NULL"),
        {"id": entity_id, "w": workspace_id},
    )
    if row.first() is None:
        raise DomainError(ErrorCode.NOT_FOUND, f"{what} not found.")
