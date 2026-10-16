"""Task 37: concurrency and authorization hardening against real PostgreSQL."""

import asyncio
import uuid

import httpx
import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from src.domain.sync import service
from tests.integration.test_api_flows import API_DIR, _async, auth, client, make_ws  # noqa: F401
from tests.integration.test_research import mut, new
from tests.integration.test_sync import push


async def test_same_mutation_pushed_concurrently_applies_once(pg_url: str) -> None:
    """Spec 4.12: a repeat never duplicates the record or its activity event, even when
    both copies arrive at the same moment (this used to fail with a 500)."""
    engine = create_async_engine(_async(pg_url), poolclass=NullPool)
    factory = async_sessionmaker(engine, expire_on_commit=False)
    user, ws = uuid.uuid4(), uuid.uuid4()
    async with factory() as s:
        await s.execute(
            text("INSERT INTO users (id, email, display_name) VALUES (:u, 'a@x.com', 'A')"),
            {"u": user},
        )
        await s.execute(
            text("INSERT INTO workspaces (id, owner_id, name) VALUES (:w, :u, 'W')"),
            {"w": ws, "u": user},
        )
        await s.execute(
            text("INSERT INTO workspace_members (workspace_id, user_id) VALUES (:w, :u)"),
            {"w": ws, "u": user},
        )
        await s.commit()

    m = service.MutationIn.model_validate(mut(str(ws), "task", new(), "create", {"title": "Once"}))

    async def first() -> dict:
        async with factory() as s:
            out = await service.apply_mutation(s, user, m)
            await asyncio.sleep(0.3)  # hold the row lock while the second one arrives
            await s.commit()
            return out

    async def second() -> dict:
        await asyncio.sleep(0.1)
        async with factory() as s:
            out = await service.apply_mutation(s, user, m)
            await s.commit()
            return out

    a, b = await asyncio.gather(first(), second())
    assert a == b and a["status"] == "accepted"
    async with factory() as s:
        counts = await s.execute(
            text(
                """SELECT (SELECT count(*) FROM tasks WHERE workspace_id = :w),
                          (SELECT count(*) FROM activity_events WHERE workspace_id = :w),
                          (SELECT count(*) FROM sync_changes
                           WHERE workspace_id = :w AND entity_type = 'task')"""
            ),
            {"w": ws},
        )
        assert tuple(counts.one()) == (1, 1, 1)
    await engine.dispose()


@pytest.mark.parametrize(
    "method,path",
    [
        ("GET", "/tasks?workspace_id={ws}"),
        ("GET", "/projects?workspace_id={ws}"),
        ("GET", "/time-blocks?workspace_id={ws}"),
        ("GET", "/notifications?workspace_id={ws}"),
        ("GET", "/milestones?workspace_id={ws}"),
        ("GET", "/reviews?workspace_id={ws}"),
        ("GET", "/analysis-records?workspace_id={ws}"),
        ("GET", "/experiment-entries?workspace_id={ws}"),
        ("GET", "/activity?workspace_id={ws}"),
        ("GET", "/sync/conflicts?workspace_id={ws}"),
        ("GET", "/search?workspace_id={ws}&q=a"),
        ("PATCH", "/tasks/{task}"),
        ("DELETE", "/tasks/{task}"),
        ("PATCH", "/projects/{project}"),
        ("DELETE", "/projects/{project}"),
        ("GET", "/reviews/{review}/items"),
        ("GET", "/experiment-entries/{entry}/revisions"),
    ],
)
async def test_other_users_get_nothing(
    client: httpx.AsyncClient,  # noqa: F811
    method: str,
    path: str,
) -> None:
    """Task 37: every read and write is checked against the user and the workspace."""
    ws = await make_ws(client, "ada")
    project, task, review, entry = new(), new(), new(), new()
    await push(
        client, "ada",
        mut(ws, "project", project, "create", {"name": "P", "category": "thesis"}),
        mut(ws, "task", task, "create", {"title": "T", "project_id": project}),
        mut(ws, "review", review, "create", {"project_id": project, "name": "R"}),
        mut(ws, "experiment_entry", entry, "create",
            {"project_id": project, "title": "E", "occurred_at": "2026-10-16T09:00:00Z"}),
    )  # fmt: skip
    url = path.format(ws=ws, task=task, project=project, review=review, entry=entry)
    body = {"title": "stolen"} if method == "PATCH" else None
    r = await client.request(method, url, json=body, headers=auth("bob"))
    assert r.status_code in (403, 404), (url, r.status_code, r.text)
    # Nothing changed for the owner.
    mine = await client.get(f"/tasks?workspace_id={ws}", headers=auth("ada"))
    assert [t["title"] for t in mine.json()["data"]] == ["T"]
