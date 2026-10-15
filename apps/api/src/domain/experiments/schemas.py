import uuid
from datetime import datetime
from enum import StrEnum
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

from src.domain.common.schemas import Utc, plain

# The experiment body: editing any of these on a finalized entry starts a new revision.
BODY_FIELDS = ("title", "occurred_at", "objective", "protocol", "variables", "materials",
               "observations", "deviations", "result_summary", "next_steps")  # fmt: skip


class Template(StrEnum):
    qpcr = "qpcr"
    primer_design = "primer_design"


class _Body(BaseModel):
    objective: str | None = Field(default=None, max_length=50000)
    protocol: str | None = Field(default=None, max_length=50000)
    variables: str | None = Field(default=None, max_length=50000)
    materials: str | None = Field(default=None, max_length=50000)
    observations: str | None = Field(default=None, max_length=50000)
    deviations: str | None = Field(default=None, max_length=50000)
    result_summary: str | None = Field(default=None, max_length=50000)
    next_steps: str | None = Field(default=None, max_length=50000)


class ExperimentCreate(_Body):
    id: uuid.UUID | None = None
    workspace_id: uuid.UUID
    project_id: uuid.UUID
    template_type: Template | None = None
    title: str = Field(min_length=1, max_length=240)
    occurred_at: Utc
    state: Literal["draft"] = "draft"  # finalizing is an explicit later action (Spec 4.10)

    def values(self) -> dict[str, Any]:
        return plain(self.model_dump())


class ExperimentUpdate(_Body):
    template_type: Template | None = None
    title: str | None = Field(default=None, min_length=1, max_length=240)
    occurred_at: Utc | None = None
    state: Literal["draft", "finalized"] | None = None

    def changes(self) -> dict[str, Any]:
        return plain(self.model_dump(exclude_unset=True))


class ExperimentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    workspace_id: uuid.UUID
    project_id: uuid.UUID
    template_type: Template | None
    title: str
    occurred_at: datetime
    objective: str | None
    protocol: str | None
    variables: str | None
    materials: str | None
    observations: str | None
    deviations: str | None
    result_summary: str | None
    next_steps: str | None
    state: Literal["draft", "finalized"]
    revision_number: int
    version: int
    updated_at: datetime
