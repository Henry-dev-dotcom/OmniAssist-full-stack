import json
import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.common.errors import DomainError, ErrorCode
from src.domain.common.ids import new_uuid7
from src.domain.common.records import require_in_workspace
from src.domain.notifications.repository import cancel_for_entity, sync_task_reminders
from src.domain.sync.repository import record_change
from src.domain.tasks.schemas import TaskOut

COLUMNS = (
    "id, workspace_id, project_id, milestone_id, parent_task_id, title, description, status, "
    "priority, due_at, estimated_minutes, recurrence_rule, completed_at, tags, version, "
    "updated_at"
)
ENUM_CASTS = {"status": "task_status", "priority": "task_priority", "tags": "jsonb"}
UPDATABLE = ("project_id", "milestone_id", "parent_task_id", "title", "description", "status",
             "priority", "due_at", "estimated_minutes", "recurrence_rule",
             "completed_at", "tags")  # fmt: skip


def _payload(row: dict[str, Any], keys: set[str] | None = None) -> dict[str, Any]:
    return TaskOut.model_validate(row).model_dump(mode="json", include=keys)


async def _check_links(
    s: AsyncSession,
    workspace_id: uuid.UUID,
    task_id: uuid.UUID | None,
    project_id: uuid.UUID | None,
    parent_id: uuid.UUID | None,
    milestone_id: uuid.UUID | None = None,
) -> None:
    """Linked project, milestone and parent task must live in the same workspace."""
    await require_in_workspace(s, "milestones", milestone_id, workspace_id, "Milestone")
    if project_id is not None:
        row = await s.execute(
            text(
                "SELECT 1 FROM projects WHERE id = :p AND workspace_id = :w AND deleted_at IS NULL"
            ),
            {"p": project_id, "w": workspace_id},
        )
        if row.first() is None:
            raise DomainError(ErrorCode.NOT_FOUND, "Project not found.")
    if parent_id is not None:
        if parent_id == task_id:
            raise DomainError(ErrorCode.DOMAIN_RULE_VIOLATION, "A task cannot be its own parent.")
        row = await s.execute(
            text("SELECT 1 FROM tasks WHERE id = :p AND workspace_id = :w AND deleted_at IS NULL"),
            {"p": parent_id, "w": workspace_id},
        )
        if row.first() is None:
            raise DomainError(ErrorCode.NOT_FOUND, "Parent task not found.")
        # Walk up from the new parent: meeting this task means a loop of subtasks.
        cur: uuid.UUID | None = parent_id
        for _ in range(100):
            cur = (
                await s.execute(text("SELECT parent_task_id FROM tasks WHERE id = :t"), {"t": cur})
            ).scalar_one_or_none()
            if cur is None:
                break
            if cur == task_id:
                raise DomainError(
                    ErrorCode.DOMAIN_RULE_VIOLATION, "A task cannot be inside its own subtask."
                )


async def list_tasks(
    s: AsyncSession,
    workspace_id: uuid.UUID,
    status: str | None = None,
    project_id: uuid.UUID | None = None,
) -> list[dict[str, Any]]:
    where = ["workspace_id = :w", "deleted_at IS NULL"]
    params: dict[str, Any] = {"w": workspace_id}
    if status:
        where.append("status = CAST(:status AS task_status)")
        params["status"] = status
    if project_id:
        where.append("project_id = :project")
        params["project"] = project_id
    rows = await s.execute(
        text(
            f"SELECT {COLUMNS} FROM tasks WHERE {' AND '.join(where)} "
            "ORDER BY due_at NULLS LAST, created_at"
        ),
        params,
    )
    return [dict(r) for r in rows.mappings()]


async def get_in_workspace(
    s: AsyncSession, task_id: uuid.UUID, workspace_id: uuid.UUID
) -> dict[str, Any] | None:
    row = await s.execute(
        text(
            f"SELECT {COLUMNS} FROM tasks WHERE id = :t AND workspace_id = :w "
            "AND deleted_at IS NULL"
        ),
        {"t": task_id, "w": workspace_id},
    )
    found = row.mappings().first()
    return dict(found) if found else None


async def get_for_user(
    s: AsyncSession, task_id: uuid.UUID, user_id: uuid.UUID
) -> dict[str, Any] | None:
    """Returns the task only if the user is a member of its workspace."""
    row = await s.execute(
        text(
            """SELECT t.workspace_id FROM tasks t
            JOIN workspace_members m ON m.workspace_id = t.workspace_id
            WHERE t.id = :t AND m.user_id = :u AND t.deleted_at IS NULL"""
        ),
        {"t": task_id, "u": user_id},
    )
    ws = row.scalar_one_or_none()
    return None if ws is None else await get_in_workspace(s, task_id, ws)


async def create(s: AsyncSession, values: dict[str, Any]) -> dict[str, Any]:
    """Callers commit. Also writes the sync change row in the same transaction."""
    values = {**values, "id": values.get("id") or new_uuid7()}
    await _check_links(
        s, values["workspace_id"], values["id"], values.get("project_id"),
        values.get("parent_task_id"), values.get("milestone_id"),
    )  # fmt: skip
    done_now = values["status"] == "complete" and values.get("completed_at") is None
    completed = "now()" if done_now else ":completed_at"
    try:
        async with s.begin_nested():
            row = await s.execute(
                text(
                    f"""INSERT INTO tasks (id, workspace_id, project_id, milestone_id,
                      parent_task_id, title, description, status, priority, due_at,
                      estimated_minutes, recurrence_rule, completed_at, tags)
                    VALUES (:id, :workspace_id, :project_id, :milestone_id, :parent_task_id,
                      :title, :description,
                      CAST(:status AS task_status), CAST(:priority AS task_priority), :due_at,
                      :estimated_minutes, :recurrence_rule, {completed}, CAST(:tags AS jsonb))
                    RETURNING {COLUMNS}"""
                ),
                {**values, "tags": json.dumps(values.get("tags") or [])},
            )
    except IntegrityError:
        raise DomainError(
            ErrorCode.VERSION_CONFLICT, "A record with this ID already exists."
        ) from None
    created = dict(row.mappings().one())
    await record_change(
        s, created["workspace_id"], "task", created["id"], "create", created["version"],
        _payload(created),
    )  # fmt: skip
    return created


async def update(
    s: AsyncSession, task_id: uuid.UUID, workspace_id: uuid.UUID, changes: dict[str, Any]
) -> dict[str, Any]:
    if changes.keys() & {"project_id", "parent_task_id", "milestone_id"}:
        await _check_links(
            s, workspace_id, task_id, changes.get("project_id"), changes.get("parent_task_id"),
            changes.get("milestone_id"),
        )  # fmt: skip
    sets = ["version = version + 1", "updated_at = now()"]
    for key in UPDATABLE:
        if key in changes:
            cast = f"CAST(:{key} AS {ENUM_CASTS[key]})" if key in ENUM_CASTS else f":{key}"
            sets.append(f"{key} = {cast}")
    if "status" in changes and "completed_at" not in changes:
        # Completing records a time; leaving "complete" clears it (Spec 4.3).
        if changes["status"] == "complete":
            sets.append("completed_at = COALESCE(completed_at, now())")
        else:
            sets.append("completed_at = NULL")
    try:
        async with s.begin_nested():
            row = await s.execute(
                text(f"UPDATE tasks SET {', '.join(sets)} WHERE id = :id RETURNING {COLUMNS}"),
                {
                    **changes,
                    "id": task_id,
                    **({"tags": json.dumps(changes["tags"])} if "tags" in changes else {}),
                },
            )
    except IntegrityError:
        raise DomainError(ErrorCode.VALIDATION_ERROR, "Task values are inconsistent.") from None
    updated = dict(row.mappings().one())
    if changes.keys() & {"status", "due_at", "title"}:
        await sync_task_reminders(s, updated, datetime.now(UTC))
    keys = {k for k in changes if k in UPDATABLE}
    if "status" in changes:
        keys.add("completed_at")  # status can set or clear it
    await record_change(
        s, updated["workspace_id"], "task", task_id, "update", updated["version"],
        _payload(updated, keys),
    )  # fmt: skip
    return updated


async def tombstone(s: AsyncSession, task_id: uuid.UUID) -> None:
    row = await s.execute(
        text(
            "UPDATE tasks SET deleted_at = now(), version = version + 1, updated_at = now() "
            "WHERE id = :id RETURNING workspace_id, version"
        ),
        {"id": task_id},
    )
    r = row.mappings().one()
    await cancel_for_entity(s, "task", task_id)
    await record_change(s, r["workspace_id"], "task", task_id, "delete", r["version"], None)
