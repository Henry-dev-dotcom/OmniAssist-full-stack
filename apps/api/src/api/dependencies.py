import uuid
from collections.abc import Awaitable, Callable

from fastapi import Request, Response

from src.infrastructure.observability.logging import request_id_var


async def request_id_middleware(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    request_id = f"req_{uuid.uuid4()}"
    request.state.request_id = request_id
    token = request_id_var.set(request_id)
    try:
        response = await call_next(request)
    finally:
        request_id_var.reset(token)
    response.headers["X-Request-ID"] = request_id
    return response
