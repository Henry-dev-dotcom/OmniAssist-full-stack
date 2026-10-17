"""Auth, profile, workspace and project routes against real PostgreSQL."""

import logging
import uuid
from collections.abc import AsyncIterator
from pathlib import Path
from typing import Any

import httpx
import pytest
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from src.auth.dependencies import get_provider
from src.infrastructure.database.session import get_session
from src.main import app
from tests.fakes import FakeProvider

API_DIR = Path(__file__).resolve().parents[2]


def _async(url: str) -> str:
    return url.replace("postgresql://", "postgresql+asyncpg://", 1)


@pytest.fixture
async def client(pg_url: str) -> AsyncIterator[httpx.AsyncClient]:
    engine = create_async_engine(_async(pg_url), poolclass=NullPool)
    factory = async_sessionmaker(engine, expire_on_commit=False)

    async def _session() -> AsyncIterator[AsyncSession]:
        async with factory() as s:
            yield s

    provider = FakeProvider()
    app.dependency_overrides[get_session] = _session
    app.dependency_overrides[get_provider] = lambda: provider
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://t/api/v1") as c:
        yield c
    app.dependency_overrides.clear()
    await engine.dispose()


def auth(who: str) -> dict[str, str]:
    return {"Authorization": f"Bearer access:{who}@example.com"}


async def make_ws(c: httpx.AsyncClient, who: str, name: str = "Lab") -> str:
    r = await c.post("/workspaces", json={"name": name}, headers=auth(who))
    assert r.status_code == 201, r.text
    return str(r.json()["data"]["id"])


def body(ws: str, **over: Any) -> dict[str, Any]:
    return {"workspace_id": ws, "name": "Thesis", "category": "thesis", **over}


async def test_login_refresh_logout(client: httpx.AsyncClient) -> None:
    r = await client.post("/auth/login", json={"email": "ada@example.com", "password": "pw"})
    assert r.status_code == 200
    data = r.json()["data"]
    assert data["access_token"] == "access:ada@example.com"
    r = await client.post("/auth/refresh", json={"refresh_token": data["refresh_token"]})
    assert r.status_code == 200
    r = await client.post(
        "/auth/logout", json={"refresh_token": data["refresh_token"]}, headers=auth("ada")
    )
    assert r.json()["data"] == {"signed_out": True}


async def test_bad_password_is_401_envelope(client: httpx.AsyncClient) -> None:
    r = await client.post("/auth/login", json={"email": "ada@example.com", "password": "no"})
    err = r.json()["error"]
    assert r.status_code == 401
    assert err["code"] == "UNAUTHENTICATED"
    assert err["request_id"]


@pytest.mark.parametrize(
    "hdr", [{}, {"Authorization": "Bearer junk"}, {"Authorization": "Basic x"}]
)
async def test_protected_routes_need_valid_token(
    client: httpx.AsyncClient, hdr: dict[str, str]
) -> None:
    r = await client.get("/me", headers=hdr)
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "UNAUTHENTICATED"


async def test_me_get_and_patch(client: httpx.AsyncClient) -> None:
    r = await client.get("/me", headers=auth("ada"))
    assert r.json()["data"]["email"] == "ada@example.com"
    r = await client.patch(
        "/me",
        json={"display_name": "Ada L", "timezone": "Africa/Accra", "preferences": {"x": 1}},
        headers=auth("ada"),
    )
    d = r.json()["data"]
    assert (d["display_name"], d["timezone"], d["preferences"]) == (
        "Ada L", "Africa/Accra", {"x": 1},
    )  # fmt: skip
    bad = await client.patch("/me", json={"timezone": "Mars/Base"}, headers=auth("ada"))
    assert bad.status_code == 400


async def test_workspace_create_and_list_are_private(client: httpx.AsyncClient) -> None:
    ws = await make_ws(client, "ada")
    mine = await client.get("/workspaces", headers=auth("ada"))
    assert [w["id"] for w in mine.json()["data"]] == [ws]
    theirs = await client.get("/workspaces", headers=auth("bob"))
    assert theirs.json()["data"] == []


async def test_project_crud_and_filters(client: httpx.AsyncClient) -> None:
    ws = await make_ws(client, "ada")
    h = auth("ada")
    r = await client.post("/projects", json=body(ws), headers=h)
    assert r.status_code == 201, r.text
    p = r.json()["data"]
    assert p["status"] == "planned"
    r = await client.patch(f"/projects/{p['id']}", json={"status": "archived"}, headers=h)
    assert r.json()["data"]["status"] == "archived"
    assert r.json()["data"]["version"] > p["version"]

    def ids(resp: httpx.Response) -> list[str]:
        return [x["id"] for x in resp.json()["data"]]

    active = await client.get("/projects", params={"workspace_id": ws}, headers=h)
    archived = await client.get(
        "/projects", params={"workspace_id": ws, "view": "archived"}, headers=h
    )
    everything = await client.get(
        "/projects", params={"workspace_id": ws, "view": "all"}, headers=h
    )
    assert ids(active) == []
    assert ids(archived) == [p["id"]]
    assert ids(everything) == [p["id"]]

    d = await client.delete(f"/projects/{p['id']}", headers=h)
    assert d.json()["data"]["deleted"] is True
    gone = await client.get("/projects", params={"workspace_id": ws, "view": "all"}, headers=h)
    assert ids(gone) == []


async def test_project_validation(client: httpx.AsyncClient) -> None:
    ws = await make_ws(client, "ada")
    h = auth("ada")
    for bad in (
        body(ws, name=""),
        body(ws, category="nope"),
        body(ws, progress_value=101),
        body(ws, start_at="2026-02-01T00:00:00Z", target_at="2026-01-01T00:00:00Z"),
    ):
        r = await client.post("/projects", json=bad, headers=h)
        assert r.status_code == 400, bad
        assert r.json()["error"]["code"] == "VALIDATION_ERROR"


async def test_funding_list_is_workspace_scoped(client: httpx.AsyncClient) -> None:
    ws = await make_ws(client, "ada")
    h = auth("ada")
    opportunity_id = str(uuid.uuid4())
    push = await client.post(
        "/sync/push",
        json={
            "device_id": str(uuid.uuid4()),
            "protocol_version": 1,
            "mutations": [
                {
                    "mutation_id": str(uuid.uuid4()),
                    "workspace_id": ws,
                    "entity_type": "funding_opportunity",
                    "entity_id": opportunity_id,
                    "operation": "create",
                    "changes": {
                        "title": "Research grant",
                        "organisation": "Research council",
                        "category": "Project funding",
                    },
                }
            ],
        },
        headers=h,
    )
    assert push.json()["data"]["results"][0]["status"] == "accepted"

    listed = await client.get("/funding-opportunities", params={"workspace_id": ws}, headers=h)
    assert listed.status_code == 200
    assert [row["id"] for row in listed.json()["data"]] == [opportunity_id]

    outsider = await client.get(
        "/funding-opportunities", params={"workspace_id": ws}, headers=auth("bob")
    )
    assert outsider.status_code == 403


async def test_cross_user_access_blocked(client: httpx.AsyncClient) -> None:
    ws = await make_ws(client, "ada")
    p = (await client.post("/projects", json=body(ws), headers=auth("ada"))).json()["data"]
    bob = auth("bob")
    assert (
        await client.get("/projects", params={"workspace_id": ws}, headers=bob)
    ).status_code == 403
    assert (await client.post("/projects", json=body(ws), headers=bob)).status_code == 403
    r = await client.patch(f"/projects/{p['id']}", json={"name": "x"}, headers=bob)
    assert (r.status_code, r.json()["error"]["code"]) == (404, "NOT_FOUND")
    assert (await client.delete(f"/projects/{p['id']}", headers=bob)).status_code == 404
    still = await client.get("/projects", params={"workspace_id": ws}, headers=auth("ada"))
    assert [x["name"] for x in still.json()["data"]] == ["Thesis"]


async def test_tokens_never_logged(
    client: httpx.AsyncClient, caplog: pytest.LogCaptureFixture
) -> None:
    caplog.set_level(logging.DEBUG)
    await client.get("/me", headers=auth("ada"))
    await client.post("/auth/login", json={"email": "ada@example.com", "password": "pw"})
    assert "access:ada" not in caplog.text
    assert "refresh:ada" not in caplog.text


async def test_project_patch_accepts_dates(client: httpx.AsyncClient) -> None:
    ws = await make_ws(client, "ada")
    p = (await client.post("/projects", json=body(ws), headers=auth("ada"))).json()["data"]
    r = await client.patch(
        f"/projects/{p['id']}",
        json={"start_at": "2026-01-01T00:00:00Z", "target_at": "2026-06-01T00:00:00Z"},
        headers=auth("ada"),
    )
    assert r.status_code == 200, r.text
    assert r.json()["data"]["target_at"].startswith("2026-06-01")
