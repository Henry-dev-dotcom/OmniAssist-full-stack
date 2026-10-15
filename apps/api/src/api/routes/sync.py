from typing import Annotated, Any

from fastapi import APIRouter, Query, Request

from src.api.responses import envelope
from src.auth.dependencies import CurrentActor, Session
from src.domain.sync import repository, service

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
