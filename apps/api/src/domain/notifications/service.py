"""Pure reminder rules: offsets, time zones, quiet hours. No database here."""

from dataclasses import dataclass
from datetime import UTC, datetime, time, timedelta
from typing import Any
from zoneinfo import ZoneInfo

PRESETS = {"at_due": 0, "15m": 15, "1h": 60, "1d": 1440}
MORNING = {"morning_of": 0, "morning_before": 1}  # days before the due date
MORNING_HOUR = 9
MAX_CUSTOM_MINUTES = 60 * 24 * 90
URGENCIES = ("low", "normal", "high", "critical")
CLOSED_TASK_STATES = frozenset({"complete", "cancelled", "archived"})


def validate_offset(spec: str) -> str:
    if spec in PRESETS or spec in MORNING:
        return spec
    if spec.startswith("custom:"):
        try:
            minutes = int(spec[7:])
        except ValueError:
            raise ValueError(f"bad reminder offset {spec!r}") from None
        if 0 <= minutes <= MAX_CUSTOM_MINUTES:
            return spec
    raise ValueError(f"bad reminder offset {spec!r}")


def remind_at(due_at: datetime, spec: str, tz: ZoneInfo) -> datetime:
    """When to remind for [due_at]. Morning offsets use 09:00 on the user's calendar day."""
    if due_at.tzinfo is None:
        raise ValueError("due_at must include a UTC offset")
    spec = validate_offset(spec)
    if spec in MORNING:
        day = due_at.astimezone(tz).date() - timedelta(days=MORNING[spec])
        local = datetime.combine(day, time(MORNING_HOUR), tzinfo=tz)
        return local.astimezone(UTC)
    minutes = PRESETS[spec] if spec in PRESETS else int(spec[7:])
    return due_at.astimezone(UTC) - timedelta(minutes=minutes)


@dataclass(frozen=True)
class QuietHours:
    start: time
    end: time

    def window_end_after(self, moment: datetime, tz: ZoneInfo) -> datetime | None:
        """End of the quiet window that holds [moment], or None when it is outside one."""
        if self.start == self.end:
            return None
        local = moment.astimezone(tz)
        t = local.time()
        if self.start < self.end:
            inside, end_day = self.start <= t < self.end, local.date()
        elif t >= self.start:
            inside, end_day = True, local.date() + timedelta(days=1)
        else:
            inside, end_day = t < self.end, local.date()
        if not inside:
            return None
        return datetime.combine(end_day, self.end, tzinfo=tz).astimezone(UTC)


def _hhmm(raw: Any) -> time:
    h, m = str(raw).split(":")
    return time(int(h), int(m))


def quiet_hours(preferences: dict[str, Any] | None) -> QuietHours | None:
    """Reads preferences.notifications.quiet_hours = {"start": "22:00", "end": "07:00"}."""
    q = ((preferences or {}).get("notifications") or {}).get("quiet_hours")
    return QuietHours(_hhmm(q["start"]), _hhmm(q["end"])) if q else None


def validate_preferences(preferences: dict[str, Any]) -> None:
    """Raises ValueError for unusable notification settings."""
    try:
        quiet_hours(preferences)
    except (KeyError, ValueError, TypeError):
        raise ValueError("quiet_hours needs start and end as HH:MM") from None


def respect_quiet_hours(
    when: datetime, urgency: str, quiet: QuietHours | None, tz: ZoneInfo
) -> datetime:
    """Critical reminders always fire on time. Others wait until quiet hours end."""
    if quiet is None or urgency == "critical":
        return when
    return quiet.window_end_after(when, tz) or when
