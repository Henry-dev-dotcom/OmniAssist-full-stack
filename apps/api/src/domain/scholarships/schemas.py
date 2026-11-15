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


class _Stored(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    workspace_id: uuid.UUID
    version: int
    updated_at: datetime


class _Update(BaseModel):
    def changes(self) -> dict[str, Any]:
        return plain(self.model_dump(exclude_unset=True))


# --- sections ---------------------------------------------------------------------------


class _SectionFields(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    description: str | None = Field(default=None, max_length=2000)
    position: int = Field(default=0, ge=0, le=100000)

    def values(self) -> dict[str, Any]:
        return plain(self.model_dump())


class SectionCreate(_SectionFields):
    id: uuid.UUID | None = None
    workspace_id: uuid.UUID


class SectionUpdate(_Update):
    name: str | None = Field(default=None, min_length=1, max_length=80)
    description: str | None = Field(default=None, max_length=2000)
    position: int | None = Field(default=None, ge=0, le=100000)


class SectionOut(_SectionFields, _Stored):
    pass


# --- schemes ----------------------------------------------------------------------------


class _SchemeFields(BaseModel):
    section_id: uuid.UUID
    name: str = Field(min_length=1, max_length=240)
    organizing_body: str | None = Field(default=None, max_length=500)
    coverage: str | None = Field(default=None, max_length=2000)
    strategy: str | None = Field(default=None, max_length=5000)
    position: int = Field(default=0, ge=0, le=100000)

    def values(self) -> dict[str, Any]:
        return plain(self.model_dump())


class SchemeCreate(_SchemeFields):
    id: uuid.UUID | None = None
    workspace_id: uuid.UUID


class SchemeUpdate(_Update):
    section_id: uuid.UUID | None = None
    name: str | None = Field(default=None, min_length=1, max_length=240)
    organizing_body: str | None = Field(default=None, max_length=500)
    coverage: str | None = Field(default=None, max_length=2000)
    strategy: str | None = Field(default=None, max_length=5000)
    position: int | None = Field(default=None, ge=0, le=100000)


class SchemeOut(_SchemeFields, _Stored):
    pass


# --- applications -----------------------------------------------------------------------


def _link(out: dict[str, Any]) -> dict[str, Any]:
    if out.get("portal_link") is not None:
        out["portal_link"] = str(out["portal_link"])
    return out


class _Fields(BaseModel):
    section_id: uuid.UUID
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
        return _link(plain(self.model_dump()))


class ScholarshipCreate(_Fields):
    id: uuid.UUID | None = None
    workspace_id: uuid.UUID


# Every field optional on update, with the same validation.
class ScholarshipUpdate(BaseModel):
    section_id: uuid.UUID | None = None
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
        return _link(plain(self.model_dump(exclude_unset=True)))


class ScholarshipOut(_Fields, _Stored):
    pass
