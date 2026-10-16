"""Sends due reminders. `run_once` is the unit of work, `main` just repeats it."""

import asyncio
import logging
from dataclasses import dataclass
from datetime import UTC, datetime

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.notifications import repository, service
from src.infrastructure.notifications.gateway import (
    DeliveryError,
    InAppGateway,
    Message,
    NotificationGateway,
)

log = logging.getLogger("omni.reminders")


@dataclass
class DispatchResult:
    sent: int = 0
    failed: int = 0
    deferred: int = 0
    cancelled: int = 0


async def _still_relevant(s: AsyncSession, entity_type: str, entity_id: object) -> bool:
    if entity_type != "task":
        return True
    row = await s.execute(
        text("SELECT status::text FROM tasks WHERE id = :i AND deleted_at IS NULL"),
        {"i": entity_id},
    )
    status = row.scalar_one_or_none()
    return status is not None and status not in service.CLOSED_TASK_STATES


async def dispatch_due(
    s: AsyncSession, gateway: NotificationGateway, now: datetime | None = None, batch: int = 100
) -> DispatchResult:
    """Delivers reminders that are due. The caller commits.

    Rows are locked with SKIP LOCKED, so two workers never send the same reminder."""
    now = now or datetime.now(UTC)
    due = await s.execute(
        text(
            """SELECT n.id, n.workspace_id, n.entity_type, n.entity_id, n.title, n.urgency,
              n.channel, n.delivery_status, u.timezone, u.preferences, u.id AS user_id
            FROM notifications n JOIN workspaces w ON w.id = n.workspace_id
            JOIN users u ON u.id = w.owner_id
            WHERE n.deleted_at IS NULL AND (
              (n.delivery_status = 'scheduled' AND n.remind_at <= :now) OR
              (n.delivery_status = 'snoozed' AND n.snoozed_until <= :now))
            ORDER BY n.remind_at LIMIT :n FOR UPDATE OF n SKIP LOCKED"""
        ),
        {"now": now, "n": batch},
    )
    result = DispatchResult()
    from zoneinfo import ZoneInfo

    for r in [dict(x) for x in due.mappings()]:
        if not await _still_relevant(s, r["entity_type"], r["entity_id"]):
            await repository.cancel_for_entity(s, r["entity_type"], r["entity_id"])
            result.cancelled += 1
            continue
        tz = ZoneInfo(r["timezone"])
        later = service.respect_quiet_hours(
            now, r["urgency"], service.quiet_hours(r["preferences"]), tz
        )
        if later > now:  # quiet hours began after this was scheduled
            col = "snoozed_until" if r["delivery_status"] == "snoozed" else "remind_at"
            await s.execute(
                text(f"UPDATE notifications SET {col} = :t, updated_at = now() WHERE id = :i"),
                {"t": later, "i": r["id"]},
            )
            result.deferred += 1
            continue
        try:
            await gateway.send(
                Message(str(r["id"]), r["channel"], r["urgency"], r["title"], str(r["user_id"]))
            )
            status, reason = "sent", None
            result.sent += 1
        except DeliveryError as e:
            status, reason = "failed", str(e)[:300]
            result.failed += 1
        await s.execute(
            text(
                """UPDATE notifications SET delivery_status = :st, failure_reason = :why,
                  sent_at = :now, snoozed_until = NULL,
                  read_at = CASE WHEN delivery_status = 'snoozed' THEN NULL
                    ELSE read_at END, updated_at = now(), version = version + 1
                WHERE id = :i"""
            ),
            {"st": status, "why": reason, "now": now, "i": r["id"]},
        )
    return result


async def main(interval_seconds: int = 30) -> None:  # pragma: no cover - process loop
    from src.config import settings
    from src.infrastructure.database.session import SessionFactory
    from src.infrastructure.notifications.webpush import WebPushGateway

    gateway: NotificationGateway = (
        WebPushGateway(SessionFactory, settings.vapid_private_key, settings.vapid_subject)
        if settings.vapid_private_key
        else InAppGateway()
    )
    while True:
        try:
            async with SessionFactory() as s:
                res = await dispatch_due(s, gateway)
                await s.commit()
            if res.sent or res.failed:
                log.info("reminders sent=%s failed=%s", res.sent, res.failed)
        except Exception:
            log.exception("reminder pass failed")
        await asyncio.sleep(interval_seconds)


if __name__ == "__main__":  # pragma: no cover
    asyncio.run(main())
