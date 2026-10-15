import uuid
from typing import Annotated, Any, Literal

from fastapi import APIRouter, Query, Request

from src.api.responses import envelope
from src.auth.dependencies import CurrentActor, Session
from src.domain.common.errors import DomainError, ErrorCode
from src.domain.projects import repository
from src.domain.projects.schemas import ProjectCreate, ProjectOut, ProjectUpdate
from src.domain.workspaces.service import require_member

router = APIRouter(prefix="/projects", tags=["projects"])

NOT_FOUND = DomainError(ErrorCode.NOT_FOUND, "Project not found.")


def _out(row: dict[str, Any]) -> dict[str, Any]:
    return ProjectOut.model_validate(row).model_dump(mode="json")


@router.get("")
async def list_projects(
    request: Request,
    actor: CurrentActor,
    session: Session,
    workspace_id: Annotated[uuid.UUID, Query()],
    view: Annotated[Literal["active", "archived", "all"], Query()] = "active",
) -> dict[str, Any]:
    await require_member(session, workspace_id, actor.user_id)
    rows = await repository.list_projects(session, workspace_id, view)
    return envelope(request, [_out(r) for r in rows])


@router.post("", status_code=201)
async def create_project(
    body: ProjectCreate, request: Request, actor: CurrentActor, session: Session
) -> dict[str, Any]:
    await require_member(session, body.workspace_id, actor.user_id)
    created = await repository.create(session, body.values())
    await session.commit()
    return envelope(request, _out(created))


@router.patch("/{project_id}")
async def update_project(
    project_id: uuid.UUID,
    body: ProjectUpdate,
    request: Request,
    actor: CurrentActor,
    session: Session,
) -> dict[str, Any]:
    if await repository.get_for_user(session, project_id, actor.user_id) is None:
        raise NOT_FOUND  # same answer for "missing" and "someone else's"
    updated = await repository.update(session, project_id, body.changes())
    await session.commit()
    return envelope(request, _out(updated))


@router.delete("/{project_id}")
async def delete_project(
    project_id: uuid.UUID, request: Request, actor: CurrentActor, session: Session
) -> dict[str, Any]:
    if await repository.get_for_user(session, project_id, actor.user_id) is None:
        raise NOT_FOUND
    await repository.tombstone(session, project_id)
    await session.commit()
    return envelope(request, {"id": str(project_id), "deleted": True})
