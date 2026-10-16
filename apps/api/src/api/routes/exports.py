import uuid
from datetime import UTC, datetime, timedelta
from typing import Annotated, Any, Literal

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Request, Response
from pydantic import BaseModel
from sqlalchemy import text

from src.api.responses import envelope
from src.auth.dependencies import CurrentActor, Session
from src.config import settings
from src.domain.common.errors import DomainError, ErrorCode
from src.domain.exports import service
from src.domain.workspaces.service import require_member
from src.infrastructure.database.session import SessionFactory

router = APIRouter(prefix="/exports", tags=["exports"])

NOT_FOUND = DomainError(ErrorCode.NOT_FOUND, "Export not found.")
MAX_EXPORTS_PER_HOUR = 10  # exports are heavy; Spec 7.4 asks for a limit


def sessions() -> Any:
    """Session factory for the background build; tests override it."""
    return SessionFactory


class ExportIn(BaseModel):
    workspace_id: uuid.UUID
    format: Literal["json", "csv"] = "json"


@router.post("", status_code=202)
async def create_export(
    body: ExportIn,
    background: BackgroundTasks,
    request: Request,
    actor: CurrentActor,
    session: Session,
    factory: Annotated[Any, Depends(sessions)],
) -> dict[str, Any]:
    await require_member(session, body.workspace_id, actor.user_id)
    recent = await session.execute(
        text(
            "SELECT count(*) FROM exports WHERE requested_by = :u "
            "AND created_at > now() - interval '1 hour'"
        ),
        {"u": actor.user_id},
    )
    if recent.scalar_one() >= MAX_EXPORTS_PER_HOUR:
        raise DomainError(ErrorCode.RATE_LIMITED, "Too many exports. Try again in an hour.")
    eid = await service.request(session, body.workspace_id, actor.user_id, body.format)
    await session.commit()
    # Runs after the response is sent, so the request never waits for the build.
    background.add_task(
        service.build,
        factory,
        eid,
        timedelta(minutes=settings.export_link_ttl_minutes),
    )
    return envelope(request, {"id": str(eid), "status": "pending"})


@router.get("/{export_id}")
async def get_export(
    export_id: uuid.UUID, request: Request, actor: CurrentActor, session: Session
) -> dict[str, Any]:
    row = (
        (
            await session.execute(
                text(
                    """SELECT e.status, e.format, e.expires_at FROM exports e
                    JOIN workspace_members m ON m.workspace_id = e.workspace_id
                    WHERE e.id = :id AND m.user_id = :u"""
                ),
                {"id": export_id, "u": actor.user_id},
            )
        )
        .mappings()
        .one_or_none()
    )
    if row is None:
        raise NOT_FOUND
    out: dict[str, Any] = {"id": str(export_id), "status": row["status"], "format": row["format"]}
    expires_at = row["expires_at"]
    if row["status"] == "ready" and expires_at and expires_at > datetime.now(UTC):
        exp = int(expires_at.timestamp())
        token = service.sign(settings.auth_local_secret, export_id, exp)
        out["download_url"] = f"/exports/{export_id}/download?expires={exp}&token={token}"
        out["expires_at"] = expires_at.isoformat()
    elif row["status"] == "ready":
        out["status"] = "expired"
    return envelope(request, out)


@router.get("/{export_id}/download")
async def download_export(
    export_id: uuid.UUID,
    session: Session,
    expires: Annotated[int, Query()],
    token: Annotated[str, Query(max_length=128)],
) -> Response:
    """Authorized by the signed, expiring link, so a browser can open it directly."""
    now = datetime.now(UTC).timestamp()
    if not service.verify(settings.auth_local_secret, export_id, expires, token, now):
        raise DomainError(ErrorCode.UNAUTHENTICATED, "This download link is invalid or expired.")
    row = (
        (
            await session.execute(
                text("SELECT format, content FROM exports WHERE id = :id AND status = 'ready'"),
                {"id": export_id},
            )
        )
        .mappings()
        .one_or_none()
    )
    if row is None:
        raise NOT_FOUND
    is_json = row["format"] == "json"
    return Response(
        content=bytes(row["content"]),
        media_type="application/json" if is_json else "application/zip",
        headers={
            "Content-Disposition": (
                f'attachment; filename="omniassist-export.{"json" if is_json else "zip"}"'
            ),
            "Cache-Control": "no-store",
        },
    )
