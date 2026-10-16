"""Built-in email/password sign-in against real PostgreSQL."""

from collections.abc import AsyncIterator

import httpx
import pytest
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from src.auth.dependencies import get_provider
from src.auth.local_provider import LocalProvider
from src.infrastructure.database.session import get_session
from src.main import app
from tests.integration.test_api_flows import _async


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
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://t/api/v1") as c:
        yield c
    app.dependency_overrides.clear()
    await engine.dispose()


ADA = {"email": "Ada@Example.com", "password": "analytical-engine", "display_name": "Ada"}


async def test_register_login_refresh_logout(client: httpx.AsyncClient) -> None:
    r = await client.post("/auth/register", json=ADA)
    assert r.status_code == 200, r.text
    access = r.json()["data"]["access_token"]

    me = await client.get("/me", headers={"Authorization": f"Bearer {access}"})
    assert me.status_code == 200, me.text
    assert me.json()["data"]["display_name"] == "Ada"

    # Email match ignores case.
    r = await client.post(
        "/auth/login", json={"email": "ada@example.com", "password": ADA["password"]}
    )
    assert r.status_code == 200, r.text
    session = r.json()["data"]

    # Refresh rotates: the old token works once, never twice.
    r = await client.post("/auth/refresh", json={"refresh_token": session["refresh_token"]})
    assert r.status_code == 200
    rotated = r.json()["data"]
    r = await client.post("/auth/refresh", json={"refresh_token": session["refresh_token"]})
    assert r.status_code == 401

    r = await client.post(
        "/auth/logout",
        json={"refresh_token": rotated["refresh_token"]},
        headers={"Authorization": f"Bearer {rotated['access_token']}"},
    )
    assert r.json()["data"] == {"signed_out": True}
    r = await client.post("/auth/refresh", json={"refresh_token": rotated["refresh_token"]})
    assert r.status_code == 401


async def test_duplicate_email_and_bad_password(client: httpx.AsyncClient) -> None:
    assert (await client.post("/auth/register", json=ADA)).status_code == 200
    r = await client.post("/auth/register", json={**ADA, "email": "ADA@example.com"})
    assert r.status_code == 422
    assert r.json()["error"]["code"] == "DOMAIN_RULE_VIOLATION"

    wrong = await client.post(
        "/auth/login", json={"email": ADA["email"], "password": "not-the-password"}
    )
    unknown = await client.post(
        "/auth/login", json={"email": "nobody@example.com", "password": "whatever-123"}
    )
    # Same answer for a wrong password and an unknown email.
    assert wrong.status_code == unknown.status_code == 401
    assert wrong.json()["error"]["message"] == unknown.json()["error"]["message"]


async def test_change_password_ends_other_sessions(client: httpx.AsyncClient) -> None:
    r = await client.post("/auth/register", json=ADA)
    first = r.json()["data"]
    other = (
        await client.post("/auth/login", json={"email": ADA["email"], "password": ADA["password"]})
    ).json()["data"]
    h = {"Authorization": f"Bearer {first['access_token']}"}

    bad = await client.post(
        "/auth/change-password",
        json={"current_password": "wrong-one", "new_password": "a-new-password"},
        headers=h,
    )
    assert bad.status_code == 400
    short = await client.post(
        "/auth/change-password",
        json={"current_password": ADA["password"], "new_password": "short"},
        headers=h,
    )
    assert short.status_code == 400

    r = await client.post(
        "/auth/change-password",
        json={"current_password": ADA["password"], "new_password": "a-new-password"},
        headers=h,
    )
    assert r.status_code == 200, r.text
    fresh = r.json()["data"]
    # The other device's refresh token is dead; this device continues with a new one.
    r = await client.post("/auth/refresh", json={"refresh_token": other["refresh_token"]})
    assert r.status_code == 401
    r = await client.post("/auth/refresh", json={"refresh_token": fresh["refresh_token"]})
    assert r.status_code == 200
    r = await client.post("/auth/login", json={"email": ADA["email"], "password": "a-new-password"})
    assert r.status_code == 200
