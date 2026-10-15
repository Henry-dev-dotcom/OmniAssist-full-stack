from datetime import UTC, datetime, timedelta

import httpx
from sqlalchemy import text

from src.domain.notifications.repository import owner_settings  # noqa: F401
from src.infrastructure.notifications.gateway import DeliveryError, Message
from src.workers.reminder_worker import dispatch_due
from tests.integration.test_api_flows import auth, client, make_ws  # noqa: F401
from tests.integration.test_tasks import task


class Recorder:
    def __init__(self, fail: bool = False) -> None:
        self.sent: list[Message] = []
        self.fail = fail

    async def send(self, message: Message) -> None:
        if self.fail:
            raise DeliveryError("push provider down")
        self.sent.append(message)


QUIET = {"notifications": {"quiet_hours": {"start": "22:00", "end": "07:00"}}}


def iso(d: datetime) -> str:
    return d.isoformat()


async def mk_task(
    c: httpx.AsyncClient, ws: str, who: str, due_in: timedelta, **over: object
) -> dict:
    due = datetime.now(UTC) + due_in
    r = await c.post("/tasks", json=task(ws, due_at=iso(due), **over), headers=auth(who))
    assert r.status_code == 201, r.text
    return r.json()["data"]


async def remind(c, tid: str, who: str, offsets: list[str], **over) -> httpx.Response:  # type: ignore[no-untyped-def]
    return await c.put(
        f"/tasks/{tid}/reminders", json={"offsets": offsets, **over}, headers=auth(who)
    )


async def test_set_reminders_replaces_and_lists(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    t = await mk_task(client, ws, "ada", timedelta(days=3))
    r = await remind(client, t["id"], "ada", ["1h", "1d", "1h"])
    assert r.status_code == 200, r.text
    assert sorted(n["offset_spec"] for n in r.json()["data"]) == ["1d", "1h"]
    r = await remind(client, t["id"], "ada", ["15m"])
    got = await client.get(f"/tasks/{t['id']}/reminders", headers=auth("ada"))
    assert [n["offset_spec"] for n in got.json()["data"]] == ["15m"]


async def test_past_reminders_are_skipped_with_a_warning(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    t = await mk_task(client, ws, "ada", timedelta(minutes=30))
    r = await remind(client, t["id"], "ada", ["1h", "15m"])
    assert [n["offset_spec"] for n in r.json()["data"]] == ["15m"]
    assert r.json()["meta"]["warnings"] == [{"code": "REMINDER_IN_PAST", "count": 1}]


async def test_rules_for_new_reminders(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    h = auth("ada")
    undated = (await client.post("/tasks", json=task(ws), headers=h)).json()["data"]
    assert (await remind(client, undated["id"], "ada", ["1h"])).status_code == 422
    done = await mk_task(client, ws, "ada", timedelta(days=2), status="complete")
    assert (await remind(client, done["id"], "ada", ["1h"])).status_code == 422
    t = await mk_task(client, ws, "ada", timedelta(days=2))
    assert (await remind(client, t["id"], "ada", ["2h"])).status_code == 400
    assert (await remind(client, t["id"], "ada", ["1h"], urgency="loud")).status_code == 400


async def test_completing_or_moving_a_task_fixes_reminders(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    h = auth("ada")
    t = await mk_task(client, ws, "ada", timedelta(days=3))
    await remind(client, t["id"], "ada", ["1d"])
    before = (await client.get(f"/tasks/{t['id']}/reminders", headers=h)).json()["data"][0]
    new_due = datetime.now(UTC) + timedelta(days=6)
    await client.patch(f"/tasks/{t['id']}", json={"due_at": iso(new_due)}, headers=h)
    after = (await client.get(f"/tasks/{t['id']}/reminders", headers=h)).json()["data"]
    assert len(after) == 1 and after[0]["remind_at"] > before["remind_at"]
    expect = new_due - timedelta(days=1)
    got = datetime.fromisoformat(after[0]["remind_at"])
    assert abs((got - expect).total_seconds()) < 1

    await client.patch(f"/tasks/{t['id']}", json={"status": "complete"}, headers=h)
    assert (await client.get(f"/tasks/{t['id']}/reminders", headers=h)).json()["data"] == []
    # Reopening does not bring the old reminders back.
    await client.patch(f"/tasks/{t['id']}", json={"status": "planned"}, headers=h)
    assert (await client.get(f"/tasks/{t['id']}/reminders", headers=h)).json()["data"] == []


async def test_delete_and_clearing_due_date_cancel(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    h = auth("ada")
    a = await mk_task(client, ws, "ada", timedelta(days=3))
    b = await mk_task(client, ws, "ada", timedelta(days=3))
    for t in (a, b):
        await remind(client, t["id"], "ada", ["1h"])
    await client.delete(f"/tasks/{a['id']}", headers=h)
    await client.patch(f"/tasks/{b['id']}", json={"due_at": None}, headers=h)
    rows = await client.get(f"/tasks/{b['id']}/reminders", headers=h)
    assert rows.json()["data"] == []


async def test_quiet_hours_shift_reminders_but_not_critical(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    h = auth("ada")
    r = await client.patch(
        "/me",
        json={"timezone": "UTC", "preferences": QUIET},
        headers=h,
    )
    assert r.status_code == 200, r.text
    bad = await client.patch(
        "/me", json={"preferences": {"notifications": {"quiet_hours": {"start": "x"}}}}, headers=h
    )
    assert bad.status_code == 400
    tomorrow = datetime.now(UTC).replace(hour=23, minute=0, second=0, microsecond=0) + timedelta(
        days=2
    )
    t = await client.post("/tasks", json=task(ws, due_at=iso(tomorrow)), headers=h)
    tid = t.json()["data"]["id"]
    normal = (await remind(client, tid, "ada", ["at_due"])).json()["data"][0]
    assert datetime.fromisoformat(normal["remind_at"]).hour == 7
    crit = (await remind(client, tid, "ada", ["at_due"], urgency="critical")).json()["data"][0]
    assert datetime.fromisoformat(crit["remind_at"]).hour == 23


async def _session(client: httpx.AsyncClient):  # noqa: F811  # type: ignore[no-untyped-def]
    from src.infrastructure.database.session import get_session
    from src.main import app

    gen = app.dependency_overrides[get_session]()
    return gen, await gen.__anext__()


async def test_worker_sends_due_reminders_once(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    t = await mk_task(client, ws, "ada", timedelta(days=1))
    await remind(client, t["id"], "ada", ["1h"], channel="in_app")
    gen, s = await _session(client)
    gw = Recorder()
    early = await dispatch_due(s, gw, datetime.now(UTC))
    assert early.sent == 0
    late = datetime.now(UTC) + timedelta(days=2)
    res = await dispatch_due(s, gw, late)
    await s.commit()
    assert (res.sent, len(gw.sent)) == (1, 1)
    again = await dispatch_due(s, gw, late)
    assert again.sent == 0
    await gen.aclose()
    inbox = (
        await client.get("/notifications", params={"workspace_id": ws}, headers=auth("ada"))
    ).json()["data"]
    assert [(n["delivery_status"], n["title"]) for n in inbox] == [("sent", "Write methods")]


async def test_worker_skips_a_task_finished_since_scheduling(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    t = await mk_task(client, ws, "ada", timedelta(days=1))
    await remind(client, t["id"], "ada", ["1h"])
    gen, s = await _session(client)
    # Simulate a change that bypassed the API hook.
    await s.execute(text("UPDATE tasks SET status = 'complete' WHERE id = :i"), {"i": t["id"]})
    gw = Recorder()
    res = await dispatch_due(s, gw, datetime.now(UTC) + timedelta(days=2))
    await s.commit()
    await gen.aclose()
    assert (res.sent, res.cancelled, gw.sent) == (0, 1, [])


async def test_failed_delivery_is_recorded(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    t = await mk_task(client, ws, "ada", timedelta(days=1))
    await remind(client, t["id"], "ada", ["1h"])
    gen, s = await _session(client)
    res = await dispatch_due(s, Recorder(fail=True), datetime.now(UTC) + timedelta(days=2))
    await s.commit()
    await gen.aclose()
    assert res.failed == 1
    rows = (await client.get("/notifications", params={"workspace_id": ws, "status": "failed"},
                             headers=auth("ada"))).json()["data"]  # fmt: skip
    assert rows[0]["failure_reason"] == "push provider down"


async def test_worker_defers_when_quiet_hours_started_late(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    t = await mk_task(client, ws, "ada", timedelta(days=1))
    await remind(client, t["id"], "ada", ["1h"])
    await client.patch("/me", json={"preferences": {"notifications": {
        "quiet_hours": {"start": "00:00", "end": "23:59"}}}}, headers=auth("ada"))  # fmt: skip
    gen, s = await _session(client)
    gw = Recorder()
    res = await dispatch_due(s, gw, datetime.now(UTC) + timedelta(days=2, hours=1))
    await s.commit()
    await gen.aclose()
    assert (res.deferred, res.sent, gw.sent) == (1, 0, [])


async def _sent_one(client: httpx.AsyncClient, ws: str, who: str) -> str:  # noqa: F811
    t = await mk_task(client, ws, who, timedelta(days=1))
    await remind(client, t["id"], who, ["1h"])
    gen, s = await _session(client)
    await dispatch_due(s, Recorder(), datetime.now(UTC) + timedelta(days=2))
    await s.commit()
    await gen.aclose()
    rows = await client.get("/notifications", params={"workspace_id": ws}, headers=auth(who))
    return rows.json()["data"][0]["id"]


async def test_notification_states(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    h = auth("ada")
    nid = await _sent_one(client, ws, "ada")
    unread = await client.get(
        "/notifications", params={"workspace_id": ws, "unread": True}, headers=h
    )
    assert len(unread.json()["data"]) == 1
    assert (await client.post(f"/notifications/{nid}/read", headers=h)).json()["data"]["read_at"]
    unread = await client.get(
        "/notifications", params={"workspace_id": ws, "unread": True}, headers=h
    )
    assert unread.json()["data"] == []
    s = await client.post(f"/notifications/{nid}/snooze", json={"minutes": 30}, headers=h)
    assert s.json()["data"]["delivery_status"] == "snoozed"
    assert s.json()["data"]["snoozed_until"] is not None
    assert (await client.post(f"/notifications/{nid}/ack", headers=h)).status_code == 422
    d = await client.post(f"/notifications/{nid}/dismiss", headers=h)
    assert d.json()["data"]["delivery_status"] == "dismissed"
    assert (
        await client.post(f"/notifications/{nid}/snooze", json={}, headers=h)
    ).status_code == 422
    n2 = await _sent_one(client, ws, "ada")
    a = await client.post(f"/notifications/{n2}/ack", headers=h)
    assert a.json()["data"]["delivery_status"] == "acted_on"
    bad = await client.post(f"/notifications/{n2}/snooze", json={"minutes": 0}, headers=h)
    assert bad.status_code == 400


async def test_snoozed_notification_comes_back(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    h = auth("ada")
    nid = await _sent_one(client, ws, "ada")
    await client.post(f"/notifications/{nid}/snooze", json={"minutes": 10}, headers=h)
    gen, s = await _session(client)
    gw = Recorder()
    res = await dispatch_due(s, gw, datetime.now(UTC) + timedelta(days=3))
    await s.commit()
    await gen.aclose()
    assert res.sent == 1
    row = (await client.get("/notifications", params={"workspace_id": ws}, headers=h)).json()[
        "data"
    ][0]
    assert row["delivery_status"] == "sent" and row["snoozed_until"] is None
    assert row["read_at"] is None  # a returning reminder is unread again


async def test_other_users_cannot_see_or_touch(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    await make_ws(client, "bob")
    nid = await _sent_one(client, ws, "ada")
    b = auth("bob")
    assert (
        await client.get("/notifications", params={"workspace_id": ws}, headers=b)
    ).status_code == 403
    assert (await client.post(f"/notifications/{nid}/dismiss", headers=b)).status_code == 404
    t = await mk_task(client, ws, "ada", timedelta(days=2))
    assert (await remind(client, t["id"], "bob", ["1h"])).status_code == 404
