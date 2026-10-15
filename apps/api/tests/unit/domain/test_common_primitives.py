import uuid
from datetime import UTC, datetime, timedelta, timezone

import pytest

from src.domain.common.errors import DomainError, ErrorCode
from src.domain.common.ids import new_uuid7
from src.domain.common.time import FixedClock, SystemClock, from_utc_iso, to_utc_iso


def test_uuid7_version_and_variant() -> None:
    u = new_uuid7()
    assert u.version == 7
    assert u.variant == uuid.RFC_4122


def test_uuid7_sorts_by_creation_time(monkeypatch: pytest.MonkeyPatch) -> None:
    import src.domain.common.ids as ids

    monkeypatch.setattr(ids.time, "time_ns", lambda: 1_000_000_000_000)
    a = new_uuid7()
    monkeypatch.setattr(ids.time, "time_ns", lambda: 2_000_000_000_000)
    assert a < new_uuid7()


def test_fixed_clock_is_deterministic() -> None:
    at = datetime(2026, 10, 14, tzinfo=UTC)
    assert FixedClock(at).now() == at
    assert SystemClock().now().tzinfo is not None


def test_utc_serialization() -> None:
    berlin = timezone(timedelta(hours=2))
    assert to_utc_iso(datetime(2026, 10, 14, 20, tzinfo=berlin)) == "2026-10-14T18:00:00Z"
    assert from_utc_iso("2026-10-14T18:00:00Z") == datetime(2026, 10, 14, 18, tzinfo=UTC)


def test_naive_datetime_rejected() -> None:
    with pytest.raises(ValueError):
        to_utc_iso(datetime(2026, 10, 14))
    with pytest.raises(ValueError):
        from_utc_iso("2026-10-14T18:00:00")


def test_domain_error_is_framework_free() -> None:
    e = DomainError(ErrorCode.RATE_LIMITED, "Slow down.")
    assert e.retryable and not isinstance(e, ImportError)
    assert "fastapi" not in type(e).__mro__[1].__module__
