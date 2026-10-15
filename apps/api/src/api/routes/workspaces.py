from typing import Any

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field

from src.api.responses import envelope
from src.auth.dependencies import CurrentActor, Session
from src.domain.workspaces import repository

router = APIRouter(prefix="/workspaces", tags=["workspaces"])


class WorkspaceCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)


@router.get("")
async def list_workspaces(
    request: Request, actor: CurrentActor, session: Session
) -> dict[str, Any]:
    return envelope(request, await repository.list_for_user(session, actor.user_id))


@router.post("", status_code=201)
async def create_workspace(
    body: WorkspaceCreate, request: Request, actor: CurrentActor, session: Session
) -> dict[str, Any]:
    return envelope(request, await repository.create(session, actor.user_id, body.name))
