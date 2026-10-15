import uuid
from datetime import datetime
from typing import Annotated, Any, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, field_validator

from src.domain.notifications.service import validate_offset

Offset = Annotated[str, AfterValidator(validate_offset)]
Urgency = Literal["low", "normal", "high", "critical"]
Channel = Literal["push", "in_app", "email"]


class ReminderSet(BaseModel):
    """Replaces the task's scheduled reminders with these offsets."""

    offsets: list[Offset] = Field(default_factory=list, max_length=10)
    urgency: Urgency = "normal"
    channel: Channel = "push"

    @field_validator("offsets")
    @classmethod
    def _unique(cls, v: list[str]) -> list[str]:
        return list(dict.fromkeys(v))


class Snooze(BaseModel):
    minutes: int = Field(default=10, ge=1, le=60 * 24 * 7)


class NotificationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    workspace_id: uuid.UUID
    entity_type: str
    entity_id: uuid.UUID
    title: str
    remind_at: datetime
    urgency: str
    channel: str
    delivery_status: str
    offset_spec: str | None = None
    snoozed_until: datetime | None = None
    sent_at: datetime | None = None
    read_at: datetime | None = None
    failure_reason: str | None = None

    def dump(self) -> dict[str, Any]:
        return self.model_dump(mode="json")
