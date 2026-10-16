"""Authorized server search (Spec 4.11). Simple ILIKE matching: the MVP has no search
cluster, and clients search their local copy first."""

import uuid
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

# entity type -> (table, title column, project column, status column, searched columns)
SOURCES: dict[str, tuple[str, str, str, str | None, tuple[str, ...]]] = {
    "project": ("projects", "name", "id", "status::text", ("name", "description")),
    "task": ("tasks", "title", "project_id", "status::text", ("title", "description")),
    "milestone": ("milestones", "title", "project_id", "status::text", ("title", "description")),
    "review_item": (
        "review_items", "title", "(SELECT v.project_id FROM reviews v WHERE v.id = r.review_id)",
        "decision", ("title", "notes", "source_identifier"),
    ),
    "analysis_record": (
        "analysis_records", "title", "project_id", "status",
        ("title", "purpose", "result_summary", "error_details", "next_action"),
    ),
    "experiment_entry": (
        "experiment_entries", "title", "project_id", "state",
        ("title", "objective", "observations", "result_summary", "next_steps"),
    ),
}  # fmt: skip


def _like(q: str) -> str:
    """Wildcards in the query match literally ("!" is the escape character)."""
    return "%" + q.replace("!", "!!").replace("%", "!%").replace("_", "!_") + "%"


async def search(
    s: AsyncSession,
    workspace_id: uuid.UUID,
    q: str,
    types: list[str] | None = None,
    project_id: uuid.UUID | None = None,
    status: str | None = None,
    limit: int = 50,
) -> list[dict[str, Any]]:
    parts = []
    for kind, (table, title, project, st, cols) in SOURCES.items():
        if types and kind not in types:
            continue
        match = " OR ".join(f"r.{c} ILIKE :q ESCAPE '!'" for c in cols)
        parts.append(
            f"""SELECT '{kind}' AS entity_type, r.id, r.{title} AS title,
              {"r." + project if not project.startswith("(") else project} AS project_id,
              {("r." + st) if st else "NULL"} AS status, r.updated_at
            FROM {table} r WHERE r.workspace_id = :w AND r.deleted_at IS NULL AND ({match})"""
        )
    if not parts:
        return []
    sql = f"SELECT * FROM ({' UNION ALL '.join(parts)}) hits WHERE true"
    params: dict[str, Any] = {"w": workspace_id, "q": _like(q), "lim": limit}
    if project_id is not None:
        sql += " AND project_id = :p"
        params["p"] = project_id
    if status:
        sql += " AND status = :st"
        params["st"] = status
    rows = await s.execute(text(sql + " ORDER BY updated_at DESC LIMIT :lim"), params)
    return [dict(r) for r in rows.mappings()]
