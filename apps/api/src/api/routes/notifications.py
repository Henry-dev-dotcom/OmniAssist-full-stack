import uuid
from datetime import UTC, datetime
from typing import Annotated, Any

from fastapi import APIRouter, Query, Request

from src.api.responses import envelope
from src.auth.dependencies import CurrentActor, Session
from src.domain.common.errors import DomainError, ErrorCode
from src.domain.notifications import repository
from src.domain.notifications.models import NotificationOut, ReminderSet, Snooze
from src.domain.tasks import repository as tasks
from src.domain.workspaces.service import require_member

router = APIRouter(tags=["notifications"])

NOT_FOUND = DomainError(ErrorCode.NOT_FOUND, "Notification not found.")


def _out(row: dict[str, Any]) -> dict[str, Any]:
    return NotificationOut.model_validate(row).dump()


@router.get("/notifications")
async def list_notifications(
    request: Request,
    actor: CurrentActor,
    session: Session,
    workspace_id: Annotated[uuid.UUID, Query()],
    status: Annotated[str | None, Query()] = None,
    unread: Annotated[bool, Query()] = False,
) -> dict[str, Any]:
    await require_member(session, workspace_id, actor.user_id)
    rows = await repository.list_for_workspace(session, workspace_id, status, unread)
    return envelope(request, [_out(r) for r in rows])


async def _act(
    request: Request, actor: CurrentActor, session: Session, nid: uuid.UUID, action: str,
    minutes: int = 10,
) -> dict[str, Any]:  # fmt: skip
    row = await repository.get_for_user(session, nid, actor.user_id)
    if row is None:
        raise NOT_FOUND
    updated = await repository.apply_action(session, row, action, datetime.now(UTC), minutes)
    await session.commit()
    return envelope(request, _out(updated))


@router.post("/notifications/{nid}/read")
async def read(nid: uuid.UUID, request: Request, actor: CurrentActor, session: Session):  # type: ignore[no-untyped-def]
    return await _act(request, actor, session, nid, "read")


@router.post("/notifications/{nid}/dismiss")
async def dismiss(nid: uuid.UUID, request: Request, actor: CurrentActor, session: Session):  # type: ignore[no-untyped-def]
    return await _act(request, actor, session, nid, "dismiss")


@router.post("/notifications/{nid}/ack")
async def ack(nid: uuid.UUID, request: Request, actor: CurrentActor, session: Session):  # type: ignore[no-untyped-def]
    return await _act(request, actor, session, nid, "ack")


@router.post("/notifications/{nid}/snooze")
async def snooze(  # type: ignore[no-untyped-def]
    nid: uuid.UUID, body: Snooze, request: Request, actor: CurrentActor, session: Session
):
    return await _act(request, actor, session, nid, "snooze", body.minutes)


@router.get("/tasks/{task_id}/reminders")
async def task_reminders(
    task_id: uuid.UUID, request: Request, actor: CurrentActor, session: Session
) -> dict[str, Any]:
    if await tasks.get_for_user(session, task_id, actor.user_id) is None:
        raise DomainError(ErrorCode.NOT_FOUND, "Task not found.")
    rows = await repository.list_for_entity(session, "task", task_id)
    return envelope(request, [_out(r) for r in rows])


@router.put("/tasks/{task_id}/reminders")
async def set_task_reminders(
    task_id: uuid.UUID, body: ReminderSet, request: Request, actor: CurrentActor, session: Session
) -> dict[str, Any]:
    task = await tasks.get_for_user(session, task_id, actor.user_id)
    if task is None:
        raise DomainError(ErrorCode.NOT_FOUND, "Task not found.")
    now = datetime.now(UTC)
    rows = await repository.set_task_reminders(
        session, task, body.offsets, body.urgency, body.channel, now
    )
    await session.commit()
    skipped = len(body.offsets) - len(rows)
    warnings = [{"code": "REMINDER_IN_PAST", "count": skipped}] if skipped else []
    return envelope(request, [_out(r) for r in rows], warnings=warnings)
