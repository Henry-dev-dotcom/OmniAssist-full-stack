import uuid
from datetime import datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.common.errors import DomainError, ErrorCode
from src.domain.common.ids import new_uuid7
from src.domain.notifications import service

COLUMNS = (
    "id, workspace_id, entity_type, entity_id, title, remind_at, urgency, channel, "
    "delivery_status, offset_spec, snoozed_until, sent_at, read_at, failure_reason"
)
OPEN = ("scheduled", "snoozed")
# action -> (statuses it may start from, status it leads to)
ACTIONS: dict[str, tuple[tuple[str, ...], str | None]] = {
    "dismiss": (("scheduled", "sent", "snoozed", "failed"), "dismissed"),
    "snooze": (("scheduled", "sent", "snoozed"), "snoozed"),
    "ack": (("sent",), "acted_on"),
    "read": (("sent", "failed", "dismissed", "acted_on"), None),
}


async def owner_settings(
    s: AsyncSession, workspace_id: uuid.UUID
) -> tuple[ZoneInfo, service.QuietHours | None]:
    row = await s.execute(
        text(
            """SELECT u.timezone, u.preferences FROM workspaces w
            JOIN users u ON u.id = w.owner_id WHERE w.id = :w"""
        ),
        {"w": workspace_id},
    )
    r = row.mappings().one()
    return ZoneInfo(r["timezone"]), service.quiet_hours(r["preferences"])


async def cancel_for_entity(s: AsyncSession, entity_type: str, entity_id: uuid.UUID) -> int:
    res = await s.execute(
        text(
            """UPDATE notifications SET delivery_status = 'cancelled', updated_at = now(),
              version = version + 1
            WHERE entity_type = :t AND entity_id = :i AND delivery_status IN ('scheduled','snoozed')
              AND deleted_at IS NULL"""
        ),
        {"t": entity_type, "i": entity_id},
    )
    return int(getattr(res, "rowcount", 0) or 0)


def _plan(
    task: dict[str, Any], specs: list[str], urgency: str, tz: ZoneInfo,
    quiet: service.QuietHours | None, now: datetime,
) -> list[tuple[str, datetime]]:  # fmt: skip
    """(offset, when) pairs that are still in the future after quiet-hours shifting."""
    out = []
    for spec in specs:
        when = service.respect_quiet_hours(
            service.remind_at(task["due_at"], spec, tz), urgency, quiet, tz
        )
        if when > now:
            out.append((spec, when))
    return out


async def set_task_reminders(
    s: AsyncSession, task: dict[str, Any], specs: list[str], urgency: str, channel: str,
    now: datetime,
) -> list[dict[str, Any]]:  # fmt: skip
    """Replaces a task's open reminders. Callers commit."""
    if task["status"] in service.CLOSED_TASK_STATES:
        raise DomainError(
            ErrorCode.DOMAIN_RULE_VIOLATION, "A finished task cannot receive new reminders."
        )
    if task["due_at"] is None and specs:
        raise DomainError(
            ErrorCode.DOMAIN_RULE_VIOLATION, "Set a due date before adding reminders."
        )
    tz, quiet = await owner_settings(s, task["workspace_id"])
    await cancel_for_entity(s, "task", task["id"])
    rows = []
    for spec, when in _plan(task, specs, urgency, tz, quiet, now) if specs else []:
        res = await s.execute(
            text(
                f"""INSERT INTO notifications (id, workspace_id, entity_type, entity_id, title,
                  remind_at, urgency, channel, offset_spec)
                VALUES (:id, :w, 'task', :t, :title, :at, :u, :c, :spec)
                RETURNING {COLUMNS}"""
            ),
            {"id": new_uuid7(), "w": task["workspace_id"], "t": task["id"], "title": task["title"],
             "at": when, "u": urgency, "c": channel, "spec": spec},
        )  # fmt: skip
        rows.append(dict(res.mappings().one()))
    return rows


async def sync_task_reminders(s: AsyncSession, task: dict[str, Any], now: datetime) -> None:
    """Keeps open reminders in step with a task that just changed (Spec 4.5).

    Finished or undated tasks lose their reminders. A moved due date recalculates them."""
    if task["status"] in service.CLOSED_TASK_STATES or task["due_at"] is None:
        await cancel_for_entity(s, "task", task["id"])
        return
    open_rows = await s.execute(
        text(
            """SELECT offset_spec, urgency, channel FROM notifications
            WHERE entity_type = 'task' AND entity_id = :i AND delivery_status = 'scheduled'
              AND deleted_at IS NULL"""
        ),
        {"i": task["id"]},
    )
    found = [dict(r) for r in open_rows.mappings()]
    if not found:
        return
    first = found[0]
    specs = [f["offset_spec"] for f in found if f["offset_spec"]]
    await set_task_reminders(s, task, specs, first["urgency"], first["channel"], now)


async def get_for_user(
    s: AsyncSession, notification_id: uuid.UUID, user_id: uuid.UUID
) -> dict[str, Any] | None:
    row = await s.execute(
        text(
            f"""SELECT {", ".join("n." + c.strip() for c in COLUMNS.split(","))}
            FROM notifications n JOIN workspace_members m ON m.workspace_id = n.workspace_id
            WHERE n.id = :i AND m.user_id = :u AND n.deleted_at IS NULL"""
        ),
        {"i": notification_id, "u": user_id},
    )
    found = row.mappings().first()
    return dict(found) if found else None


async def list_for_workspace(
    s: AsyncSession, workspace_id: uuid.UUID, status: str | None, unread: bool, limit: int = 100
) -> list[dict[str, Any]]:
    where = ["workspace_id = :w", "deleted_at IS NULL", "delivery_status <> 'cancelled'",
             "delivery_status <> 'scheduled'"]  # fmt: skip
    params: dict[str, Any] = {"w": workspace_id, "n": limit}
    if status:
        where.append("delivery_status = :s")
        params["s"] = status
    if unread:
        where.append("read_at IS NULL")
    rows = await s.execute(
        text(
            f"SELECT {COLUMNS} FROM notifications WHERE {' AND '.join(where)} "
            "ORDER BY remind_at DESC LIMIT :n"
        ),
        params,
    )
    return [dict(r) for r in rows.mappings()]


async def list_for_entity(
    s: AsyncSession, entity_type: str, entity_id: uuid.UUID
) -> list[dict[str, Any]]:
    rows = await s.execute(
        text(
            f"""SELECT {COLUMNS} FROM notifications WHERE entity_type = :t AND entity_id = :i
            AND deleted_at IS NULL AND delivery_status <> 'cancelled' ORDER BY remind_at"""
        ),
        {"t": entity_type, "i": entity_id},
    )
    return [dict(r) for r in rows.mappings()]


async def apply_action(
    s: AsyncSession, row: dict[str, Any], action: str, now: datetime, minutes: int = 10
) -> dict[str, Any]:
    allowed, target = ACTIONS[action]
    if row["delivery_status"] not in allowed:
        raise DomainError(
            ErrorCode.DOMAIN_RULE_VIOLATION,
            f"A {row['delivery_status']} notification cannot be changed that way.",
        )
    sets = ["updated_at = now()", "version = version + 1"]
    params: dict[str, Any] = {"i": row["id"]}
    if action == "read":
        sets.append("read_at = COALESCE(read_at, :now)")
    elif action == "snooze":
        sets += ["delivery_status = 'snoozed'", "snoozed_until = :until", "resolved_at = NULL"]
        params["until"] = now + timedelta(minutes=minutes)
    else:
        sets += ["delivery_status = :st", "resolved_at = :now", "read_at = COALESCE(read_at, :now)"]
        params["st"] = target
    params["now"] = now
    res = await s.execute(
        text(f"UPDATE notifications SET {', '.join(sets)} WHERE id = :i RETURNING {COLUMNS}"),
        params,
    )
    return dict(res.mappings().one())
