import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, HttpUrl

from src.domain.common.schemas import Utc, plain


class FundingPriority(StrEnum):
    high = "high"
    medium = "medium"
    low = "low"

class FundingStatus(StrEnum):
    not_started = "not_started"
    researching = "researching"
    preparing = "preparing"
    submitted = "submitted"
    awarded = "awarded"
    rejected = "rejected"
    not_eligible = "not_eligible"

class _Fields(BaseModel):
    project_id: uuid.UUID | None = None
    category: str = Field(min_length=1, max_length=120)
    title: str = Field(min_length=1, max_length=240)
    organisation: str = Field(min_length=1, max_length=240)
    amount: str | None = Field(default=None, max_length=500)
    opens_label: str | None = Field(default=None, max_length=120)
    deadline_at: Utc | None = None
    deadline_type: str = Field(default="Not announced", max_length=40)
    eligibility_notes: str | None = Field(default=None, max_length=20000)
    priority: FundingPriority = FundingPriority.medium
    status: FundingStatus = FundingStatus.not_started
    date_applied: Utc | None = None
    next_action: str | None = Field(default=None, max_length=2000)
    official_link: HttpUrl | None = None
    other_source: str | None = Field(default=None, max_length=500)

    def values(self) -> dict[str, Any]:
        out = plain(self.model_dump())
        if out.get("official_link") is not None:
            out["official_link"] = str(out["official_link"])
        return out

class FundingCreate(_Fields):
    id: uuid.UUID | None = None
    workspace_id: uuid.UUID

# The update model keeps every field optional while retaining the same validation.
class FundingUpdate(BaseModel):
    project_id: uuid.UUID | None = None
    category: str | None = Field(default=None, min_length=1, max_length=120)
    title: str | None = Field(default=None, min_length=1, max_length=240)
    organisation: str | None = Field(default=None, min_length=1, max_length=240)
    amount: str | None = Field(default=None, max_length=500)
    opens_label: str | None = Field(default=None, max_length=120)
    deadline_at: Utc | None = None
    deadline_type: str | None = Field(default=None, max_length=40)
    eligibility_notes: str | None = Field(default=None, max_length=20000)
    priority: FundingPriority | None = None
    status: FundingStatus | None = None
    date_applied: Utc | None = None
    next_action: str | None = Field(default=None, max_length=2000)
    official_link: HttpUrl | None = None
    other_source: str | None = Field(default=None, max_length=500)

    def changes(self) -> dict[str, Any]:
        out = plain(self.model_dump(exclude_unset=True))
        if out.get("official_link") is not None:
            out["official_link"] = str(out["official_link"])
        return out

class FundingOut(_Fields):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    workspace_id: uuid.UUID
    version: int
    updated_at: datetime
