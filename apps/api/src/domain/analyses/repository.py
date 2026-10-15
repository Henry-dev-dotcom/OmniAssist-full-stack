import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.analyses.schemas import TRANSITIONS, AnalysisOut
from src.domain.common.errors import DomainError, ErrorCode
from src.domain.common.records import RecordRepo, require_in_workspace

RUN_STATES = {"running", "succeeded", "failed"}


class AnalysisRepo(RecordRepo):
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
        await require_in_workspace(
            s, "milestones", values.get("milestone_id"), workspace_id, "Milestone"
        )
        status = values.get("status")
        if status is not None and current is not None and status != current["status"]:
            if status not in TRANSITIONS[current["status"]]:
                raise DomainError(
                    ErrorCode.DOMAIN_RULE_VIOLATION,
                    f"An analysis cannot go from {current['status']} to {status}.",
                    {"field": "status"},
                )
        changed = current is None or status != current["status"]
        if status in RUN_STATES and changed and "last_run_at" not in values:
            values = {**values, "last_run_at": datetime.now(UTC)}
        return values


repo = AnalysisRepo(
    table="analysis_records",
    entity_type="analysis_record",
    columns=(
        "project_id",
        "milestone_id",
        "title",
        "purpose",
        "language",
        "repository_url",
        "branch_name",
        "commit_ref",
        "data_source_ref",
        "environment",
        "status",
        "last_run_at",
        "result_summary",
        "error_details",
        "next_action",
    ),
    updatable=(
        "milestone_id",
        "title",
        "purpose",
        "language",
        "repository_url",
        "branch_name",
        "commit_ref",
        "data_source_ref",
        "environment",
        "status",
        "last_run_at",
        "result_summary",
        "error_details",
        "next_action",
    ),
    out=AnalysisOut,
    label="Analysis record",
)
