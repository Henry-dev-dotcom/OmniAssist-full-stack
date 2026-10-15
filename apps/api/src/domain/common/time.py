from datetime import UTC, datetime
from typing import Protocol


class Clock(Protocol):
    def now(self) -> datetime: ...


class SystemClock:
    def now(self) -> datetime:
        return datetime.now(UTC)


class FixedClock:
    def __init__(self, at: datetime) -> None:
        self._at = at

    def now(self) -> datetime:
        return self._at


def to_utc_iso(value: datetime) -> str:
    """Serialize as ISO 8601 UTC with a trailing Z. Rejects naive datetimes."""
    if value.tzinfo is None:
        raise ValueError("naive datetime not allowed; attach a timezone")
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def from_utc_iso(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("timestamp must carry a UTC offset")
    return parsed.astimezone(UTC)
