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
