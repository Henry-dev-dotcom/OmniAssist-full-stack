import uuid
from typing import Annotated, Any

from fastapi import APIRouter, Query, Request

from src.api.responses import envelope
from src.auth.dependencies import CurrentActor, Session
from src.domain.funding.repository import repo
from src.domain.funding.schemas import FundingOut
from src.domain.workspaces.service import require_member

router = APIRouter(prefix="/funding-opportunities", tags=["funding"])


@router.get("")
async def list_funding_opportunities(
    request: Request,
    actor: CurrentActor,
    session: Session,
    workspace_id: Annotated[uuid.UUID, Query()],
    limit: Annotated[int, Query(ge=1, le=100)] = 100,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> dict[str, Any]:
    await require_member(session, workspace_id, actor.user_id)
    rows = await repo.list_rows(
        session, workspace_id, order="deadline_at ASC NULLS LAST, r.updated_at DESC"
    )
    page = rows[offset : offset + limit]
    return envelope(
        request,
        [FundingOut.model_validate(row).model_dump(mode="json") for row in page],
        limit=limit,
        offset=offset,
        has_more=len(rows) > offset + limit,
    )
