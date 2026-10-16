"""Workspace export (Spec 4.11): a background job builds JSON or a ZIP of CSVs; the file is
fetched through a signed link that expires. Includes archived and deleted rows with their
sync metadata, so nothing the user owns is left out."""

import csv
import hashlib
import hmac
import io
import json
import uuid
import zipfile
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from src.domain.common.ids import new_uuid7

# Rows per table for workspace :w; child tables are reached through their parents.
TABLES: dict[str, str] = {
    "workspace": "SELECT * FROM workspaces WHERE id = :w",
    "projects": "SELECT * FROM projects WHERE workspace_id = :w",
    "tasks": "SELECT * FROM tasks WHERE workspace_id = :w",
    "time_blocks": "SELECT * FROM time_blocks WHERE workspace_id = :w",
    "milestones": "SELECT * FROM milestones WHERE workspace_id = :w",
    "milestone_dependencies": """SELECT d.* FROM milestone_dependencies d
        JOIN milestones m ON m.id = d.milestone_id WHERE m.workspace_id = :w""",
    "reviews": "SELECT * FROM reviews WHERE workspace_id = :w",
    "review_stages": """SELECT st.* FROM review_stages st
        JOIN reviews r ON r.id = st.review_id WHERE r.workspace_id = :w""",
    "review_items": "SELECT * FROM review_items WHERE workspace_id = :w",
    "review_item_events": """SELECT e.* FROM review_item_events e
        JOIN review_items i ON i.id = e.review_item_id WHERE i.workspace_id = :w""",
    "analysis_records": "SELECT * FROM analysis_records WHERE workspace_id = :w",
    "experiment_entries": "SELECT * FROM experiment_entries WHERE workspace_id = :w",
    "experiment_revisions": """SELECT v.* FROM experiment_revisions v
        JOIN experiment_entries e ON e.id = v.entry_id WHERE e.workspace_id = :w""",
    "notifications": "SELECT * FROM notifications WHERE workspace_id = :w",
    "activity_events": "SELECT * FROM activity_events WHERE workspace_id = :w",
}


def _plain(v: Any) -> Any:
    if isinstance(v, uuid.UUID | Decimal):
        return str(v)
    if isinstance(v, datetime | date):
        return v.isoformat()
    if isinstance(v, bytes | memoryview):
        return None
    return v


async def collect(s: AsyncSession, workspace_id: uuid.UUID) -> dict[str, list[dict[str, Any]]]:
    out = {}
    for name, sql in TABLES.items():
        rows = await s.execute(text(sql), {"w": workspace_id})
        out[name] = [{k: _plain(v) for k, v in r.items()} for r in rows.mappings()]
    return out


def to_json(data: dict[str, list[dict[str, Any]]]) -> bytes:
    body = {
        "format": "omniassist-export",
        "version": 1,
        "exported_at": datetime.now(UTC).isoformat(),
        **data,
    }
    return json.dumps(body, indent=2, default=_plain).encode()


def to_zip(data: dict[str, list[dict[str, Any]]]) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for name, rows in data.items():
            out = io.StringIO()
            cols = sorted({k for r in rows for k in r})
            w = csv.DictWriter(out, fieldnames=cols)
            w.writeheader()
            for r in rows:
                w.writerow(
                    {k: json.dumps(v) if isinstance(v, dict | list) else v for k, v in r.items()}
                )
            z.writestr(f"{name}.csv", out.getvalue())
    return buf.getvalue()


async def request(
    s: AsyncSession, workspace_id: uuid.UUID, user_id: uuid.UUID, fmt: str
) -> uuid.UUID:
    eid = new_uuid7()
    await s.execute(
        text(
            "INSERT INTO exports (id, workspace_id, requested_by, format) VALUES (:id, :w, :u, :f)"
        ),
        {"id": eid, "w": workspace_id, "u": user_id, "f": fmt},
    )
    return eid


async def build(
    sessions: async_sessionmaker[AsyncSession], export_id: uuid.UUID, ttl: timedelta
) -> None:
    """Background job. Never raises: a failure is recorded on the export row."""
    async with sessions() as s:
        row = (
            (
                await s.execute(
                    text("SELECT workspace_id, format FROM exports WHERE id = :id"),
                    {"id": export_id},
                )
            )
            .mappings()
            .one_or_none()
        )
        if row is None:
            return
        try:
            data = await collect(s, row["workspace_id"])
            content = to_json(data) if row["format"] == "json" else to_zip(data)
            await s.execute(
                text(
                    "UPDATE exports SET status = 'ready', content = :c, expires_at = :x "
                    "WHERE id = :id"
                ),
                {"c": content, "x": datetime.now(UTC) + ttl, "id": export_id},
            )
        except Exception:  # noqa: BLE001 - recorded as failed; content is never logged
            await s.rollback()
            await s.execute(
                text("UPDATE exports SET status = 'failed' WHERE id = :id"), {"id": export_id}
            )
        await s.commit()


def sign(secret: str, export_id: uuid.UUID, expires: int) -> str:
    msg = f"export:{export_id}:{expires}".encode()
    return hmac.new(secret.encode(), msg, hashlib.sha256).hexdigest()


def verify(secret: str, export_id: uuid.UUID, expires: int, token: str, now: float) -> bool:
    return expires > now and hmac.compare_digest(sign(secret, export_id, expires), token)
