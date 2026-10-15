import uuid
from typing import Annotated, Any, Literal

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel

from src.api.responses import envelope
from src.auth.dependencies import CurrentActor, Session
from src.domain.activity import repository as activity
from src.domain.common.errors import DomainError, ErrorCode
from src.domain.sync import repository, service
from src.domain.workspaces.service import require_member

router = APIRouter(prefix="/sync", tags=["sync"])


@router.post("/push")
async def push(
    body: service.PushIn, request: Request, actor: CurrentActor, session: Session
) -> dict[str, Any]:
    results = [await service.apply_mutation(session, actor.user_id, m) for m in body.mutations]
    await session.commit()
    return envelope(request, {"results": results})


@router.get("/pull")
async def pull(
    request: Request,
    actor: CurrentActor,
    session: Session,
    cursor: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=500)] = 200,
) -> dict[str, Any]:
    items, has_more = await repository.pull(session, actor.user_id, cursor, limit)
    changes = [
        {
            "sequence": i["sequence"],
            "workspace_id": str(i["workspace_id"]),
            "entity_type": i["entity_type"],
            "entity_id": str(i["entity_id"]),
            "operation": i["operation"],
            "entity_version": i["entity_version"],
            "payload": i["payload"],
        }
        for i in items
    ]
    next_cursor = changes[-1]["sequence"] if changes else cursor
    return envelope(
        request,
        {"changes": changes, "next_cursor": next_cursor, "has_more": has_more, "conflicts": []},
    )


@router.get("/conflicts")
async def list_conflicts(
    request: Request,
    actor: CurrentActor,
    session: Session,
    workspace_id: Annotated[uuid.UUID, Query()],
) -> dict[str, Any]:
    await require_member(session, workspace_id, actor.user_id)
    rows = await repository.open_conflicts(session, workspace_id)
    return envelope(
        request,
        [{**r, "id": str(r["id"]), "entity_id": str(r["entity_id"]),
          "created_at": r["created_at"].isoformat()} for r in rows],
    )  # fmt: skip


class ResolveIn(BaseModel):
    # The chosen values reach the server as a normal mutation; this closes the record.
    resolution: Literal["keep_local", "keep_server", "merge"]


@router.post("/conflicts/{conflict_id}/resolve")
async def resolve_conflict(
    conflict_id: uuid.UUID,
    body: ResolveIn,
    request: Request,
    actor: CurrentActor,
    session: Session,
) -> dict[str, Any]:
    closed = await repository.close_conflict(
        session, conflict_id, actor.user_id, f"resolved_{body.resolution}"
    )
    if closed is None:
        raise DomainError(ErrorCode.NOT_FOUND, "Conflict not found or already resolved.")
    await activity.record(
        session, closed["workspace_id"], actor.user_id, closed["entity_type"],
        closed["entity_id"], "conflict_resolved", {"resolution": body.resolution},
    )  # fmt: skip
    await session.commit()
    return envelope(request, {"id": str(conflict_id), "resolution": body.resolution})
