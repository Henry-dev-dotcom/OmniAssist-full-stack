import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, HttpUrl

from src.domain.common.schemas import Utc, plain


class ScholarshipStatus(StrEnum):
    not_started = "not_started"
    preparing = "preparing"
    submitted = "submitted"
    under_review = "under_review"
    accepted = "accepted"
    rejected = "rejected"


class ChecklistStep(StrEnum):
    not_started = "not_started"
    in_progress = "in_progress"
    requested = "requested"
    registered = "registered"
    pending = "pending"
    ready = "ready"
    submitted = "submitted"


class _Fields(BaseModel):
    region: str = Field(min_length=1, max_length=80)
    university: str = Field(min_length=1, max_length=240)
    program: str | None = Field(default=None, max_length=500)
    scheme: str | None = Field(default=None, max_length=500)
    portal_link: HttpUrl | None = None
    opens_label: str | None = Field(default=None, max_length=120)
    deadline_at: Utc | None = None
    status: ScholarshipStatus = ScholarshipStatus.not_started
    documents_required: str | None = Field(default=None, max_length=2000)
    cv_status: ChecklistStep = ChecklistStep.not_started
    transcripts_status: ChecklistStep = ChecklistStep.not_started
    letter_status: ChecklistStep = ChecklistStep.not_started
    references_status: ChecklistStep = ChecklistStep.not_started
    portal_status: ChecklistStep = ChecklistStep.not_started
    funding: str | None = Field(default=None, max_length=1000)
    notes: str | None = Field(default=None, max_length=20000)

    def values(self) -> dict[str, Any]:
        out = plain(self.model_dump())
        if out.get("portal_link") is not None:
            out["portal_link"] = str(out["portal_link"])
        return out


class ScholarshipCreate(_Fields):
    id: uuid.UUID | None = None
    workspace_id: uuid.UUID


# Every field optional on update, with the same validation.
class ScholarshipUpdate(BaseModel):
    region: str | None = Field(default=None, min_length=1, max_length=80)
    university: str | None = Field(default=None, min_length=1, max_length=240)
    program: str | None = Field(default=None, max_length=500)
    scheme: str | None = Field(default=None, max_length=500)
    portal_link: HttpUrl | None = None
    opens_label: str | None = Field(default=None, max_length=120)
    deadline_at: Utc | None = None
    status: ScholarshipStatus | None = None
    documents_required: str | None = Field(default=None, max_length=2000)
    cv_status: ChecklistStep | None = None
    transcripts_status: ChecklistStep | None = None
    letter_status: ChecklistStep | None = None
    references_status: ChecklistStep | None = None
    portal_status: ChecklistStep | None = None
    funding: str | None = Field(default=None, max_length=1000)
    notes: str | None = Field(default=None, max_length=20000)

    def changes(self) -> dict[str, Any]:
        out = plain(self.model_dump(exclude_unset=True))
        if out.get("portal_link") is not None:
            out["portal_link"] = str(out["portal_link"])
        return out


class ScholarshipOut(_Fields):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    workspace_id: uuid.UUID
    version: int
    updated_at: datetime
