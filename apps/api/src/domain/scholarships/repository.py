import uuid
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.common.errors import DomainError, ErrorCode
from src.domain.common.records import RecordRepo, require_in_workspace
from src.domain.scholarships.schemas import SchemeOut, ScholarshipOut, SectionOut

_CHILDREN = ("scholarship_applications", "scholarship_schemes")


class SectionRepo(RecordRepo):
    async def tombstone(self, s: AsyncSession, entity_id: uuid.UUID) -> None:
        """Only an empty section can be removed; the client removes its contents first."""
        for table in _CHILDREN:
            busy = await s.execute(
                text(
                    f"SELECT 1 FROM {table} WHERE section_id = :id AND deleted_at IS NULL LIMIT 1"
                ),
                {"id": entity_id},
            )
            if busy.first() is not None:
                raise DomainError(
                    ErrorCode.DOMAIN_RULE_VIOLATION,
                    "Remove the section's applications and schemes before removing the section.",
                )
        await super().tombstone(s, entity_id)


class InSectionRepo(RecordRepo):
    """Records that belong to a section of the same workspace."""

    async def check(
        self,
        s: AsyncSession,
        workspace_id: uuid.UUID,
        entity_id: uuid.UUID,
        values: dict[str, Any],
        current: dict[str, Any] | None,
    ) -> dict[str, Any]:
        if current is None or "section_id" in values:
            if values.get("section_id") is None:
                raise DomainError(ErrorCode.VALIDATION_ERROR, "A section is required.")
            await require_in_workspace(
                s, "scholarship_sections", values["section_id"], workspace_id, "Section"
            )
        return values


_SECTION = ("name", "description", "position")
_SCHEME = ("section_id", "name", "organizing_body", "coverage", "strategy", "position")
_APPLICATION = (
    "section_id",
    "university",
    "program",
    "scheme",
    "portal_link",
    "opens_label",
    "deadline_at",
    "status",
    "documents_required",
    "cv_status",
    "transcripts_status",
    "letter_status",
    "references_status",
    "portal_status",
    "funding",
    "notes",
)

sections = SectionRepo(
    table="scholarship_sections",
    entity_type="scholarship_section",
    columns=_SECTION,
    updatable=_SECTION,
    out=SectionOut,
    label="Scholarship section",
)

schemes = InSectionRepo(
    table="scholarship_schemes",
    entity_type="scholarship_scheme",
    columns=_SCHEME,
    updatable=_SCHEME,
    out=SchemeOut,
    label="Scholarship scheme",
)

repo = InSectionRepo(
    table="scholarship_applications",
    entity_type="scholarship_application",
    columns=_APPLICATION,
    updatable=_APPLICATION,
    out=ScholarshipOut,
    label="Scholarship application",
)
