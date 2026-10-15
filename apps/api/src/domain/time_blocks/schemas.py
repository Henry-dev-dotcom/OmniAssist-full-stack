import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any, Self

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from src.domain.common.schemas import plain


class BlockStatus(StrEnum):
    planned = "planned"
    in_progress = "in_progress"
    complete = "complete"
    skipped = "skipped"
    cancelled = "cancelled"


def _aware(v: datetime | None) -> datetime | None:
    if v is not None and v.tzinfo is None:
        raise ValueError("timestamp must include a UTC offset")
    return v


class _Times(BaseModel):
    starts_at: datetime | None = None
    ends_at: datetime | None = None

    _utc = field_validator("starts_at", "ends_at")(_aware)

    @model_validator(mode="after")
    def _order(self) -> Self:
        if self.starts_at and self.ends_at and self.ends_at <= self.starts_at:
            raise ValueError("ends_at must be after starts_at")
        return self


class TimeBlockCreate(_Times):
    id: uuid.UUID | None = None  # clients generate IDs so offline records keep identity
    workspace_id: uuid.UUID
    task_id: uuid.UUID | None = None
    project_id: uuid.UUID | None = None
    title: str = Field(min_length=1, max_length=240)
    category: str = Field(default="focus", min_length=1, max_length=40)
    starts_at: datetime
    ends_at: datetime
    status: BlockStatus = BlockStatus.planned

    def values(self) -> dict[str, Any]:
        return plain(self.model_dump())


class TimeBlockUpdate(_Times):
    task_id: uuid.UUID | None = None
    project_id: uuid.UUID | None = None
    title: str | None = Field(default=None, min_length=1, max_length=240)
    category: str | None = Field(default=None, min_length=1, max_length=40)
    status: BlockStatus | None = None

    def changes(self) -> dict[str, Any]:
        return plain(self.model_dump(exclude_unset=True))


class TimeBlockOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    workspace_id: uuid.UUID
    task_id: uuid.UUID | None
    project_id: uuid.UUID | None
    title: str
    category: str
    starts_at: datetime
    ends_at: datetime
    status: BlockStatus
    version: int
    updated_at: datetime
