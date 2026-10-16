"""Applies client mutations. Idempotent by mutation_id; one bad mutation never blocks the rest."""

import hashlib
import json
import uuid
from dataclasses import dataclass
from typing import Any, Literal

from pydantic import BaseModel, Field, ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.activity import repository as activity
from src.domain.analyses import repository as analyses
from src.domain.analyses.schemas import AnalysisCreate, AnalysisOut, AnalysisUpdate
from src.domain.common.errors import DomainError, ErrorCode
from src.domain.common.records import RecordRepo
from src.domain.experiments import repository as experiments
from src.domain.experiments.schemas import ExperimentCreate, ExperimentOut, ExperimentUpdate
from src.domain.milestones import repository as milestones
from src.domain.milestones.schemas import MilestoneCreate, MilestoneOut, MilestoneUpdate
from src.domain.projects import repository as projects
from src.domain.projects.schemas import ProjectCreate, ProjectOut, ProjectUpdate
from src.domain.reviews import repository as reviews
from src.domain.reviews.schemas import (
    ReviewCreate,
    ReviewItemCreate,
    ReviewItemOut,
    ReviewItemUpdate,
    ReviewOut,
    ReviewUpdate,
)
from src.domain.sync import repository as sync
from src.domain.tasks import repository as tasks
from src.domain.tasks.schemas import TaskCreate, TaskOut, TaskUpdate
from src.domain.time_blocks import repository as time_blocks
from src.domain.time_blocks.schemas import TimeBlockCreate, TimeBlockOut, TimeBlockUpdate
from src.domain.workspaces import repository as workspaces


class MutationIn(BaseModel):
    mutation_id: uuid.UUID
    workspace_id: uuid.UUID
    entity_type: str = Field(max_length=40)
    entity_id: uuid.UUID
    operation: Literal["create", "update", "delete"]
    base_version: int | None = None
    changes: dict[str, Any] = Field(default_factory=dict)


class PushIn(BaseModel):
    device_id: uuid.UUID
    protocol_version: Literal[1]
    cursor: int = 0
    mutations: list[MutationIn] = Field(max_length=100)


def _rejected(code: ErrorCode, message: str) -> dict[str, Any]:
    return {"status": "rejected", "error_code": code.value, "message": message}


def _hash(m: MutationIn) -> str:
    body = json.dumps(m.model_dump(mode="json"), sort_keys=True)
    return hashlib.sha256(body.encode()).hexdigest()


@dataclass(frozen=True)
class Entity:
    repo: Any  # module with get_in_workspace / create / update / tombstone
    create_schema: type[BaseModel]
    update_schema: type[BaseModel]
    out_schema: type[BaseModel]


ENTITIES = {
    "project": Entity(projects, ProjectCreate, ProjectUpdate, ProjectOut),
    "task": Entity(tasks, TaskCreate, TaskUpdate, TaskOut),
    "time_block": Entity(time_blocks, TimeBlockCreate, TimeBlockUpdate, TimeBlockOut),
    "milestone": Entity(milestones.repo, MilestoneCreate, MilestoneUpdate, MilestoneOut),
    "review": Entity(reviews.reviews, ReviewCreate, ReviewUpdate, ReviewOut),
    "review_item": Entity(reviews.items, ReviewItemCreate, ReviewItemUpdate, ReviewItemOut),
    "analysis_record": Entity(analyses.repo, AnalysisCreate, AnalysisUpdate, AnalysisOut),
    "experiment_entry": Entity(experiments.repo, ExperimentCreate, ExperimentUpdate, ExperimentOut),
}


async def _apply(s: AsyncSession, e: Entity, m: MutationIn, actor_id: uuid.UUID) -> dict[str, Any]:
    current = await e.repo.get_in_workspace(s, m.entity_id, m.workspace_id)
    generic = isinstance(e.repo, RecordRepo)
    extra = {"actor_id": actor_id} if generic else {}
    if m.operation == "create":
        if current is not None:
            return _rejected(ErrorCode.VERSION_CONFLICT, "Record already exists.")
        data = e.create_schema.model_validate(
            {**m.changes, "id": m.entity_id, "workspace_id": m.workspace_id}
        )
        row = await e.repo.create(s, data.values(), **extra)  # type: ignore[attr-defined]
        await _log(s, m, actor_id, {}, None)
        return {"status": "accepted", "entity_version": row["version"]}
    if current is None:
        return _rejected(ErrorCode.NOT_FOUND, "Record not found.")
    if m.operation == "delete":
        await e.repo.tombstone(s, m.entity_id)
        await _log(s, m, actor_id, {}, current)
        return {"status": "accepted", "entity_version": current["version"] + 1}
    if m.base_version is None:
        return _rejected(ErrorCode.VALIDATION_ERROR, "base_version is required for update.")
    changes = e.update_schema.model_validate(m.changes).changes()  # type: ignore[attr-defined]
    if m.base_version != current["version"]:
        # Edits to different fields merge; the same field changed on both sides is a conflict.
        overlap = changes.keys() & await sync.keys_changed_since(s, m.entity_id, m.base_version)
        if overlap:
            server = e.out_schema.model_validate(current).model_dump(mode="json")
            cid = await sync.save_conflict(
                s, m.workspace_id, m.entity_type, m.entity_id, m.base_version, m.changes, server
            )
            return {"status": "conflict", "conflict_id": str(cid), "server": server}
    if e.repo is projects:
        row = await projects.update(s, m.entity_id, changes)
    else:
        row = await e.repo.update(s, m.entity_id, m.workspace_id, changes, **extra)
    await _log(s, m, actor_id, changes, current)
    return {"status": "accepted", "entity_version": row["version"]}


async def _log(
    s: AsyncSession,
    m: MutationIn,
    actor_id: uuid.UUID,
    changes: dict[str, Any],
    before: dict[str, Any] | None,
) -> None:
    action, meta = activity.describe(m.operation, changes, before)
    await activity.record(s, m.workspace_id, actor_id, m.entity_type, m.entity_id, action, meta)


class _LostRace(Exception):
    """Another request stored this mutation_id first."""


def _out(m: MutationIn, result: dict[str, Any]) -> dict[str, Any]:
    return {"mutation_id": str(m.mutation_id), **result}


def _replay(m: MutationIn, digest: str, seen: dict[str, Any]) -> dict[str, Any]:
    if seen["request_hash"] != digest:
        return _out(m, _rejected(ErrorCode.IDEMPOTENCY_KEY_REUSED, "Mutation ID reused."))
    return _out(m, seen["result"])


async def apply_mutation(s: AsyncSession, actor_id: uuid.UUID, m: MutationIn) -> dict[str, Any]:
    digest = _hash(m)
    seen = await sync.find_mutation(s, m.mutation_id)
    if seen is not None:
        return _replay(m, digest, seen)
    if not await workspaces.is_member(s, m.workspace_id, actor_id):
        return _out(m, _rejected(ErrorCode.FORBIDDEN, "You do not have access to this workspace."))
    entity = ENTITIES.get(m.entity_type)
    if entity is None:
        return _out(
            m, _rejected(ErrorCode.VALIDATION_ERROR, f"Unsupported entity_type: {m.entity_type}.")
        )
    try:
        # The change and its idempotency record commit together, or not at all.
        async with s.begin_nested():
            try:
                async with s.begin_nested():  # a failed mutation rolls back alone
                    result = await _apply(s, entity, m, actor_id)
            except ValidationError:
                result = _rejected(ErrorCode.VALIDATION_ERROR, "Mutation values are invalid.")
            except DomainError as e:
                result = _rejected(e.code, e.message)
            if not await sync.save_mutation(s, actor_id, m, digest, result):
                raise _LostRace
    except _LostRace:
        # A concurrent push with the same mutation_id won; its effects stand alone.
        won = await sync.find_mutation(s, m.mutation_id)
        assert won is not None
        return _replay(m, digest, won)
    return _out(m, result)
