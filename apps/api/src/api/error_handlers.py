import logging
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from src.domain.common.errors import HTTP_STATUS, RETRYABLE, DomainError, ErrorCode

log = logging.getLogger(__name__)


def error_response(
    request: Request, code: ErrorCode, message: str, details: dict[str, Any] | None = None
) -> JSONResponse:
    return JSONResponse(
        status_code=HTTP_STATUS[code],
        content={
            "error": {
                "code": code.value,
                "message": message,
                "details": details or {},
                "request_id": getattr(request.state, "request_id", None),
                "retryable": code in RETRYABLE,
            }
        },
    )


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(DomainError)
    async def _domain(request: Request, exc: DomainError) -> JSONResponse:
        return error_response(request, exc.code, exc.message, exc.details)

    @app.exception_handler(RequestValidationError)
    async def _validation(request: Request, exc: RequestValidationError) -> JSONResponse:
        fields = [{"field": ".".join(map(str, e["loc"])), "issue": e["msg"]} for e in exc.errors()]
        return error_response(
            request, ErrorCode.VALIDATION_ERROR, "Request is invalid.", {"fields": fields}
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http(request: Request, exc: StarletteHTTPException) -> JSONResponse:
        by_status = {s: c for c, s in HTTP_STATUS.items() if c != ErrorCode.IDEMPOTENCY_KEY_REUSED}
        code = by_status.get(exc.status_code, ErrorCode.INTERNAL_ERROR)
        return error_response(request, code, "Request failed.")

    @app.exception_handler(Exception)
    async def _unhandled(request: Request, exc: Exception) -> JSONResponse:
        log.error("unhandled error", exc_info=exc)
        return error_response(request, ErrorCode.INTERNAL_ERROR, "Something went wrong. Try again.")
