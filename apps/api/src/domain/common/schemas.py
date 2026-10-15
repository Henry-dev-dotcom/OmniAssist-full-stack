from enum import StrEnum
from typing import Any


def plain(values: dict[str, Any]) -> dict[str, Any]:
    """Enum members become their string values, so the database driver accepts them."""
    return {k: (v.value if isinstance(v, StrEnum) else v) for k, v in values.items()}
