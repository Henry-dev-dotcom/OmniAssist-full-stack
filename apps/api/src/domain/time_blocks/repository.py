import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import bindparam, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.common.errors import DomainError, ErrorCode
from src.domain.common.ids import new_uuid7
from src.domain.sync.repository import record_change
from src.domain.time_blocks.schemas import TimeBlockOut
from src.domain.time_blocks.service import FREE_STATES, check_transition

COLUMNS = (
    "id, workspace_id, task_id, project_id, title, category, starts_at, ends_at, status, "
    "version, updated_at"
)
UPDATABLE = ("task_id", "project_id", "title", "category", "starts_at", "ends_at", "status")


def _payload(row: dict[str, Any], keys: set[str] | None = None) -> dict[str, Any]:
    return TimeBlockOut.model_validate(row).model_dump(mode="json", include=keys)


async def _check_links(
    s: AsyncSession,
    workspace_id: uuid.UUID,
    task_id: uuid.UUID | None,
    project_id: uuid.UUID | None,
) -> None:
    for table, value, label in (("tasks", task_id, "Task"), ("projects", project_id, "Project")):
        if value is None:
            continue
        row = await s.execute(
            text(
                f"SELECT 1 FROM {table} WHERE id = :i AND workspace_id = :w AND deleted_at IS NULL"
            ),
            {"i": value, "w": workspace_id},
        )
        if row.first() is None:
            raise DomainError(ErrorCode.NOT_FOUND, f"{label} not found.")


async def overlapping_ids(
    s: AsyncSession,
    workspace_id: uuid.UUID,
    starts_at: datetime,
    ends_at: datetime,
    exclude: uuid.UUID | None,
) -> list[uuid.UUID]:
    """Blocks that share time with the range. A warning only; saving is never blocked."""
    rows = await s.execute(
        text(
            """SELECT id FROM time_blocks
            WHERE workspace_id = :w AND deleted_at IS NULL AND status NOT IN :free
              AND starts_at < :e AND ends_at > :s AND (CAST(:x AS uuid) IS NULL OR id <> :x)
            ORDER BY starts_at"""
        ).bindparams(bindparam("free", expanding=True)),
        {"w": workspace_id, "s": starts_at, "e": ends_at, "x": exclude, "free": list(FREE_STATES)},
    )
    return [r[0] for r in rows]


async def list_blocks(
    s: AsyncSession,
    workspace_id: uuid.UUID,
    start: datetime | None,
    end: datetime | None,
) -> list[dict[str, Any]]:
    where = ["workspace_id = :w", "deleted_at IS NULL"]
    params: dict[str, Any] = {"w": workspace_id}
    if start:
        where.append("ends_at > :s")
        params["s"] = start
    if end:
        where.append("starts_at < :e")
        params["e"] = end
    rows = await s.execute(
        text(f"SELECT {COLUMNS} FROM time_blocks WHERE {' AND '.join(where)} ORDER BY starts_at"),
        params,
    )
    return [dict(r) for r in rows.mappings()]


async def get_in_workspace(
    s: AsyncSession, block_id: uuid.UUID, workspace_id: uuid.UUID
) -> dict[str, Any] | None:
    row = await s.execute(
        text(
            f"SELECT {COLUMNS} FROM time_blocks WHERE id = :b AND workspace_id = :w "
            "AND deleted_at IS NULL"
        ),
        {"b": block_id, "w": workspace_id},
    )
    found = row.mappings().first()
    return dict(found) if found else None


async def get_for_user(
    s: AsyncSession, block_id: uuid.UUID, user_id: uuid.UUID
) -> dict[str, Any] | None:
    row = await s.execute(
        text(
            """SELECT b.workspace_id FROM time_blocks b
            JOIN workspace_members m ON m.workspace_id = b.workspace_id
            WHERE b.id = :b AND m.user_id = :u AND b.deleted_at IS NULL"""
        ),
        {"b": block_id, "u": user_id},
    )
    ws = row.scalar_one_or_none()
    return None if ws is None else await get_in_workspace(s, block_id, ws)


async def create(s: AsyncSession, values: dict[str, Any]) -> dict[str, Any]:
    """Callers commit. Also writes the sync change row in the same transaction."""
    values = {**values, "id": values.get("id") or new_uuid7()}
    await _check_links(s, values["workspace_id"], values.get("task_id"), values.get("project_id"))
    try:
        async with s.begin_nested():
            row = await s.execute(
                text(
                    f"""INSERT INTO time_blocks (id, workspace_id, task_id, project_id, title,
                      category, starts_at, ends_at, status)
                    VALUES (:id, :workspace_id, :task_id, :project_id, :title, :category,
                      :starts_at, :ends_at, :status)
                    RETURNING {COLUMNS}"""
                ),
                values,
            )
    except IntegrityError:
        raise DomainError(
            ErrorCode.VERSION_CONFLICT, "A record with this ID already exists."
        ) from None
    created = dict(row.mappings().one())
    await record_change(
        s, created["workspace_id"], "time_block", created["id"], "create", created["version"],
        _payload(created),
    )  # fmt: skip
    return created


async def update(
    s: AsyncSession, block_id: uuid.UUID, workspace_id: uuid.UUID, changes: dict[str, Any]
) -> dict[str, Any]:
    current = await get_in_workspace(s, block_id, workspace_id)
    if current is None:
        raise DomainError(ErrorCode.NOT_FOUND, "Time block not found.")
    if "status" in changes:
        check_transition(current["status"], changes["status"])
    start = changes.get("starts_at", current["starts_at"])
    end = changes.get("ends_at", current["ends_at"])
    if end <= start:  # a one-sided edit can still invert the stored range
        raise DomainError(ErrorCode.VALIDATION_ERROR, "ends_at must be after starts_at.")
    if "task_id" in changes or "project_id" in changes:
        await _check_links(s, workspace_id, changes.get("task_id"), changes.get("project_id"))
    sets = ["version = version + 1", "updated_at = now()"]
    for key in UPDATABLE:
        if key in changes:
            sets.append(f"{key} = :{key}")
    row = await s.execute(
        text(f"UPDATE time_blocks SET {', '.join(sets)} WHERE id = :id RETURNING {COLUMNS}"),
        {**changes, "id": block_id},
    )
    updated = dict(row.mappings().one())
    await record_change(
        s, workspace_id, "time_block", block_id, "update", updated["version"],
        _payload(updated, {k for k in changes if k in UPDATABLE}),
    )  # fmt: skip
    return updated


async def tombstone(s: AsyncSession, block_id: uuid.UUID) -> None:
    row = await s.execute(
        text(
            "UPDATE time_blocks SET deleted_at = now(), version = version + 1, updated_at = now() "
            "WHERE id = :id RETURNING workspace_id, version"
        ),
        {"id": block_id},
    )
    r = row.mappings().one()
    await record_change(s, r["workspace_id"], "time_block", block_id, "delete", r["version"], None)
