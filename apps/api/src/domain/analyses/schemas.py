import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, HttpUrl

from src.domain.common.schemas import Utc, plain


class AnalysisStatus(StrEnum):
    planned = "planned"
    running = "running"
    succeeded = "succeeded"
    failed = "failed"
    blocked = "blocked"
    archived = "archived"


class Language(StrEnum):
    r = "r"
    python = "python"


# Allowed moves (decision 0003). Archived records come back only through planned.
TRANSITIONS: dict[str, set[str]] = {
    "planned": {"running", "succeeded", "failed", "blocked", "archived"},
    "running": {"succeeded", "failed", "blocked", "planned"},
    "succeeded": {"running", "planned", "archived"},
    "failed": {"running", "planned", "blocked", "archived"},
    "blocked": {"planned", "running", "archived"},
    "archived": {"planned"},
}


class _Body(BaseModel):
    purpose: str | None = Field(default=None, max_length=5000)
    language: Language | None = None
    repository_url: HttpUrl | None = None
    branch_name: str | None = Field(default=None, max_length=255)
    commit_ref: str | None = Field(default=None, max_length=100)
    data_source_ref: str | None = Field(default=None, max_length=2000)
    environment: str | None = Field(default=None, max_length=5000)
    last_run_at: Utc | None = None
    result_summary: str | None = Field(default=None, max_length=20000)
    error_details: str | None = Field(default=None, max_length=20000)
    next_action: str | None = Field(default=None, max_length=2000)


def _urls(out: dict[str, Any]) -> dict[str, Any]:
    if out.get("repository_url") is not None:
        out["repository_url"] = str(out["repository_url"])
    return out


class AnalysisCreate(_Body):
    id: uuid.UUID | None = None
    workspace_id: uuid.UUID
    project_id: uuid.UUID
    milestone_id: uuid.UUID | None = None
    title: str = Field(min_length=1, max_length=240)
    status: AnalysisStatus = AnalysisStatus.planned

    def values(self) -> dict[str, Any]:
        return _urls(plain(self.model_dump()))


class AnalysisUpdate(_Body):
    milestone_id: uuid.UUID | None = None
    title: str | None = Field(default=None, min_length=1, max_length=240)
    status: AnalysisStatus | None = None

    def changes(self) -> dict[str, Any]:
        return _urls(plain(self.model_dump(exclude_unset=True)))


class AnalysisOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    workspace_id: uuid.UUID
    project_id: uuid.UUID
    milestone_id: uuid.UUID | None
    title: str
    purpose: str | None
    language: Language | None
    repository_url: str | None
    branch_name: str | None
    commit_ref: str | None
    data_source_ref: str | None
    environment: str | None
    status: AnalysisStatus
    last_run_at: datetime | None
    result_summary: str | None
    error_details: str | None
    next_action: str | None
    version: int
    updated_at: datetime
