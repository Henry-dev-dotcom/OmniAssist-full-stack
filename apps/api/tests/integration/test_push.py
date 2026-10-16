"""Web push (decision 0006): subscriptions, the public key, and delivery."""

import json
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import httpx
import pytest
from py_vapid import Vapid02, b64urldecode
from pywebpush import WebPushException
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from src.config import settings
from src.infrastructure.notifications import webpush as wp
from src.workers.reminder_worker import dispatch_due
from tests.integration.test_api_flows import _async, auth, client, make_ws  # noqa: F401
from tests.integration.test_research import mut, new
from tests.integration.test_sync import push

SUB = {
    "endpoint": "https://push.example.com/send/abc",
    "keys": {"p256dh": "BPublicKeyOfTheDevice", "auth": "secretAuth"},
}


def test_generated_keys_have_the_right_shape() -> None:
    private, public = wp.generate_keys()
    assert len(b64urldecode(private.encode())) == 32
    raw = b64urldecode(public.encode())
    assert len(raw) == 65 and raw[0] == 4  # uncompressed P-256 point
    # pywebpush loads the private key this way when it signs each push.
    headers = Vapid02.from_string(private).sign(
        {"sub": "mailto:ops@example.com", "aud": "https://push.example.com"}
    )
    assert headers["Authorization"].startswith("vapid t=")


async def test_subscribe_and_public_key(
    client: httpx.AsyncClient,  # noqa: F811
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    await make_ws(client, "ada")
    monkeypatch.setattr(settings, "vapid_public_key", "")  # not configured
    assert (await client.get("/push/public-key", headers=auth("ada"))).status_code == 404
    monkeypatch.setattr(settings, "vapid_public_key", "BTestPublicKey")
    r = await client.get("/push/public-key", headers=auth("ada"))
    assert r.json()["data"]["public_key"] == "BTestPublicKey"

    insecure = {**SUB, "endpoint": "http://push.example.com/x"}
    assert (
        await client.post("/push/subscriptions", json=insecure, headers=auth("ada"))
    ).status_code == 400
    assert (
        await client.post("/push/subscriptions", json=SUB, headers=auth("ada"))
    ).status_code == 200
    # Another user cannot remove ada's device.
    await make_ws(client, "bob")
    await client.post(
        "/push/subscriptions/remove", json={"endpoint": SUB["endpoint"]}, headers=auth("bob")
    )
    r = await client.post(
        "/push/subscriptions/remove", json={"endpoint": SUB["endpoint"]}, headers=auth("ada")
    )
    assert r.json()["data"] == {"subscribed": False}


async def test_due_reminder_is_pushed_and_dead_devices_are_dropped(
    client: httpx.AsyncClient,  # noqa: F811
    pg_url: str,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    ws = await make_ws(client, "ada")
    dead = {**SUB, "endpoint": "https://push.example.com/send/gone"}
    for s in (SUB, dead):
        await client.post("/push/subscriptions", json=s, headers=auth("ada"))
    due = (datetime.now(UTC) + timedelta(minutes=5)).isoformat()
    tid = new()
    await push(client, "ada", mut(ws, "task", tid, "create",
                                  {"title": "Submit ethics form", "due_at": due}))  # fmt: skip
    # The app mirrors the reminders the user set on the task (server_reminders.dart).
    r = await client.put(
        f"/tasks/{tid}/reminders", json={"offsets": ["at_due"]}, headers=auth("ada")
    )
    assert r.status_code == 200, r.text

    engine = create_async_engine(_async(pg_url), poolclass=NullPool)
    factory = async_sessionmaker(engine, expire_on_commit=False)
    sent: list[dict[str, Any]] = []

    def fake_webpush(**kw: Any) -> None:
        if kw["subscription_info"]["endpoint"].endswith("/gone"):
            raise WebPushException("gone", response=type("R", (), {"status_code": 410})())
        sent.append(kw)

    monkeypatch.setattr(wp, "webpush", fake_webpush)
    gateway = wp.WebPushGateway(factory, "private-key", "mailto:ops@example.com")
    async with factory() as s:
        result = await dispatch_due(s, gateway, now=datetime.now(UTC) + timedelta(hours=1))
        await s.commit()
    assert result.sent >= 1

    [call] = sent
    body = json.loads(call["data"])
    assert body["title"] == "Submit ethics form"
    assert call["vapid_claims"] == {"sub": "mailto:ops@example.com"}
    assert call["headers"]["Urgency"] in ("normal", "high")
    async with factory() as s:
        left = (await s.execute(text("SELECT endpoint FROM push_subscriptions"))).scalars().all()
    assert left == [SUB["endpoint"]]  # the 410 one was removed
    await engine.dispose()


async def test_account_deletion_removes_push_devices(pg_url: str) -> None:
    """The FK cascades, so a deleted user leaves no device addresses behind."""
    engine = create_async_engine(_async(pg_url), poolclass=NullPool)
    factory: async_sessionmaker[AsyncSession] = async_sessionmaker(engine)

    u = uuid.uuid4()
    async with factory() as s:
        await s.execute(
            text("INSERT INTO users (id, email, display_name) VALUES (:u, 'x@x.com', 'X')"),
            {"u": u},
        )
        await s.execute(
            text(
                "INSERT INTO push_subscriptions (endpoint, user_id, p256dh, auth) "
                "VALUES ('https://p/1', :u, 'k', 'a')"
            ),
            {"u": u},
        )
        await s.execute(text("DELETE FROM users WHERE id = :u"), {"u": u})
        await s.commit()
        n = (await s.execute(text("SELECT count(*) FROM push_subscriptions"))).scalar_one()
    assert n == 0
    await engine.dispose()
