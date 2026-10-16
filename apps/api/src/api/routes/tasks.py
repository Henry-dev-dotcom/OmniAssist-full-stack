import uuid
from typing import Annotated, Any

from fastapi import APIRouter, Query, Request

from src.api.responses import envelope
from src.auth.dependencies import CurrentActor, Session
from src.domain.common.errors import DomainError, ErrorCode
from src.domain.tasks import repository
from src.domain.tasks.schemas import TaskCreate, TaskOut, TaskStatus, TaskUpdate
from src.domain.workspaces.service import require_member

router = APIRouter(prefix="/tasks", tags=["tasks"])

NOT_FOUND = DomainError(ErrorCode.NOT_FOUND, "Task not found.")


def _out(row: dict[str, Any]) -> dict[str, Any]:
    return TaskOut.model_validate(row).model_dump(mode="json")


@router.get("")
async def list_tasks(
    request: Request,
    actor: CurrentActor,
    session: Session,
    workspace_id: Annotated[uuid.UUID, Query()],
    status: Annotated[TaskStatus | None, Query()] = None,
    project_id: Annotated[uuid.UUID | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> dict[str, Any]:
    await require_member(session, workspace_id, actor.user_id)
    rows = await repository.list_tasks(
        session, workspace_id, status.value if status else None, project_id, limit, offset
    )
    return envelope(
        request, [_out(r) for r in rows], limit=limit, offset=offset, has_more=len(rows) == limit
    )


@router.post("", status_code=201)
async def create_task(
    body: TaskCreate, request: Request, actor: CurrentActor, session: Session
) -> dict[str, Any]:
    await require_member(session, body.workspace_id, actor.user_id)
    created = await repository.create(session, body.values())
    await session.commit()
    return envelope(request, _out(created))


@router.patch("/{task_id}")
async def update_task(
    task_id: uuid.UUID,
    body: TaskUpdate,
    request: Request,
    actor: CurrentActor,
    session: Session,
) -> dict[str, Any]:
    current = await repository.get_for_user(session, task_id, actor.user_id)
    if current is None:
        raise NOT_FOUND  # same answer for "missing" and "someone else's"
    updated = await repository.update(session, task_id, current["workspace_id"], body.changes())
    await session.commit()
    return envelope(request, _out(updated))


@router.delete("/{task_id}")
async def delete_task(
    task_id: uuid.UUID, request: Request, actor: CurrentActor, session: Session
) -> dict[str, Any]:
    if await repository.get_for_user(session, task_id, actor.user_id) is None:
        raise NOT_FOUND
    await repository.tombstone(session, task_id)
    await session.commit()
    return envelope(request, {"id": str(task_id), "deleted": True})
