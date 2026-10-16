import json
import uuid
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.auth.provider import Identity
from src.domain.common.ids import new_uuid7

COLUMNS = "id, email, display_name, timezone, preferences"


async def upsert_by_subject(s: AsyncSession, identity: Identity) -> dict[str, Any]:
    """Map a provider identity to a local user, creating it on first sight."""
    name = identity.name or identity.email.split("@")[0]
    row = await s.execute(
        text(
            f"""INSERT INTO users (id, email, display_name, auth_subject)
            VALUES (:id, :email, :name, :sub)
            ON CONFLICT (auth_subject) DO UPDATE SET email = EXCLUDED.email
            RETURNING {COLUMNS}"""
        ),
        {"id": new_uuid7(), "email": identity.email, "name": name, "sub": identity.subject},
    )
    await s.commit()
    return dict(row.mappings().one())


async def get(s: AsyncSession, user_id: uuid.UUID) -> dict[str, Any]:
    row = await s.execute(text(f"SELECT {COLUMNS} FROM users WHERE id = :id"), {"id": user_id})
    return dict(row.mappings().one())


# Child tables first, so foreign keys never block the delete.
_WORKSPACE_DATA = (
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


async def delete_account(s: AsyncSession, user_id: uuid.UUID, auth_subject: str | None) -> None:
    """Removes the user, every workspace they own and all its data, and their sign-in
    credentials and sessions, in one transaction (decision 0004). Callers commit."""
    rows = await s.execute(text("SELECT id FROM workspaces WHERE owner_id = :u"), {"u": user_id})
    ws = [r for (r,) in rows]
    for stmt in _WORKSPACE_DATA:
        await s.execute(text(stmt), {"ws": ws})
    # Rows in workspaces the user does not own keep their history without the person.
    await s.execute(
        text("UPDATE audit_events SET actor_id = NULL WHERE actor_id = :u"), {"u": user_id}
    )
    await s.execute(text("DELETE FROM workspace_members WHERE user_id = :u"), {"u": user_id})
    if auth_subject is not None:
        # Cascades to refresh tokens, so every session ends now.
        await s.execute(
            text("DELETE FROM local_credentials WHERE subject = :sub"), {"sub": auth_subject}
        )
    await s.execute(text("DELETE FROM exports WHERE requested_by = :u"), {"u": user_id})
    await s.execute(text("DELETE FROM users WHERE id = :u"), {"u": user_id})


async def subject_of(s: AsyncSession, user_id: uuid.UUID) -> str | None:
    row = await s.execute(text("SELECT auth_subject FROM users WHERE id = :u"), {"u": user_id})
    sub: str | None = row.scalar_one_or_none()
    return sub


async def update_profile(
    s: AsyncSession, user_id: uuid.UUID, fields: dict[str, Any]
) -> dict[str, Any]:
    sets = []
    params: dict[str, Any] = {"id": user_id}
    for key in ("display_name", "timezone"):
        if key in fields:
            sets.append(f"{key} = :{key}")
            params[key] = fields[key]
    if "preferences" in fields:
        sets.append("preferences = CAST(:preferences AS jsonb)")
        params["preferences"] = json.dumps(fields["preferences"])
    sets.append("updated_at = now()")
    row = await s.execute(
        text(f"UPDATE users SET {', '.join(sets)} WHERE id = :id RETURNING {COLUMNS}"), params
    )
    await s.commit()
    return dict(row.mappings().one())
