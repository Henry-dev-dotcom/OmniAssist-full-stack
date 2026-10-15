import uuid
from datetime import datetime
from typing import Annotated, Any

from fastapi import APIRouter, Query, Request

from src.api.responses import envelope
from src.auth.dependencies import CurrentActor, Session
from src.domain.common.errors import DomainError, ErrorCode
from src.domain.time_blocks import repository
from src.domain.time_blocks.schemas import TimeBlockCreate, TimeBlockOut, TimeBlockUpdate
from src.domain.workspaces.service import require_member

router = APIRouter(prefix="/time-blocks", tags=["time-blocks"])

NOT_FOUND = DomainError(ErrorCode.NOT_FOUND, "Time block not found.")


def _out(row: dict[str, Any]) -> dict[str, Any]:
    return TimeBlockOut.model_validate(row).model_dump(mode="json")


def _warnings(ids: list[uuid.UUID]) -> list[dict[str, Any]]:
    return [{"code": "TIME_BLOCK_OVERLAP", "block_ids": [str(i) for i in ids]}] if ids else []


@router.get("")
async def list_blocks(
    request: Request,
    actor: CurrentActor,
    session: Session,
    workspace_id: Annotated[uuid.UUID, Query()],
    start: Annotated[datetime | None, Query()] = None,
    end: Annotated[datetime | None, Query()] = None,
) -> dict[str, Any]:
    await require_member(session, workspace_id, actor.user_id)
    rows = await repository.list_blocks(session, workspace_id, start, end)
    return envelope(request, [_out(r) for r in rows])


@router.post("", status_code=201)
async def create_block(
    body: TimeBlockCreate, request: Request, actor: CurrentActor, session: Session
) -> dict[str, Any]:
    await require_member(session, body.workspace_id, actor.user_id)
    created = await repository.create(session, body.values())
    clashes = await repository.overlapping_ids(
        session, created["workspace_id"], created["starts_at"], created["ends_at"], created["id"]
    )
    await session.commit()
    return envelope(request, _out(created), warnings=_warnings(clashes))


@router.patch("/{block_id}")
async def update_block(
    block_id: uuid.UUID,
    body: TimeBlockUpdate,
    request: Request,
    actor: CurrentActor,
    session: Session,
) -> dict[str, Any]:
    current = await repository.get_for_user(session, block_id, actor.user_id)
    if current is None:
        raise NOT_FOUND
    updated = await repository.update(session, block_id, current["workspace_id"], body.changes())
    clashes = await repository.overlapping_ids(
        session, updated["workspace_id"], updated["starts_at"], updated["ends_at"], block_id
    )
    await session.commit()
    return envelope(request, _out(updated), warnings=_warnings(clashes))


@router.delete("/{block_id}")
async def delete_block(
    block_id: uuid.UUID, request: Request, actor: CurrentActor, session: Session
) -> dict[str, Any]:
    if await repository.get_for_user(session, block_id, actor.user_id) is None:
        raise NOT_FOUND
    await repository.tombstone(session, block_id)
    await session.commit()
    return envelope(request, {"id": str(block_id), "deleted": True})
