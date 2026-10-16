import uuid
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

COLUMNS = "w.id, w.owner_id, w.name, w.archived_at, w.created_at, w.version"


async def create(s: AsyncSession, owner_id: uuid.UUID, name: str) -> dict[str, Any]:
    row = await s.execute(
        text(
            "INSERT INTO workspaces (owner_id, name) VALUES (:o, :n) "
            "RETURNING id, owner_id, name, archived_at, created_at, version"
        ),
        {"o": owner_id, "n": name},
    )
    ws = dict(row.mappings().one())
    await s.execute(
        text(
            "INSERT INTO workspace_members (workspace_id, user_id, role) VALUES (:w, :u, 'owner')"
        ),
        {"w": ws["id"], "u": owner_id},
    )
    await s.commit()
    return ws


async def list_for_user(s: AsyncSession, user_id: uuid.UUID) -> list[dict[str, Any]]:
    rows = await s.execute(
        text(
            f"""SELECT {COLUMNS} FROM workspaces w
            JOIN workspace_members m ON m.workspace_id = w.id
            WHERE m.user_id = :u AND w.deleted_at IS NULL ORDER BY w.created_at"""
        ),
        {"u": user_id},
    )
    return [dict(r) for r in rows.mappings()]


async def is_member(s: AsyncSession, workspace_id: uuid.UUID, user_id: uuid.UUID) -> bool:
    row = await s.execute(
        text(
            """SELECT 1 FROM workspace_members m JOIN workspaces w ON w.id = m.workspace_id
            WHERE m.workspace_id = :w AND m.user_id = :u AND w.deleted_at IS NULL"""
        ),
        {"w": workspace_id, "u": user_id},
    )
    return row.first() is not None


# Child tables first, so foreign keys never block the delete.
_DATA = (
    "DELETE FROM milestone_dependencies d USING milestones m "
    "WHERE m.id = d.milestone_id AND m.workspace_id = ANY(:ws)",
    "DELETE FROM task_tags tt USING tasks t WHERE t.id = tt.task_id AND t.workspace_id = ANY(:ws)",
    "DELETE FROM review_item_events e USING review_items i "
    "WHERE i.id = e.review_item_id AND i.workspace_id = ANY(:ws)",
    "DELETE FROM experiment_revisions v USING experiment_entries e "
    "WHERE e.id = v.entry_id AND e.workspace_id = ANY(:ws)",
    "DELETE FROM time_blocks WHERE workspace_id = ANY(:ws)",
    "UPDATE tasks SET parent_task_id = NULL WHERE workspace_id = ANY(:ws)",
    "DELETE FROM tasks WHERE workspace_id = ANY(:ws)",
    "DELETE FROM review_items WHERE workspace_id = ANY(:ws)",
    "DELETE FROM review_stages st USING reviews r "
    "WHERE r.id = st.review_id AND r.workspace_id = ANY(:ws)",
    "DELETE FROM reviews WHERE workspace_id = ANY(:ws)",
    "DELETE FROM analysis_records WHERE workspace_id = ANY(:ws)",
    "DELETE FROM experiment_entries WHERE workspace_id = ANY(:ws)",
    "UPDATE milestones SET parent_id = NULL WHERE workspace_id = ANY(:ws)",
    "DELETE FROM milestones WHERE workspace_id = ANY(:ws)",
    "DELETE FROM routines WHERE workspace_id = ANY(:ws)",
    "DELETE FROM tags WHERE workspace_id = ANY(:ws)",
    "DELETE FROM projects WHERE workspace_id = ANY(:ws)",
    "DELETE FROM notifications WHERE workspace_id = ANY(:ws)",
    "DELETE FROM attachments WHERE workspace_id = ANY(:ws)",
    "DELETE FROM activity_events WHERE workspace_id = ANY(:ws)",
    "DELETE FROM audit_events WHERE workspace_id = ANY(:ws)",
    "DELETE FROM sync_changes WHERE workspace_id = ANY(:ws)",
    "DELETE FROM sync_mutations WHERE workspace_id = ANY(:ws)",
    "DELETE FROM sync_conflicts WHERE workspace_id = ANY(:ws)",
    "DELETE FROM exports WHERE workspace_id = ANY(:ws)",
    "DELETE FROM workspace_members WHERE workspace_id = ANY(:ws)",
    "DELETE FROM workspaces WHERE id = ANY(:ws)",
)


async def purge(s: AsyncSession, workspace_ids: list[uuid.UUID]) -> None:
    """Permanently removes the workspaces and everything in them. Callers commit."""
    for stmt in _DATA:
        await s.execute(text(stmt), {"ws": workspace_ids})


async def get_owned(
    s: AsyncSession, workspace_id: uuid.UUID, user_id: uuid.UUID
) -> dict[str, Any] | None:
    row = await s.execute(
        text(f"SELECT {COLUMNS} FROM workspaces w WHERE w.id = :w AND w.owner_id = :u "
             "AND w.deleted_at IS NULL"),
        {"w": workspace_id, "u": user_id},
    )  # fmt: skip
    found = row.mappings().first()
    return dict(found) if found else None


async def update(
    s: AsyncSession, workspace_id: uuid.UUID, name: str | None, archived: bool | None
) -> dict[str, Any]:
    sets = ["version = version + 1", "updated_at = now()"]
    if name is not None:
        sets.append("name = :n")
    if archived is not None:
        sets.append("archived_at = CASE WHEN :a THEN COALESCE(archived_at, now()) END")
    row = await s.execute(
        text(f"UPDATE workspaces w SET {', '.join(sets)} WHERE w.id = :w RETURNING {COLUMNS}"),
        {"w": workspace_id, "n": name, "a": archived},
    )
    await s.commit()
    return dict(row.mappings().one())
