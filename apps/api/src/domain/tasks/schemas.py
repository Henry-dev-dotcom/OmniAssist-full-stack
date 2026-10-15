import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator

from src.domain.common.schemas import plain


class TaskStatus(StrEnum):
    inbox = "inbox"
    planned = "planned"
    in_progress = "in_progress"
    complete = "complete"
    snoozed = "snoozed"
    cancelled = "cancelled"
    archived = "archived"


class TaskPriority(StrEnum):
    low = "low"
    normal = "normal"
    high = "high"
    critical = "critical"


def _aware(v: datetime | None) -> datetime | None:
    if v is not None and v.tzinfo is None:
        raise ValueError("timestamp must include a UTC offset")
    return v


class _Fields(BaseModel):
    @field_validator("due_at", "completed_at", check_fields=False)
    @classmethod
    def _utc(cls, v: datetime | None) -> datetime | None:
        return _aware(v)


class TaskCreate(_Fields):
    id: uuid.UUID | None = None  # clients generate IDs so offline records keep identity
    workspace_id: uuid.UUID
    project_id: uuid.UUID | None = None
    parent_task_id: uuid.UUID | None = None
    title: str = Field(min_length=1, max_length=240)
    description: str | None = None
    status: TaskStatus = TaskStatus.inbox
    priority: TaskPriority = TaskPriority.normal
    due_at: datetime | None = None
    estimated_minutes: int | None = Field(default=None, gt=0)
    recurrence_rule: str | None = Field(default=None, max_length=500)
    completed_at: datetime | None = None

    def values(self) -> dict[str, Any]:
        return plain(self.model_dump())


class TaskUpdate(_Fields):
    project_id: uuid.UUID | None = None
    parent_task_id: uuid.UUID | None = None
    title: str | None = Field(default=None, min_length=1, max_length=240)
    description: str | None = None
    status: TaskStatus | None = None
    priority: TaskPriority | None = None
    due_at: datetime | None = None
    estimated_minutes: int | None = Field(default=None, gt=0)
    recurrence_rule: str | None = Field(default=None, max_length=500)
    completed_at: datetime | None = None

    def changes(self) -> dict[str, Any]:
        """Only the fields the caller sent. Sending null clears an optional field."""
        return plain(self.model_dump(exclude_unset=True))


class TaskOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    workspace_id: uuid.UUID
    project_id: uuid.UUID | None
    parent_task_id: uuid.UUID | None
    title: str
    description: str | None
    status: TaskStatus
    priority: TaskPriority
    due_at: datetime | None
    estimated_minutes: int | None
    recurrence_rule: str | None
    completed_at: datetime | None
    version: int
    updated_at: datetime
