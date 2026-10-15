from datetime import UTC, datetime, time
from zoneinfo import ZoneInfo

import pytest

from src.domain.notifications import service
from src.domain.notifications.service import QuietHours

ACCRA = ZoneInfo("Africa/Accra")  # UTC+0, no DST
NY = ZoneInfo("America/New_York")
NIGHT = QuietHours(time(22, 0), time(7, 0))


def utc(*a: int) -> datetime:
    return datetime(*a, tzinfo=UTC)


def test_preset_offsets_subtract_from_due() -> None:
    due = utc(2026, 10, 20, 12, 0)
    assert service.remind_at(due, "at_due", ACCRA) == due
    assert service.remind_at(due, "15m", ACCRA) == utc(2026, 10, 20, 11, 45)
    assert service.remind_at(due, "1h", ACCRA) == utc(2026, 10, 20, 11, 0)
    assert service.remind_at(due, "1d", ACCRA) == utc(2026, 10, 19, 12, 0)
    assert service.remind_at(due, "custom:90", ACCRA) == utc(2026, 10, 20, 10, 30)


def test_morning_offsets_use_the_users_calendar_day() -> None:
    # Due 03:30 UTC on 21 Oct is 23:30 on 20 Oct in New York (EDT, UTC-4).
    due = utc(2026, 10, 21, 3, 30)
    assert service.remind_at(due, "morning_of", NY) == utc(2026, 10, 20, 13, 0)
    assert service.remind_at(due, "morning_before", NY) == utc(2026, 10, 19, 13, 0)
    assert service.remind_at(due, "morning_of", ACCRA) == utc(2026, 10, 21, 9, 0)


def test_morning_follows_dst_change() -> None:
    # New York leaves DST on 1 Nov 2026: 09:00 is UTC-5 afterwards.
    due = utc(2026, 11, 2, 20, 0)
    assert service.remind_at(due, "morning_of", NY) == utc(2026, 11, 2, 14, 0)
    assert service.remind_at(due, "morning_before", NY) == utc(2026, 11, 1, 14, 0)
    # The day before the change is still on summer time (UTC-4).
    assert service.remind_at(utc(2026, 11, 1, 20, 0), "morning_before", NY) == utc(
        2026, 10, 31, 13, 0
    )


@pytest.mark.parametrize("bad", ["", "2h", "custom:", "custom:-5", "custom:x", "custom:999999999"])
def test_bad_offsets_are_rejected(bad: str) -> None:
    with pytest.raises(ValueError):
        service.validate_offset(bad)


def test_naive_due_is_rejected() -> None:
    with pytest.raises(ValueError):
        service.remind_at(datetime(2026, 10, 20, 12), "1h", ACCRA)


def test_quiet_hours_wrap_midnight_and_defer_to_the_end() -> None:
    assert service.respect_quiet_hours(utc(2026, 10, 20, 23, 30), "normal", NIGHT, ACCRA) == utc(
        2026, 10, 21, 7, 0
    )
    assert service.respect_quiet_hours(utc(2026, 10, 21, 3, 0), "normal", NIGHT, ACCRA) == utc(
        2026, 10, 21, 7, 0
    )


def test_outside_quiet_hours_is_unchanged_and_edges_are_half_open() -> None:
    noon = utc(2026, 10, 20, 12, 0)
    assert service.respect_quiet_hours(noon, "normal", NIGHT, ACCRA) == noon
    seven = utc(2026, 10, 20, 7, 0)
    assert service.respect_quiet_hours(seven, "normal", NIGHT, ACCRA) == seven
    ten_pm = utc(2026, 10, 20, 22, 0)
    assert service.respect_quiet_hours(ten_pm, "low", NIGHT, ACCRA) == utc(2026, 10, 21, 7, 0)


def test_critical_ignores_quiet_hours() -> None:
    at = utc(2026, 10, 20, 23, 30)
    assert service.respect_quiet_hours(at, "critical", NIGHT, ACCRA) == at


def test_quiet_hours_use_local_time_not_utc() -> None:
    # 03:00 UTC is 23:00 in New York: inside quiet hours there, ends 07:00 local = 11:00 UTC.
    at = utc(2026, 10, 21, 3, 0)
    assert service.respect_quiet_hours(at, "normal", NIGHT, NY) == utc(2026, 10, 21, 11, 0)


def test_same_day_window_and_empty_window() -> None:
    lunch = QuietHours(time(12, 0), time(13, 0))
    assert service.respect_quiet_hours(utc(2026, 10, 20, 12, 30), "normal", lunch, ACCRA) == utc(
        2026, 10, 20, 13, 0
    )
    none = QuietHours(time(8, 0), time(8, 0))
    at = utc(2026, 10, 20, 8, 0)
    assert service.respect_quiet_hours(at, "normal", none, ACCRA) == at


def test_preferences_parse_and_validate() -> None:
    q = service.quiet_hours({"notifications": {"quiet_hours": {"start": "22:00", "end": "07:30"}}})
    assert q == QuietHours(time(22, 0), time(7, 30))
    assert service.quiet_hours({}) is None
    service.validate_preferences({"theme": "dark"})
    with pytest.raises(ValueError):
        service.validate_preferences({"notifications": {"quiet_hours": {"start": "late"}}})
