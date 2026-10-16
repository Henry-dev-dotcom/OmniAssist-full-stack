from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from src.api.dependencies import request_id_middleware
from src.api.error_handlers import register_error_handlers
from src.api.routes import (
    exports,
    notifications,
    projects,
    push,
    research,
    sync,
    tasks,
    time_blocks,
    users,
    workspaces,
)
from src.auth import routes as auth_routes
from src.auth.dependencies import Session
from src.config import settings
from src.infrastructure.observability.logging import configure_logging

configure_logging(settings.log_level)

app = FastAPI(title="OmniAssist API", version="0.1.0")
app.middleware("http")(request_id_middleware)
# The web client runs on another origin; bearer tokens, not cookies, so no credentials.
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["X-Request-ID"],
)
register_error_handlers(app)

for router in (
    auth_routes.router,
    users.router,
    workspaces.router,
    projects.router,
    research.router,
    tasks.router,
    notifications.router,
    time_blocks.router,
    sync.router,
    exports.router,
    push.router,
):
    app.include_router(router, prefix="/api/v1")


@app.get("/api/v1/health/live")
def live() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/v1/health/ready")
async def ready(session: Session) -> JSONResponse:
    """Ready only when the database answers, so a load balancer skips a broken instance."""
    try:
        await session.execute(text("SELECT 1"))
    except (OSError, SQLAlchemyError):
        return JSONResponse({"status": "unavailable"}, status_code=503)
    return JSONResponse({"status": "ok"})
