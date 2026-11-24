import logging
import uuid
from collections.abc import Awaitable, Callable

from fastapi import Request, Response

from src.api.error_handlers import error_response
from src.domain.common.errors import ErrorCode
from src.infrastructure.observability.logging import request_id_var

log = logging.getLogger(__name__)


async def request_id_middleware(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    request_id = f"req_{uuid.uuid4()}"
    request.state.request_id = request_id
    token = request_id_var.set(request_id)
    try:
        response = await call_next(request)
    except Exception as exc:
        # FastAPI's catch-all handler runs outside CORSMiddleware, so its 500 reached the
        # browser without CORS headers and showed as "Failed to fetch". Answering here, inside
        # CORS, lets the web app read the error and its request id.
        log.error("unhandled error", exc_info=exc)
        response = error_response(
            request, ErrorCode.INTERNAL_ERROR, "Something went wrong. Try again."
        )
    finally:
        request_id_var.reset(token)
    response.headers["X-Request-ID"] = request_id
    # API responses are data, never pages: no sniffing, framing or referrer leaks.
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    return response
