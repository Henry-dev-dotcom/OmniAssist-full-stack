import uuid
from typing import Any

from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.common.errors import DomainError, ErrorCode
from src.domain.common.ids import new_uuid7
from src.domain.projects.schemas import ProjectOut
from src.domain.sync.repository import record_change

COLUMNS = (
    "id, workspace_id, name, category, status, description, start_at, target_at, "
    "progress_mode, progress_value, version, updated_at"
)
ENUM_CASTS = {"category": "project_category", "status": "project_status"}
UPDATABLE = ("name", "category", "status", "description", "start_at", "target_at",
             "progress_mode", "progress_value")  # fmt: skip


async def list_projects(
    s: AsyncSession, workspace_id: uuid.UUID, view: str, limit: int = 50, offset: int = 0
) -> list[dict[str, Any]]:
    cond = {
        "active": "AND status <> 'archived'",
        "archived": "AND status = 'archived'",
        "all": "",
    }[view]
    rows = await s.execute(
        text(
            f"SELECT {COLUMNS} FROM projects WHERE workspace_id = :w AND deleted_at IS NULL "
            f"{cond} ORDER BY name, id LIMIT :limit OFFSET :offset"
        ),
        {"w": workspace_id, "limit": limit, "offset": offset},
    )
    return [dict(r) for r in rows.mappings()]


async def get_for_user(
    s: AsyncSession, project_id: uuid.UUID, user_id: uuid.UUID
) -> dict[str, Any] | None:
    """Returns the project only if the user is a member of its workspace."""
    row = await s.execute(
        text(
            f"""SELECT {", ".join("p." + c.strip() for c in COLUMNS.split(","))}
            FROM projects p JOIN workspace_members m ON m.workspace_id = p.workspace_id
            WHERE p.id = :p AND m.user_id = :u AND p.deleted_at IS NULL"""
        ),
        {"p": project_id, "u": user_id},
    )
    found = row.mappings().first()
    return dict(found) if found else None


async def get_in_workspace(
    s: AsyncSession, project_id: uuid.UUID, workspace_id: uuid.UUID
) -> dict[str, Any] | None:
    row = await s.execute(
        text(
            f"SELECT {COLUMNS} FROM projects WHERE id = :p AND workspace_id = :w "
            "AND deleted_at IS NULL"
        ),
        {"p": project_id, "w": workspace_id},
    )
    found = row.mappings().first()
    return dict(found) if found else None


def _payload(row: dict[str, Any], keys: set[str] | None = None) -> dict[str, Any]:
    return ProjectOut.model_validate(row).model_dump(mode="json", include=keys)


async def create(s: AsyncSession, values: dict[str, Any]) -> dict[str, Any]:
    """Callers commit. Also writes the sync change row in the same transaction."""
    values = {**values, "id": values.get("id") or new_uuid7()}
    try:
        async with s.begin_nested():
            row = await s.execute(
                text(
                    """INSERT INTO projects (id, workspace_id, name, category, status, description,
                      start_at, target_at, progress_mode, progress_value)
                    VALUES (:id, :workspace_id, :name, CAST(:category AS project_category),
                      CAST(:status AS project_status), :description, :start_at, :target_at,
                      :progress_mode, :progress_value)
                    RETURNING """
                    + COLUMNS
                ),
                values,
            )
    except IntegrityError:
        raise DomainError(
            ErrorCode.VERSION_CONFLICT, "A record with this ID already exists."
        ) from None
    created = dict(row.mappings().one())
    await record_change(
        s, created["workspace_id"], "project", created["id"], "create", created["version"],
        _payload(created),
    )  # fmt: skip
    return created


async def update(s: AsyncSession, project_id: uuid.UUID, changes: dict[str, Any]) -> dict[str, Any]:
    sets = ["version = version + 1", "updated_at = now()"]
    for key in UPDATABLE:
        if key in changes:
            cast = f"CAST(:{key} AS {ENUM_CASTS[key]})" if key in ENUM_CASTS else f":{key}"
            sets.append(f"{key} = {cast}")
    try:
        async with s.begin_nested():
            row = await s.execute(
                text(f"UPDATE projects SET {', '.join(sets)} WHERE id = :id RETURNING {COLUMNS}"),
                {**changes, "id": project_id},
            )
    except IntegrityError:  # e.g. target_at before start_at after merging with stored values
        raise DomainError(ErrorCode.VALIDATION_ERROR, "Project values are inconsistent.") from None
    updated = dict(row.mappings().one())
    await record_change(
        s, updated["workspace_id"], "project", project_id, "update", updated["version"],
        _payload(updated, {k for k in changes if k in UPDATABLE}),
    )  # fmt: skip
    return updated


LINKED = (
    "tasks",
    "milestones",
    "reviews",
    "analysis_records",
    "experiment_entries",
    "funding_opportunities",
)


async def tombstone(s: AsyncSession, project_id: uuid.UUID) -> None:
    """Only an empty project can be deleted; otherwise archive it (decision 0003)."""
    for table in LINKED:
        busy = await s.execute(
            text(f"SELECT 1 FROM {table} WHERE project_id = :p AND deleted_at IS NULL LIMIT 1"),
            {"p": project_id},
        )
        if busy.first() is not None:
            raise DomainError(
                ErrorCode.DOMAIN_RULE_VIOLATION,
                "This project still has work in it. Archive it, or move its work first.",
            )
    row = await s.execute(
        text(
            "UPDATE projects SET deleted_at = now(), version = version + 1, updated_at = now() "
            "WHERE id = :id RETURNING workspace_id, version"
        ),
        {"id": project_id},
    )
    r = row.mappings().one()
    await record_change(s, r["workspace_id"], "project", project_id, "delete", r["version"], None)
