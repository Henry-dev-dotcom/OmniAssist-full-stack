"""Search, export and account deletion (Spec 4.11) against real PostgreSQL."""

import io
import json
import zipfile
from collections.abc import AsyncIterator
from typing import Any

import httpx
import pytest
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from src.api.routes.exports import sessions
from src.auth.dependencies import get_provider
from src.auth.local_provider import LocalProvider
from src.infrastructure.database.session import get_session
from src.main import app
from tests.integration.test_api_flows import _async
from tests.integration.test_research import mut, new


@pytest.fixture
async def client(pg_url: str) -> AsyncIterator[httpx.AsyncClient]:
    engine = create_async_engine(_async(pg_url), poolclass=NullPool)
    factory = async_sessionmaker(engine, expire_on_commit=False)

    async def _session() -> AsyncIterator[AsyncSession]:
        async with factory() as s:
            yield s

    provider = LocalProvider(secret="t" * 40, sessions=factory)
    app.dependency_overrides[get_session] = _session
    app.dependency_overrides[get_provider] = lambda: provider
    app.dependency_overrides[sessions] = lambda: factory
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://t/api/v1") as c:
        yield c
    app.dependency_overrides.clear()
    await engine.dispose()


async def account(c: httpx.AsyncClient, name: str) -> tuple[dict[str, str], str, str]:
    """Registers, makes a workspace, returns (headers, workspace id, refresh token)."""
    r = await c.post(
        "/auth/register",
        json={"email": f"{name}@example.com", "password": "long-enough-pw", "display_name": name},
    )
    assert r.status_code == 200, r.text
    data = r.json()["data"]
    h = {"Authorization": f"Bearer {data['access_token']}"}
    ws = (await c.post("/workspaces", json={"name": "Lab"}, headers=h)).json()["data"]["id"]
    return h, ws, data["refresh_token"]


async def push(c: httpx.AsyncClient, h: dict[str, str], *ms: dict[str, Any]) -> None:
    r = await c.post(
        "/sync/push",
        json={"device_id": new(), "protocol_version": 1, "mutations": list(ms)},
        headers=h,
    )
    assert r.status_code == 200, r.text
    for res in r.json()["data"]["results"]:
        assert res["status"] == "accepted", res


async def seed(c: httpx.AsyncClient, h: dict[str, str], ws: str) -> str:
    pid = new()
    await push(
        c, h,
        mut(ws, "project", pid, "create", {"name": "Thesis", "category": "thesis"}),
        mut(ws, "task", new(), "create", {"title": "Write 100% of intro", "project_id": pid}),
        mut(ws, "analysis_record", new(), "create",
            {"project_id": pid, "title": "Mixed model", "status": "failed"}),
    )  # fmt: skip
    return pid


async def test_search_is_scoped_filtered_and_literal(client: httpx.AsyncClient) -> None:
    h, ws, _ = await account(client, "ada")
    pid = await seed(client, h, ws)

    async def search(**q: Any) -> list[dict[str, Any]]:
        r = await client.get("/search", params={"workspace_id": ws, **q}, headers=h)
        assert r.status_code == 200, r.text
        return list(r.json()["data"])

    assert [x["entity_type"] for x in await search(q="mixed")] == ["analysis_record"]
    [failed] = await search(q="model", type="analysis_record", status="failed")
    assert failed["project_id"] == pid
    assert [x["title"] for x in await search(q="100%")] == ["Write 100% of intro"]
    assert await search(q="1_0") == []  # "_" is not a wildcard
    assert {x["entity_type"] for x in await search(q="thesis")} == {"project"}

    bob, _, _ = await account(client, "bob")
    r = await client.get("/search", params={"workspace_id": ws, "q": "model"}, headers=bob)
    assert r.status_code in (403, 404)


async def test_export_json_and_csv_with_expiring_signed_link(
    client: httpx.AsyncClient,
) -> None:
    h, ws, _ = await account(client, "ada")
    await seed(client, h, ws)

    r = await client.post("/exports", json={"workspace_id": ws, "format": "json"}, headers=h)
    assert r.status_code == 202
    eid = r.json()["data"]["id"]
    status = (await client.get(f"/exports/{eid}", headers=h)).json()["data"]
    assert status["status"] == "ready", status
    body = json.loads((await client.get(status["download_url"])).content)
    assert body["format"] == "omniassist-export"
    assert [t["title"] for t in body["tasks"]] == ["Write 100% of intro"]
    assert {"version", "updated_at", "deleted_at"} <= body["projects"][0].keys()

    bad = status["download_url"].replace("token=", "token=0")
    assert (await client.get(bad)).status_code == 401
    expired = status["download_url"].replace("expires=", "expires=1")
    assert (await client.get(expired)).status_code == 401

    r = await client.post("/exports", json={"workspace_id": ws, "format": "csv"}, headers=h)
    status = (await client.get(f"/exports/{r.json()['data']['id']}", headers=h)).json()["data"]
    z = zipfile.ZipFile(io.BytesIO((await client.get(status["download_url"])).content))
    assert {"tasks.csv", "projects.csv", "analysis_records.csv"} <= set(z.namelist())

    bob, _, _ = await account(client, "bob")
    assert (await client.get(f"/exports/{eid}", headers=bob)).status_code == 404
    r = await client.post("/exports", json={"workspace_id": ws}, headers=bob)
    assert r.status_code in (403, 404)


async def test_delete_account_needs_confirmation_and_removes_everything(
    client: httpx.AsyncClient,
) -> None:
    h, ws, refresh = await account(client, "ada")
    await seed(client, h, ws)
    bob, bob_ws, _ = await account(client, "bob")
    await seed(client, bob, bob_ws)

    r = await client.request("DELETE", "/me", json={"confirm": "yes"}, headers=h)
    assert r.status_code == 400
    r = await client.request("DELETE", "/me", json={"confirm": "DELETE"}, headers=h)
    assert r.status_code == 200, r.text

    # Sessions end at once: the unexpired access token and the refresh token both fail.
    assert (await client.get("/me", headers=h)).status_code == 401
    r = await client.post("/auth/refresh", json={"refresh_token": refresh})
    assert r.status_code == 401
    r = await client.post(
        "/auth/login", json={"email": "ada@example.com", "password": "long-enough-pw"}
    )
    assert r.status_code == 401
    # The other account is untouched.
    r = await client.get("/search", params={"workspace_id": bob_ws, "q": "model"}, headers=bob)
    assert len(r.json()["data"]) == 1
