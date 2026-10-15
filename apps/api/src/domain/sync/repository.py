import json
import uuid
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


async def record_change(
    s: AsyncSession,
    workspace_id: uuid.UUID,
    entity_type: str,
    entity_id: uuid.UUID,
    operation: str,
    version: int,
    payload: dict[str, Any] | None,
) -> None:
    """Appends to the change feed. Runs in the caller's transaction, so a change row exists
    exactly when the entity change committed."""
    await s.execute(
        text(
            """INSERT INTO sync_changes
            (workspace_id, entity_type, entity_id, operation, entity_version, payload)
            VALUES (:w, :t, :e, :o, :v, CAST(:p AS jsonb))"""
        ),
        {
            "w": workspace_id, "t": entity_type, "e": entity_id, "o": operation, "v": version,
            "p": None if payload is None else json.dumps(payload),
        },
    )  # fmt: skip


async def pull(
    s: AsyncSession, user_id: uuid.UUID, cursor: int, limit: int
) -> tuple[list[dict[str, Any]], bool]:
    """Changes after `cursor` across every workspace the user belongs to."""
    rows = await s.execute(
        text(
            """SELECT c.sequence, c.entity_type, c.entity_id, c.operation, c.entity_version,
                      c.payload, c.workspace_id
            FROM sync_changes c JOIN workspace_members m ON m.workspace_id = c.workspace_id
            WHERE m.user_id = :u AND c.sequence > :cur ORDER BY c.sequence LIMIT :lim"""
        ),
        {"u": user_id, "cur": cursor, "lim": limit + 1},
    )
    items = [dict(r) for r in rows.mappings()]
    return items[:limit], len(items) > limit


async def keys_changed_since(s: AsyncSession, entity_id: uuid.UUID, base_version: int) -> set[str]:
    rows = await s.execute(
        text(
            "SELECT payload FROM sync_changes WHERE entity_id = :e AND entity_version > :v "
            "AND operation = 'update'"
        ),
        {"e": entity_id, "v": base_version},
    )
    return {k for (p,) in rows if p for k in p}


async def find_mutation(s: AsyncSession, mutation_id: uuid.UUID) -> dict[str, Any] | None:
    row = await s.execute(
        text("SELECT request_hash, result FROM sync_mutations WHERE mutation_id = :m"),
        {"m": mutation_id},
    )
    found = row.mappings().first()
    return dict(found) if found else None


async def save_mutation(
    s: AsyncSession,
    actor_id: uuid.UUID,
    m: Any,
    request_hash: str,
    result: dict[str, Any],
) -> None:
    await s.execute(
        text(
            """INSERT INTO sync_mutations (mutation_id, workspace_id, actor_id, entity_type,
            entity_id, operation, base_version, request_hash, result)
            VALUES (:m, :w, :a, :t, :e, :o, :b, :h, CAST(:r AS jsonb))"""
        ),
        {
            "m": m.mutation_id, "w": m.workspace_id, "a": actor_id, "t": m.entity_type,
            "e": m.entity_id, "o": m.operation, "b": m.base_version, "h": request_hash,
            "r": json.dumps(result),
        },
    )  # fmt: skip


async def save_conflict(
    s: AsyncSession,
    workspace_id: uuid.UUID,
    entity_type: str,
    entity_id: uuid.UUID,
    base_version: int | None,
    local: dict[str, Any],
    server: dict[str, Any],
) -> uuid.UUID:
    row = await s.execute(
        text(
            """INSERT INTO sync_conflicts (workspace_id, entity_type, entity_id, base_version,
            local_payload, server_payload)
            VALUES (:w, :t, :e, :b, CAST(:l AS jsonb), CAST(:s AS jsonb)) RETURNING id"""
        ),
        {
            "w": workspace_id, "t": entity_type, "e": entity_id, "b": base_version,
            "l": json.dumps(local), "s": json.dumps(server),
        },
    )  # fmt: skip
    cid: uuid.UUID = row.scalar_one()
    return cid


async def open_conflicts(s: AsyncSession, workspace_id: uuid.UUID) -> list[dict[str, Any]]:
    rows = await s.execute(
        text(
            """SELECT id, entity_type, entity_id, base_version, local_payload, server_payload,
            created_at FROM sync_conflicts
            WHERE workspace_id = :w AND status = 'open' ORDER BY created_at"""
        ),
        {"w": workspace_id},
    )
    return [dict(r) for r in rows.mappings()]


async def close_conflict(
    s: AsyncSession, conflict_id: uuid.UUID, user_id: uuid.UUID, resolution: str
) -> dict[str, Any] | None:
    """Marks an open conflict resolved if the user belongs to its workspace."""
    row = await s.execute(
        text(
            """UPDATE sync_conflicts c SET status = :res, resolved_at = now()
            FROM workspace_members m
            WHERE c.id = :id AND c.status = 'open'
              AND m.workspace_id = c.workspace_id AND m.user_id = :u
            RETURNING c.workspace_id, c.entity_type, c.entity_id"""
        ),
        {"id": conflict_id, "u": user_id, "res": resolution},
    )
    found = row.mappings().first()
    return dict(found) if found else None
