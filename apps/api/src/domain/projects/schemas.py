import uuid
from datetime import datetime
from decimal import Decimal
from enum import StrEnum
from typing import Any, Self

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from src.domain.common.schemas import plain


class ProjectCategory(StrEnum):
    personal = "personal"
    thesis = "thesis"
    grant = "grant"
    review = "review"
    experiment = "experiment"
    analysis = "analysis"
    software = "software"


class ProjectStatus(StrEnum):
    planned = "planned"
    in_progress = "in_progress"
    on_hold = "on_hold"
    complete = "complete"
    archived = "archived"


class ProgressMode(StrEnum):
    manual = "manual"
    weighted = "weighted"


class _DateOrder(BaseModel):
    start_at: datetime | None = None
    target_at: datetime | None = None

    @model_validator(mode="after")
    def _order(self) -> Self:
        if self.start_at and self.target_at and self.target_at < self.start_at:
            raise ValueError("target_at must not be before start_at")
        return self

    @field_validator("start_at", "target_at")
    @classmethod
    def _aware(cls, v: datetime | None) -> datetime | None:
        if v is not None and v.tzinfo is None:
            raise ValueError("timestamp must include a UTC offset")
        return v


class ProjectCreate(_DateOrder):
    id: uuid.UUID | None = None  # clients generate IDs so offline records keep identity
    workspace_id: uuid.UUID
    name: str = Field(min_length=1, max_length=120)
    category: ProjectCategory
    status: ProjectStatus = ProjectStatus.planned
    description: str | None = None
    progress_mode: ProgressMode = ProgressMode.manual
    progress_value: Decimal = Field(default=Decimal(0), ge=0, le=100)

    def values(self) -> dict[str, Any]:
        return plain(self.model_dump())


class ProjectUpdate(_DateOrder):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    category: ProjectCategory | None = None
    status: ProjectStatus | None = None
    description: str | None = None
    progress_mode: ProgressMode | None = None
    progress_value: Decimal | None = Field(default=None, ge=0, le=100)

    def changes(self) -> dict[str, Any]:
        """Only the fields the caller sent, as plain values the database driver accepts."""
        return plain(self.model_dump(exclude_unset=True))


class ProjectOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    workspace_id: uuid.UUID
    name: str
    category: ProjectCategory
    status: ProjectStatus
    description: str | None
    start_at: datetime | None
    target_at: datetime | None
    progress_mode: ProgressMode
    progress_value: float
    version: int
    updated_at: datetime
