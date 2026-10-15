import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from src.domain.common.schemas import Utc, plain


class MilestoneStatus(StrEnum):
    not_started = "not_started"
    in_progress = "in_progress"
    at_risk = "at_risk"
    blocked = "blocked"
    complete = "complete"
    archived = "archived"


class ProgressMode(StrEnum):
    manual = "manual"
    weighted = "weighted"  # derived on the client from children and linked tasks (decision 0003)


class MilestoneCreate(BaseModel):
    id: uuid.UUID | None = None
    workspace_id: uuid.UUID
    project_id: uuid.UUID
    parent_id: uuid.UUID | None = None
    title: str = Field(min_length=1, max_length=240)
    description: str | None = Field(default=None, max_length=20000)
    status: MilestoneStatus = MilestoneStatus.not_started
    due_at: Utc | None = None
    progress_value: float = Field(default=0, ge=0, le=100)
    weight: float | None = Field(default=None, gt=0)
    progress_mode: ProgressMode = ProgressMode.manual
    depends_on: list[uuid.UUID] = Field(default_factory=list, max_length=50)

    def values(self) -> dict[str, Any]:
        return plain(self.model_dump())


class MilestoneUpdate(BaseModel):
    parent_id: uuid.UUID | None = None
    title: str | None = Field(default=None, min_length=1, max_length=240)
    description: str | None = Field(default=None, max_length=20000)
    status: MilestoneStatus | None = None
    due_at: Utc | None = None
    progress_value: float | None = Field(default=None, ge=0, le=100)
    weight: float | None = Field(default=None, gt=0)
    progress_mode: ProgressMode | None = None
    depends_on: list[uuid.UUID] | None = Field(default=None, max_length=50)

    def changes(self) -> dict[str, Any]:
        return plain(self.model_dump(exclude_unset=True))


class MilestoneOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    workspace_id: uuid.UUID
    project_id: uuid.UUID
    parent_id: uuid.UUID | None
    title: str
    description: str | None
    status: MilestoneStatus
    due_at: datetime | None
    progress_value: float
    weight: float | None
    progress_mode: ProgressMode
    completed_at: datetime | None
    depends_on: list[uuid.UUID]
    version: int
    updated_at: datetime
