from datetime import datetime
from enum import StrEnum
from typing import Annotated, Any

from pydantic import AfterValidator


def _aware(v: datetime) -> datetime:
    if v.tzinfo is None:
        raise ValueError("timestamp must include a UTC offset")
    return v


# Timestamps on the wire must carry an offset, so no device's local clock leaks in.
Utc = Annotated[datetime, AfterValidator(_aware)]


def plain(values: dict[str, Any]) -> dict[str, Any]:
    """Enum members become their string values, so the database driver accepts them."""
    return {k: (v.value if isinstance(v, StrEnum) else v) for k, v in values.items()}
