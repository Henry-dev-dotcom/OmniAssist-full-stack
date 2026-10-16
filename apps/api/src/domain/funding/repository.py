import uuid
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.common.records import RecordRepo, require_in_workspace
from src.domain.funding.schemas import FundingOut


class FundingRepo(RecordRepo):
    async def check(
        self,
        s: AsyncSession,
        workspace_id: uuid.UUID,
        entity_id: uuid.UUID,
        values: dict[str, Any],
        current: dict[str, Any] | None,
    ) -> dict[str, Any]:
        if current is None or "project_id" in values:
            project_id = values.get("project_id") if current is None else values["project_id"]
            await require_in_workspace(s, "projects", project_id, workspace_id, "Project")
        return values


repo = FundingRepo(
    table="funding_opportunities",
    entity_type="funding_opportunity",
    columns=(
        "project_id",
        "category",
        "title",
        "organisation",
        "amount",
        "opens_label",
        "deadline_at",
        "deadline_type",
        "eligibility_notes",
        "priority",
        "status",
        "date_applied",
        "next_action",
        "official_link",
        "other_source",
    ),
    updatable=(
        "project_id",
        "category",
        "title",
        "organisation",
        "amount",
        "opens_label",
        "deadline_at",
        "deadline_type",
        "eligibility_notes",
        "priority",
        "status",
        "date_applied",
        "next_action",
        "official_link",
        "other_source",
    ),
    out=FundingOut,
    label="Funding opportunity",
)
