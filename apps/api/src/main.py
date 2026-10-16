from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from src.api.dependencies import request_id_middleware
from src.api.error_handlers import register_error_handlers
from src.api.routes import (
    exports,
    notifications,
    projects,
    research,
    sync,
    tasks,
    time_blocks,
    users,
    workspaces,
)
from src.auth import routes as auth_routes
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
):
    app.include_router(router, prefix="/api/v1")


@app.get("/api/v1/health/live")
def live() -> dict[str, str]:
    return {"status": "ok"}


# shortcut: ready mirrors live, wire DB check when Task 6 adds the engine
@app.get("/api/v1/health/ready")
def ready() -> dict[str, str]:
    return {"status": "ok"}
