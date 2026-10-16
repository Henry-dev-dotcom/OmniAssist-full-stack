import uuid
from typing import Any

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field

from src.api.responses import envelope
from src.auth.dependencies import CurrentActor, Session
from src.domain.common.errors import DomainError, ErrorCode
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


class WorkspaceUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    archived: bool | None = None


class WorkspaceDelete(BaseModel):
    confirm_name: str = Field(min_length=1, max_length=120)


NOT_FOUND = DomainError(ErrorCode.NOT_FOUND, "Workspace not found.")


@router.patch("/{workspace_id}")
async def update_workspace(
    workspace_id: uuid.UUID,
    body: WorkspaceUpdate,
    request: Request,
    actor: CurrentActor,
    session: Session,
) -> dict[str, Any]:
    if await repository.get_owned(session, workspace_id, actor.user_id) is None:
        raise NOT_FOUND  # same answer for missing and someone else's
    row = await repository.update(
        session, workspace_id, body.name.strip() if body.name else None, body.archived
    )
    return envelope(request, row)


@router.delete("/{workspace_id}")
async def delete_workspace(
    workspace_id: uuid.UUID,
    body: WorkspaceDelete,
    request: Request,
    actor: CurrentActor,
    session: Session,
) -> dict[str, Any]:
    """Permanent. The user types the workspace name, and the last workspace stays."""
    ws = await repository.get_owned(session, workspace_id, actor.user_id)
    if ws is None:
        raise NOT_FOUND
    if body.confirm_name.strip() != ws["name"]:
        raise DomainError(
            ErrorCode.VALIDATION_ERROR,
            "Type the workspace name exactly to delete it.",
            {"field": "confirm_name"},
        )
    if len(await repository.list_for_user(session, actor.user_id)) <= 1:
        raise DomainError(
            ErrorCode.DOMAIN_RULE_VIOLATION,
            "Create another workspace before deleting your last one.",
        )
    await repository.purge(session, [workspace_id])
    await session.commit()
    return envelope(request, {"id": str(workspace_id), "deleted": True})
