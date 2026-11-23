"""Reminders for dated records other than tasks: grant and scholarship deadlines, milestone due
dates and time-block starts. Tasks keep their own rules in repository.py.

Each source says where its date lives and which statuses mean "nothing left to remind about".
The worker re-reads the record before sending, so a moved date reschedules the reminder and a
finished or deleted record cancels it, without hooks in every write path.
"""

import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.common.errors import DomainError, ErrorCode
from src.domain.common.ids import new_uuid7
from src.domain.notifications import repository, service


@dataclass(frozen=True)
class Source:
    table: str
    name_column: str
    date_column: str
    closed: frozenset[str]
    label: str


SOURCES: dict[str, Source] = {
    "funding_opportunity": Source(
        "funding_opportunities", "title", "deadline_at",
        frozenset({"submitted", "awarded", "rejected", "not_eligible"}), "Grant deadline",
    ),
    "scholarship_application": Source(
        "scholarship_applications", "university", "deadline_at",
        frozenset({"submitted", "under_review", "accepted", "rejected"}), "Scholarship deadline",
    ),
    "milestone": Source(
        "milestones", "title", "due_at", frozenset({"complete", "archived"}), "Milestone due",
    ),
    "time_block": Source(
        "time_blocks", "title", "starts_at", frozenset({"complete", "skipped", "cancelled"}),
        "Starting soon",
    ),
}  # fmt: skip

NOT_FOUND = DomainError(ErrorCode.NOT_FOUND, "Record not found.")


def source(entity_type: str) -> Source:
    found = SOURCES.get(entity_type)
    if found is None:
        raise DomainError(
            ErrorCode.VALIDATION_ERROR, f"Reminders are not available for {entity_type}."
        )
    return found


async def load(
    s: AsyncSession, entity_type: str, entity_id: uuid.UUID, user_id: uuid.UUID | None = None
) -> dict[str, Any] | None:
    """The record's workspace, name, date and status; None if it is gone (or not the user's)."""
    src = source(entity_type)
    member = (
        " AND EXISTS (SELECT 1 FROM workspace_members m WHERE m.workspace_id = r.workspace_id"
        " AND m.user_id = :u)"
        if user_id
        else ""
    )
    row = await s.execute(
        text(
            f"""SELECT r.id, r.workspace_id, r.{src.name_column} AS name, r.{src.date_column} AS at,
              r.status::text AS status
            FROM {src.table} r WHERE r.id = :i AND r.deleted_at IS NULL{member}"""
        ),
        {"i": entity_id, **({"u": user_id} if user_id else {})},
    )
    found = row.mappings().first()
    return dict(found) if found else None


def title_for(entity_type: str, record: dict[str, Any]) -> str:
    return f"{SOURCES[entity_type].label}: {record['name']}"[:240]


async def set_reminders(
    s: AsyncSession, entity_type: str, record: dict[str, Any], specs: list[str], urgency: str,
    channel: str, now: datetime,
) -> list[dict[str, Any]]:  # fmt: skip
    """Replaces the record's open reminders. Callers commit."""
    src = SOURCES[entity_type]
    if record["status"] in src.closed and specs:
        raise DomainError(
            ErrorCode.DOMAIN_RULE_VIOLATION, "There is nothing left to remind you about for this."
        )
    if record["at"] is None and specs:
        raise DomainError(ErrorCode.DOMAIN_RULE_VIOLATION, "Set a date before adding reminders.")
    tz, quiet = await repository.owner_settings(s, record["workspace_id"])
    await repository.cancel_for_entity(s, entity_type, record["id"])
    rows = []
    for spec in specs:
        when = service.respect_quiet_hours(
            service.remind_at(record["at"], spec, tz), urgency, quiet, tz
        )
        if when <= now:
            continue
        res = await s.execute(
            text(
                f"""INSERT INTO notifications (id, workspace_id, entity_type, entity_id, title,
                  remind_at, urgency, channel, offset_spec)
                VALUES (:id, :w, :t, :e, :title, :at, :u, :c, :spec)
                RETURNING {repository.COLUMNS}"""
            ),
            {"id": new_uuid7(), "w": record["workspace_id"], "t": entity_type, "e": record["id"],
             "title": title_for(entity_type, record), "at": when, "u": urgency, "c": channel,
             "spec": spec},
        )  # fmt: skip
        rows.append(dict(res.mappings().one()))
    return rows


async def list_scheduled(s: AsyncSession, workspace_id: uuid.UUID) -> list[dict[str, Any]]:
    """Every reminder still waiting to go out, so pages can show what is set on each record."""
    rows = await s.execute(
        text(
            f"""SELECT {repository.COLUMNS} FROM notifications
            WHERE workspace_id = :w AND deleted_at IS NULL
              AND delivery_status IN ('scheduled', 'snoozed')
            ORDER BY remind_at"""
        ),
        {"w": workspace_id},
    )
    return [dict(r) for r in rows.mappings()]


@dataclass(frozen=True)
class Check:
    """What the worker should do with a due reminder for a non-task record."""

    action: str  # "send", "cancel" or "reschedule"
    when: datetime | None = None
    title: str | None = None


async def check_due(
    s: AsyncSession, row: dict[str, Any], tz: Any, quiet: service.QuietHours | None, now: datetime
) -> Check:
    record = await load(s, row["entity_type"], row["entity_id"])
    src = SOURCES[row["entity_type"]]
    if record is None or record["at"] is None or record["status"] in src.closed:
        return Check("cancel")
    title = title_for(row["entity_type"], record)
    if row.get("offset_spec") and row["delivery_status"] == "scheduled":
        planned = service.respect_quiet_hours(
            service.remind_at(record["at"], row["offset_spec"], tz), row["urgency"], quiet, tz
        )
        # The date moved later since this was scheduled: wait for the new time.
        if planned > now and abs((planned - row["remind_at"]).total_seconds()) > 60:
            return Check("reschedule", planned, title)
    return Check("send", title=title)
