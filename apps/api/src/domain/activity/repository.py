"""Append-only activity history (Spec 4.7). Metadata holds field names and status values
only, never titles or notes, so it is safe to show and to export."""

import json
import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.common.ids import new_uuid7
from src.domain.sync.repository import record_change

# Fields whose before/after values are short enums, so the timeline can show the move.
TRACKED = ("status", "stage_id", "state", "decision", "due_at")


def describe(
    operation: str, changes: dict[str, Any], before: dict[str, Any] | None
) -> tuple[str, dict[str, Any]]:
    if operation in ("create", "delete"):
        return f"{operation}d", {}
    meta: dict[str, Any] = {"fields": sorted(changes)}
    for key in TRACKED:
        if key in changes and before is not None and str(before.get(key)) != str(changes[key]):
            meta[key] = {"from": _wire(before.get(key)), "to": _wire(changes[key])}
    action = {
        "stage_id": "moved",
        "state": "finalized" if changes.get("state") == "finalized" else "updated",
        "status": "completed" if changes.get("status") == "complete" else "status_changed",
    }
    for key in ("stage_id", "status", "state"):
        if key in meta:
            return action[key], meta
    return "updated", meta


def _wire(v: Any) -> Any:
    if isinstance(v, datetime):
        return v.astimezone(UTC).isoformat()
    return None if v is None else str(v)


async def record(
    s: AsyncSession,
    workspace_id: uuid.UUID,
    actor_id: uuid.UUID,
    entity_type: str,
    entity_id: uuid.UUID,
    action: str,
    metadata: dict[str, Any],
) -> None:
    eid = new_uuid7()
    now = datetime.now(UTC)
    await s.execute(
        text(
            """INSERT INTO activity_events
            (id, workspace_id, actor_id, entity_type, entity_id, action, metadata, created_at)
            VALUES (:id, :w, :a, :t, :e, :act, CAST(:m AS jsonb), :at)"""
        ),
        {"id": eid, "w": workspace_id, "a": actor_id, "t": entity_type, "e": entity_id,
         "act": action, "m": json.dumps(metadata), "at": now},
    )  # fmt: skip
    await record_change(
        s, workspace_id, "activity_event", eid, "create", 1,
        {"id": str(eid), "entity_type": entity_type, "entity_id": str(entity_id),
         "action": action, "metadata": metadata, "actor_id": str(actor_id),
         "created_at": now.isoformat()},
    )  # fmt: skip


async def for_entity(
    s: AsyncSession, workspace_id: uuid.UUID, entity_id: uuid.UUID | None, limit: int = 200
) -> list[dict[str, Any]]:
    rows = await s.execute(
        text(
            """SELECT id, entity_type, entity_id, action, metadata, actor_id, created_at
            FROM activity_events WHERE workspace_id = :w
              AND (CAST(:e AS uuid) IS NULL OR entity_id = :e)
            ORDER BY created_at DESC, id DESC LIMIT :lim"""
        ),
        {"w": workspace_id, "e": entity_id, "lim": limit},
    )
    return [dict(r) for r in rows.mappings()]
