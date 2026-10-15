from typing import Any

from fastapi import Request


def envelope(request: Request, data: Any, **meta: Any) -> dict[str, Any]:
    """Success envelope: {"data": ..., "meta": {"request_id": ...}} (error_codes.md)."""
    return {
        "data": data,
        "meta": {"request_id": getattr(request.state, "request_id", None), **meta},
    }
