import uuid
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.common.errors import DomainError, ErrorCode
from src.domain.common.ids import new_uuid7
from src.domain.common.records import RecordRepo, require_in_workspace
from src.domain.reviews.schemas import DEFAULT_STAGES, ReviewItemOut, ReviewOut


def _rule(message: str) -> DomainError:
    return DomainError(ErrorCode.DOMAIN_RULE_VIOLATION, message)


class ReviewRepo(RecordRepo):
    async def check(
        self,
        s: AsyncSession,
        workspace_id: uuid.UUID,
        entity_id: uuid.UUID,
        values: dict[str, Any],
        current: dict[str, Any] | None,
    ) -> dict[str, Any]:
        if current is None:
            await require_in_workspace(s, "projects", values["project_id"], workspace_id, "Project")
            if values.get("stages") is None:
                values = {
                    **values,
                    "stages": [{"id": new_uuid7(), "name": n, "archived": False}
                               for n in DEFAULT_STAGES],
                }  # fmt: skip
        stages = values.get("stages")
        if stages is None:
            return values
        names = [st["name"].strip().casefold() for st in stages]
        if len(set(names)) != len(names):
            raise _rule("Stage names must be unique within a review.")
        if not any(not st["archived"] for st in stages):
            raise _rule("A review needs at least one active stage.")
        given = {st["id"] for st in stages}
        rows = await s.execute(
            text("SELECT id, review_id FROM review_stages WHERE id = ANY(:ids) OR review_id = :r"),
            {"ids": list(given), "r": entity_id},
        )
        owned: set[uuid.UUID] = set()
        for sid, rid in rows:
            if rid != entity_id:
                raise _rule("A stage belongs to another review.")
            owned.add(sid)
        if owned - given:
            raise _rule("Archive a stage instead of removing it.")
        archived = [st["id"] for st in stages if st["archived"]]
        if archived:
            busy = await s.execute(
                text(
                    "SELECT 1 FROM review_items WHERE stage_id = ANY(:ids) "
                    "AND deleted_at IS NULL LIMIT 1"
                ),
                {"ids": archived},
            )
            if busy.first() is not None:
                raise _rule("Move the items out of a stage before archiving it.")
        return values

    async def after_write(
        self,
        s: AsyncSession,
        row: dict[str, Any],
        values: dict[str, Any],
        before: dict[str, Any] | None,
        actor_id: uuid.UUID | None,
    ) -> None:
        stages = values.get("stages")
        if stages is None:
            return
        for position, st in enumerate(stages):
            await s.execute(
                text(
                    """INSERT INTO review_stages (id, review_id, name, position, archived_at)
                    VALUES (:id, :r, :name, :pos, CASE WHEN :arch THEN now() END)
                    ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name,
                      position = EXCLUDED.position,
                      archived_at = CASE WHEN :arch
                        THEN COALESCE(review_stages.archived_at, now()) END"""
                ),
                {"id": st["id"], "r": row["id"], "name": st["name"].strip(), "pos": position,
                 "arch": st["archived"]},
            )  # fmt: skip


reviews = ReviewRepo(
    table="reviews",
    entity_type="review",
    columns=("project_id", "name", "description"),
    updatable=("name", "description"),
    out=ReviewOut,
    extra_select=(
        ", COALESCE((SELECT json_agg(json_build_object('id', st.id, 'name', st.name, "
        "'archived', st.archived_at IS NOT NULL) ORDER BY st.position) "
        "FROM review_stages st WHERE st.review_id = r.id), '[]'::json) AS stages"
    ),
    label="Review",
)


class ReviewItemRepo(RecordRepo):
    async def check(
        self,
        s: AsyncSession,
        workspace_id: uuid.UUID,
        entity_id: uuid.UUID,
        values: dict[str, Any],
        current: dict[str, Any] | None,
    ) -> dict[str, Any]:
        review_id = values["review_id"] if current is None else current["review_id"]
        if current is None:
            await require_in_workspace(s, "reviews", review_id, workspace_id, "Review")
        if current is None or values.get("stage_id") is not None:
            row = await s.execute(
                text(
                    """SELECT id FROM review_stages WHERE review_id = :r
                    AND archived_at IS NULL AND (CAST(:st AS uuid) IS NULL OR id = :st)
                    ORDER BY position LIMIT 1"""
                ),
                {"r": review_id, "st": values.get("stage_id")},
            )
            stage = row.scalar_one_or_none()
            if stage is None:
                raise DomainError(ErrorCode.NOT_FOUND, "Stage not found in this review.")
            values = {**values, "stage_id": stage}
        elif "stage_id" in values:
            raise DomainError(ErrorCode.VALIDATION_ERROR, "An item must stay in a stage.")
        return values

    async def after_write(
        self,
        s: AsyncSession,
        row: dict[str, Any],
        values: dict[str, Any],
        before: dict[str, Any] | None,
        actor_id: uuid.UUID | None,
    ) -> None:
        moved = before is None or row["stage_id"] != before["stage_id"]
        if not moved or actor_id is None:
            return
        # Stage history is append-only (Spec 4.8); the decision at move time is kept with it.
        await s.execute(
            text(
                """INSERT INTO review_item_events
                (id, review_item_id, from_stage_id, to_stage_id, decision, actor_id)
                VALUES (:id, :item, :from_st, :to_st, :decision, :actor)"""
            ),
            {"id": new_uuid7(), "item": row["id"],
             "from_st": None if before is None else before["stage_id"],
             "to_st": row["stage_id"], "decision": row["decision"], "actor": actor_id},
        )  # fmt: skip


items = ReviewItemRepo(
    table="review_items",
    entity_type="review_item",
    columns=(
        "review_id",
        "stage_id",
        "title",
        "source_identifier",
        "decision",
        "reviewer",
        "tags",
        "notes",
        "external_url",
    ),
    updatable=(
        "stage_id",
        "title",
        "source_identifier",
        "decision",
        "reviewer",
        "tags",
        "notes",
        "external_url",
    ),
    out=ReviewItemOut,
    casts={"tags": "jsonb"},
    label="Review item",
)


async def stage_history(s: AsyncSession, item_id: uuid.UUID) -> list[dict[str, Any]]:
    rows = await s.execute(
        text(
            """SELECT from_stage_id, to_stage_id, decision, actor_id, created_at
            FROM review_item_events WHERE review_item_id = :i ORDER BY created_at, id"""
        ),
        {"i": item_id},
    )
    return [dict(r) for r in rows.mappings()]
