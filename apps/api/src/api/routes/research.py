"""Online read endpoints for research entities. Writes go through /sync/push (Spec 7.1)."""

import uuid
from typing import Annotated, Any

from fastapi import APIRouter, Query, Request

from src.api.responses import envelope
from src.auth.dependencies import CurrentActor, Session
from src.domain.activity import repository as activity
from src.domain.analyses import repository as analyses
from src.domain.analyses.schemas import AnalysisStatus
from src.domain.common.records import RecordRepo
from src.domain.experiments import repository as experiments
from src.domain.milestones import repository as milestones
from src.domain.reviews import repository as reviews
from src.domain.workspaces.service import require_member

router = APIRouter(tags=["research"])

WorkspaceId = Annotated[uuid.UUID, Query()]
ProjectId = Annotated[uuid.UUID | None, Query()]


async def _list(
    request: Request,
    actor: Any,
    session: Any,
    repo: RecordRepo,
    workspace_id: uuid.UUID,
    **filters: Any,
) -> dict[str, Any]:
    await require_member(session, workspace_id, actor.user_id)
    rows = await repo.list_rows(session, workspace_id, filters)
    return envelope(request, [repo.payload(r) for r in rows])


@router.get("/milestones")
async def list_milestones(
    request: Request,
    actor: CurrentActor,
    session: Session,
    workspace_id: WorkspaceId,
    project_id: ProjectId = None,
) -> dict[str, Any]:
    return await _list(
        request, actor, session, milestones.repo, workspace_id, project_id=project_id
    )


@router.get("/reviews")
async def list_reviews(
    request: Request,
    actor: CurrentActor,
    session: Session,
    workspace_id: WorkspaceId,
    project_id: ProjectId = None,
) -> dict[str, Any]:
    return await _list(
        request, actor, session, reviews.reviews, workspace_id, project_id=project_id
    )


@router.get("/reviews/{review_id}/items")
async def list_review_items(
    review_id: uuid.UUID, request: Request, actor: CurrentActor, session: Session
) -> dict[str, Any]:
    review = await reviews.reviews.get_for_user(session, review_id, actor.user_id)
    if review is None:
        raise reviews.reviews.not_found
    return await _list(
        request, actor, session, reviews.items, review["workspace_id"], review_id=review_id
    )


@router.get("/review-items/{item_id}/history")
async def review_item_history(
    item_id: uuid.UUID, request: Request, actor: CurrentActor, session: Session
) -> dict[str, Any]:
    if await reviews.items.get_for_user(session, item_id, actor.user_id) is None:
        raise reviews.items.not_found
    rows = await reviews.stage_history(session, item_id)
    return envelope(request, [{k: str(v) if v is not None else None for k, v in r.items()}
                              for r in rows])  # fmt: skip


@router.get("/analysis-records")
async def list_analyses(
    request: Request,
    actor: CurrentActor,
    session: Session,
    workspace_id: WorkspaceId,
    project_id: ProjectId = None,
    status: Annotated[AnalysisStatus | None, Query()] = None,
) -> dict[str, Any]:
    return await _list(
        request, actor, session, analyses.repo, workspace_id,
        project_id=project_id, status=status.value if status else None,
    )  # fmt: skip


@router.get("/experiment-entries")
async def list_experiments(
    request: Request,
    actor: CurrentActor,
    session: Session,
    workspace_id: WorkspaceId,
    project_id: ProjectId = None,
) -> dict[str, Any]:
    return await _list(
        request, actor, session, experiments.repo, workspace_id, project_id=project_id
    )


@router.get("/experiment-entries/{entry_id}/revisions")
async def experiment_revisions(
    entry_id: uuid.UUID, request: Request, actor: CurrentActor, session: Session
) -> dict[str, Any]:
    if await experiments.repo.get_for_user(session, entry_id, actor.user_id) is None:
        raise experiments.repo.not_found
    rows = await experiments.revisions(session, entry_id)
    return envelope(
        request,
        [{**r, "id": str(r["id"]), "actor_id": str(r["actor_id"]),
          "created_at": r["created_at"].isoformat()} for r in rows],
    )  # fmt: skip


@router.get("/activity")
async def list_activity(
    request: Request,
    actor: CurrentActor,
    session: Session,
    workspace_id: WorkspaceId,
    entity_id: Annotated[uuid.UUID | None, Query()] = None,
) -> dict[str, Any]:
    await require_member(session, workspace_id, actor.user_id)
    rows = await activity.for_entity(session, workspace_id, entity_id)
    return envelope(
        request,
        [{**r, "id": str(r["id"]), "entity_id": str(r["entity_id"]),
          "actor_id": str(r["actor_id"]), "created_at": r["created_at"].isoformat()}
         for r in rows],
    )  # fmt: skip
