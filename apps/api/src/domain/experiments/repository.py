import json
import uuid
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.domain.common.ids import new_uuid7
from src.domain.common.records import RecordRepo, require_in_workspace
from src.domain.experiments.schemas import BODY_FIELDS, ExperimentOut
from src.domain.sync.repository import record_change


class ExperimentRepo(RecordRepo):
    async def check(
        self,
        s: AsyncSession,
        workspace_id: uuid.UUID,
        entity_id: uuid.UUID,
        values: dict[str, Any],
        current: dict[str, Any] | None,
    ) -> dict[str, Any]:
        if current is None:
            await require_in_workspace(s, "projects", values["project_id"], workspace_id, "Project")
            return values
        if current["state"] != "finalized":
            return values
        edits = any(
            k in values and values[k] != current[k] for k in (*BODY_FIELDS, "template_type")
        )
        if edits or values.get("state") == "draft":
            # A finalized entry is never edited in place: work continues on a new revision,
            # and the finalized one stays in experiment_revisions (Spec 4.10).
            return {
                **values,
                "revision_number": current["revision_number"] + 1,
                "state": values.get("state") or "draft",
            }
        return {k: v for k, v in values.items() if k != "state"}

    async def after_write(
        self,
        s: AsyncSession,
        row: dict[str, Any],
        values: dict[str, Any],
        before: dict[str, Any] | None,
        actor_id: uuid.UUID | None,
    ) -> None:
        newly_final = row["state"] == "finalized" and (
            before is None
            or before["state"] != "finalized"
            or before["revision_number"] != row["revision_number"]
        )
        if not newly_final or actor_id is None:
            return
        snapshot = self.payload(row, {*BODY_FIELDS, "template_type"})
        rid = new_uuid7()
        await s.execute(
            text(
                """INSERT INTO experiment_revisions
                (id, entry_id, revision_number, snapshot, actor_id)
                VALUES (:id, :e, :n, CAST(:snap AS jsonb), :a)"""
            ),
            {"id": rid, "e": row["id"], "n": row["revision_number"],
             "snap": json.dumps(snapshot), "a": actor_id},
        )  # fmt: skip
        # Revisions reach other devices through the feed, so history works offline.
        await record_change(
            s, row["workspace_id"], "experiment_revision", rid, "create", 1,
            {"id": str(rid), "entry_id": str(row["id"]),
             "revision_number": row["revision_number"], "snapshot": snapshot},
        )  # fmt: skip


repo = ExperimentRepo(
    table="experiment_entries",
    entity_type="experiment_entry",
    columns=("project_id", "template_type", *BODY_FIELDS, "state", "revision_number"),
    updatable=("template_type", *BODY_FIELDS, "state", "revision_number"),
    out=ExperimentOut,
    label="Experiment entry",
)


async def revisions(s: AsyncSession, entry_id: uuid.UUID) -> list[dict[str, Any]]:
    rows = await s.execute(
        text(
            """SELECT id, revision_number, snapshot, actor_id, created_at
            FROM experiment_revisions WHERE entry_id = :e ORDER BY revision_number"""
        ),
        {"e": entry_id},
    )
    return [dict(r) for r in rows.mappings()]
