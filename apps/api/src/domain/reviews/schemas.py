import json
import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, field_validator

from src.domain.common.schemas import plain

DEFAULT_STAGES = ("Protocol", "Screening", "Full Text", "Extraction", "Synthesis")


class Decision(StrEnum):
    include = "include"
    exclude = "exclude"
    maybe = "maybe"


class Stage(BaseModel):
    id: uuid.UUID
    name: str = Field(min_length=1, max_length=80)
    archived: bool = False


class ReviewCreate(BaseModel):
    id: uuid.UUID | None = None
    workspace_id: uuid.UUID
    project_id: uuid.UUID
    name: str = Field(min_length=1, max_length=240)
    description: str | None = Field(default=None, max_length=20000)
    # Order is position. Omitted: the server adds the default stages (Spec 4.8).
    stages: list[Stage] | None = Field(default=None, max_length=30)

    def values(self) -> dict[str, Any]:
        return plain(self.model_dump())


class ReviewUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=240)
    description: str | None = Field(default=None, max_length=20000)
    stages: list[Stage] | None = Field(default=None, max_length=30)

    def changes(self) -> dict[str, Any]:
        return plain(self.model_dump(exclude_unset=True))


class ReviewOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    workspace_id: uuid.UUID
    project_id: uuid.UUID
    name: str
    description: str | None
    stages: list[Stage]
    version: int
    updated_at: datetime

    @field_validator("stages", mode="before")
    @classmethod
    def _decode(cls, v: Any) -> Any:
        return json.loads(v) if isinstance(v, str) else v


def _check_tags(v: list[str] | None) -> list[str] | None:
    if v is not None and any(not t.strip() or len(t) > 60 for t in v):
        raise ValueError("tags must be 1 to 60 characters")
    return v


class ReviewItemCreate(BaseModel):
    id: uuid.UUID | None = None
    workspace_id: uuid.UUID
    review_id: uuid.UUID
    stage_id: uuid.UUID | None = None  # omitted: the first active stage
    title: str = Field(min_length=1, max_length=1000)
    source_identifier: str | None = Field(default=None, max_length=500)
    decision: Decision | None = None
    reviewer: str | None = Field(default=None, max_length=120)
    tags: list[str] = Field(default_factory=list, max_length=50)
    notes: str | None = Field(default=None, max_length=20000)
    external_url: HttpUrl | None = None

    _tags = field_validator("tags")(_check_tags)

    def values(self) -> dict[str, Any]:
        out = plain(self.model_dump())
        out["external_url"] = None if self.external_url is None else str(self.external_url)
        return out


class ReviewItemUpdate(BaseModel):
    stage_id: uuid.UUID | None = None
    title: str | None = Field(default=None, min_length=1, max_length=1000)
    source_identifier: str | None = Field(default=None, max_length=500)
    decision: Decision | None = None
    reviewer: str | None = Field(default=None, max_length=120)
    tags: list[str] | None = Field(default=None, max_length=50)
    notes: str | None = Field(default=None, max_length=20000)
    external_url: HttpUrl | None = None

    _tags = field_validator("tags")(_check_tags)

    def changes(self) -> dict[str, Any]:
        out = plain(self.model_dump(exclude_unset=True))
        if "external_url" in out and out["external_url"] is not None:
            out["external_url"] = str(out["external_url"])
        return out


class ReviewItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    workspace_id: uuid.UUID
    review_id: uuid.UUID
    stage_id: uuid.UUID
    title: str
    source_identifier: str | None
    decision: Decision | None
    reviewer: str | None
    tags: list[str]
    notes: str | None
    external_url: str | None
    version: int
    updated_at: datetime

    @field_validator("tags", mode="before")
    @classmethod
    def _decode(cls, v: Any) -> Any:
        return json.loads(v) if isinstance(v, str) else v
