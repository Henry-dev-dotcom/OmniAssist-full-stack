import uuid
from typing import Annotated, Any

from fastapi import APIRouter, Query, Request

from src.api.responses import envelope
from src.auth.dependencies import CurrentActor, Session
from src.domain.common.records import RecordRepo
from src.domain.scholarships import repository as scholarships
from src.domain.workspaces.service import require_member

router = APIRouter(tags=["scholarships"])

WorkspaceId = Annotated[uuid.UUID, Query()]
Limit = Annotated[int, Query(ge=1, le=100)]
Offset = Annotated[int, Query(ge=0)]


async def _page(
    request: Request,
    actor: CurrentActor,
    session: Session,
    repo: RecordRepo,
    workspace_id: uuid.UUID,
    order: str,
    limit: int,
    offset: int,
) -> dict[str, Any]:
    await require_member(session, workspace_id, actor.user_id)
    rows = await repo.list_rows(session, workspace_id, order=order)
    return envelope(
        request,
        [repo.payload(row) for row in rows[offset : offset + limit]],
        limit=limit,
        offset=offset,
        has_more=len(rows) > offset + limit,
    )


@router.get("/scholarship-sections")
async def list_scholarship_sections(
    request: Request,
    actor: CurrentActor,
    session: Session,
    workspace_id: WorkspaceId,
    limit: Limit = 100,
    offset: Offset = 0,
) -> dict[str, Any]:
    return await _page(
        request, actor, session, scholarships.sections, workspace_id,
        "r.position ASC, r.created_at ASC, r.id ASC", limit, offset,
    )  # fmt: skip


@router.get("/scholarship-schemes")
async def list_scholarship_schemes(
    request: Request,
    actor: CurrentActor,
    session: Session,
    workspace_id: WorkspaceId,
    limit: Limit = 100,
    offset: Offset = 0,
) -> dict[str, Any]:
    return await _page(
        request, actor, session, scholarships.schemes, workspace_id,
        "r.position ASC, r.created_at ASC, r.id ASC", limit, offset,
    )  # fmt: skip


@router.get("/scholarship-applications")
async def list_scholarship_applications(
    request: Request,
    actor: CurrentActor,
    session: Session,
    workspace_id: WorkspaceId,
    limit: Limit = 100,
    offset: Offset = 0,
) -> dict[str, Any]:
    return await _page(
        request, actor, session, scholarships.repo, workspace_id,
        "r.deadline_at ASC NULLS LAST, r.updated_at DESC, r.id ASC", limit, offset,
    )  # fmt: skip
