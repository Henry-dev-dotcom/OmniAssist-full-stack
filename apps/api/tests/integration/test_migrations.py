import os
import subprocess
import sys
from pathlib import Path

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError

API_DIR = Path(__file__).resolve().parents[2]

CORE_TABLES = {
    "users", "workspaces", "workspace_members", "projects", "milestones", "tasks", "tags",
    "task_tags", "time_blocks", "reviews", "review_stages", "review_items", "analysis_records",
    "experiment_entries", "experiment_revisions", "notifications", "attachments",
    "activity_events", "audit_events", "sync_changes", "sync_mutations", "sync_conflicts",
}  # fmt: skip


def alembic(url: str, *args: str) -> None:
    env = {**os.environ, "OMNI_MIGRATION_URL": url}
    subprocess.run(
        [sys.executable, "-m", "alembic", *args], cwd=API_DIR, env=env, check=True, timeout=120
    )


def engine(url: str):  # type: ignore[no-untyped-def]
    return create_engine(url.replace("postgresql://", "postgresql+psycopg://", 1))


def tables(url: str) -> set[str]:
    with engine(url).connect() as c:
        rows = c.execute(text("SELECT tablename FROM pg_tables WHERE schemaname='public'"))
        return {r[0] for r in rows} - {"alembic_version"}


def test_upgrade_creates_core_tables_and_indexes(empty_pg_url: str) -> None:
    alembic(empty_pg_url, "upgrade", "head")
    assert CORE_TABLES <= tables(empty_pg_url)
    with engine(empty_pg_url).connect() as c:
        idx = {r[0] for r in c.execute(text("SELECT indexname FROM pg_indexes"))}
    assert {"idx_tasks_workspace_due", "idx_sync_changes_workspace_sequence",
            "idx_sync_mutations_workspace_id"} <= idx  # fmt: skip


def test_downgrade_removes_everything(empty_pg_url: str) -> None:
    alembic(empty_pg_url, "upgrade", "head")
    alembic(empty_pg_url, "downgrade", "base")
    assert tables(empty_pg_url) == set()
    alembic(empty_pg_url, "upgrade", "head")  # and it can go up again


def test_constraints_reject_bad_rows(empty_pg_url: str) -> None:
    alembic(empty_pg_url, "upgrade", "head")
    owner = "00000000-0000-0000-0000-000000000001"
    with engine(empty_pg_url).begin() as c:
        c.execute(text(f"INSERT INTO users(id,email,display_name) VALUES ('{owner}','a@b.c','A')"))
        ws = c.execute(
            text(f"INSERT INTO workspaces(owner_id,name) VALUES ('{owner}','W') RETURNING id")
        ).scalar()
    bad = [
        f"INSERT INTO projects(id,workspace_id,name,category,progress_value) VALUES "
        f"(gen_random_uuid(),'{ws}','P','thesis',101)",
        f"INSERT INTO time_blocks(id,workspace_id,title,category,starts_at,ends_at) VALUES "
        f"(gen_random_uuid(),'{ws}','B','focus','2026-01-01T10:00Z','2026-01-01T09:00Z')",
        "INSERT INTO workspaces(owner_id,name) VALUES ('00000000-0000-0000-0000-000000000001','')",
    ]
    for sql in bad:
        with pytest.raises(IntegrityError), engine(empty_pg_url).begin() as c:
            c.execute(text(sql))
