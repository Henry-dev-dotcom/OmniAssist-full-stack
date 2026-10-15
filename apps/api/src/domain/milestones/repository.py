import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.common.errors import DomainError, ErrorCode
from src.domain.common.records import RecordRepo, require_in_workspace
from src.domain.milestones.schemas import MilestoneOut

CYCLE = DomainError(
    ErrorCode.DOMAIN_RULE_VIOLATION, "That link would make a milestone depend on itself."
)


async def _reaches(s: AsyncSession, sql: str, start: list[uuid.UUID], target: uuid.UUID) -> bool:
    """Walks `sql` (maps :ids to next ids) from `start`; true if `target` is reachable."""
    seen: set[uuid.UUID] = set()
    frontier = [i for i in start if i is not None]
    while frontier:
        if target in frontier:
            return True
        seen.update(frontier)
        rows = await s.execute(text(sql), {"ids": frontier})
        frontier = [r for (r,) in rows if r is not None and r not in seen]
    return False


class MilestoneRepo(RecordRepo):
    async def check(
        self,
        s: AsyncSession,
        workspace_id: uuid.UUID,
        entity_id: uuid.UUID,
        values: dict[str, Any],
        current: dict[str, Any] | None,
    ) -> dict[str, Any]:
        project_id = values["project_id"] if current is None else current["project_id"]
        if current is None:
            await require_in_workspace(s, "projects", project_id, workspace_id, "Project")
        parent = values.get("parent_id")
        if parent is not None:
            await require_in_workspace(s, "milestones", parent, workspace_id, "Parent milestone")
            if await _reaches(
                s, "SELECT parent_id FROM milestones WHERE id = ANY(:ids)", [parent], entity_id
            ):
                raise CYCLE
        deps = values.get("depends_on")
        if deps:
            for d in deps:
                await require_in_workspace(s, "milestones", d, workspace_id, "Milestone")
            if await _reaches(
                s,
                "SELECT depends_on_id FROM milestone_dependencies WHERE milestone_id = ANY(:ids)",
                list(deps),
                entity_id,
            ):
                raise CYCLE
        if "status" in values:
            # Completing records a time; leaving "complete" clears it (Spec 4.7).
            was = current["completed_at"] if current else None
            done = values["status"] == "complete"
            values = {**values, "completed_at": (was or datetime.now(UTC)) if done else None}
        return values

    async def after_write(
        self,
        s: AsyncSession,
        row: dict[str, Any],
        values: dict[str, Any],
        before: dict[str, Any] | None,
        actor_id: uuid.UUID | None,
    ) -> None:
        if values.get("depends_on") is None:
            return
        await s.execute(
            text("DELETE FROM milestone_dependencies WHERE milestone_id = :m"), {"m": row["id"]}
        )
        for d in dict.fromkeys(values["depends_on"]):  # de-duplicate, keep order
            await s.execute(
                text(
                    "INSERT INTO milestone_dependencies (milestone_id, depends_on_id) "
                    "VALUES (:m, :d)"
                ),
                {"m": row["id"], "d": d},
            )


repo = MilestoneRepo(
    table="milestones",
    entity_type="milestone",
    columns=(
        "project_id",
        "parent_id",
        "title",
        "description",
        "status",
        "due_at",
        "progress_value",
        "weight",
        "progress_mode",
        "completed_at",
    ),
    updatable=(
        "parent_id",
        "title",
        "description",
        "status",
        "due_at",
        "progress_value",
        "weight",
        "progress_mode",
        "completed_at",
    ),
    out=MilestoneOut,
    casts={"status": "milestone_status"},
    extra_select=(
        ", ARRAY(SELECT d.depends_on_id FROM milestone_dependencies d "
        "WHERE d.milestone_id = r.id ORDER BY d.depends_on_id) AS depends_on"
    ),
    label="Milestone",
)
