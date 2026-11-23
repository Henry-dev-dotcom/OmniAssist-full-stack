"""Reminders on grants, scholarship applications, milestones and time blocks."""

import uuid
from datetime import UTC, datetime, timedelta

import httpx
from sqlalchemy import text

from src.workers.reminder_worker import dispatch_due
from tests.integration.test_api_flows import auth, client, make_ws  # noqa: F401
from tests.integration.test_notifications import Recorder, _session


async def push(c: httpx.AsyncClient, ws: str, who: str, entity_type: str, changes: dict,
               operation: str = "create", entity_id: str | None = None,
               base_version: int | None = None) -> str:  # fmt: skip
    entity_id = entity_id or str(uuid.uuid4())
    r = await c.post(
        "/sync/push",
        json={
            "device_id": str(uuid.uuid4()),
            "protocol_version": 1,
            "mutations": [
                {
                    "mutation_id": str(uuid.uuid4()),
                    "workspace_id": ws,
                    "entity_type": entity_type,
                    "entity_id": entity_id,
                    "operation": operation,
                    "base_version": base_version,
                    "changes": changes,
                }
            ],
        },
        headers=auth(who),
    )
    result = r.json()["data"]["results"][0]
    assert result["status"] == "accepted", result
    return entity_id


async def scholarship(c: httpx.AsyncClient, ws: str, due_in: timedelta | None) -> str:
    section = await push(c, ws, "ada", "scholarship_section", {"name": "Russia"})
    deadline = (datetime.now(UTC) + due_in).isoformat() if due_in else None
    return await push(
        c, ws, "ada", "scholarship_application",
        {"section_id": section, "university": "Skoltech", "deadline_at": deadline},
    )  # fmt: skip


async def remind(c: httpx.AsyncClient, kind: str, eid: str, offsets: list[str], who: str = "ada"):  # type: ignore[no-untyped-def]
    return await c.put(f"/reminders/{kind}/{eid}", json={"offsets": offsets}, headers=auth(who))


async def test_scholarship_deadline_reminders_are_set_and_listed(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    app_id = await scholarship(client, ws, timedelta(days=10))
    r = await remind(client, "scholarship_application", app_id, ["custom:10080", "morning_before"])
    assert r.status_code == 200, r.text
    assert sorted(n["offset_spec"] for n in r.json()["data"]) == ["custom:10080", "morning_before"]
    assert {n["title"] for n in r.json()["data"]} == {"Scholarship deadline: Skoltech"}
    listed = await client.get("/reminders", params={"workspace_id": ws}, headers=auth("ada"))
    assert [(n["entity_type"], n["entity_id"]) for n in listed.json()["data"]] == [
        ("scholarship_application", app_id)
    ] * 2
    # Replacing with nothing clears them.
    assert (await remind(client, "scholarship_application", app_id, [])).status_code == 200
    listed = await client.get("/reminders", params={"workspace_id": ws}, headers=auth("ada"))
    assert listed.json()["data"] == []


async def test_rules_for_record_reminders(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    undated = await scholarship(client, ws, None)
    assert (await remind(client, "scholarship_application", undated, ["1d"])).status_code == 422
    grant = await push(
        client, ws, "ada", "funding_opportunity",
        {"title": "Wellcome", "organisation": "Wellcome", "category": "Project funding",
         "status": "awarded", "deadline_at": (datetime.now(UTC) + timedelta(days=5)).isoformat()},
    )  # fmt: skip
    assert (await remind(client, "funding_opportunity", grant, ["1d"])).status_code == 422
    assert (await remind(client, "project", grant, ["1d"])).status_code == 400
    soon = await scholarship(client, ws, timedelta(hours=2))
    r = await remind(client, "scholarship_application", soon, ["1d", "1h"])
    assert [n["offset_spec"] for n in r.json()["data"]] == ["1h"]
    assert r.json()["meta"]["warnings"] == [{"code": "REMINDER_IN_PAST", "count": 1}]
    assert (await remind(client, "scholarship_application", soon, ["1h"], "bob")).status_code == 404


async def test_time_block_reminder_is_sent_with_its_title(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    start = datetime.now(UTC) + timedelta(days=1)
    block = await client.post(
        "/time-blocks",
        json={"workspace_id": ws, "title": "Write letter", "starts_at": start.isoformat(),
              "ends_at": (start + timedelta(hours=1)).isoformat()},
        headers=auth("ada"),
    )  # fmt: skip
    bid = block.json()["data"]["id"]
    assert (await remind(client, "time_block", bid, ["15m"])).status_code == 200
    gen, s = await _session(client)
    gw = Recorder()
    res = await dispatch_due(s, gw, start + timedelta(minutes=1))
    await s.commit()
    await gen.aclose()
    assert (res.sent, [m.title for m in gw.sent]) == (1, ["Starting soon: Write letter"])


async def test_worker_cancels_when_submitted_and_follows_a_moved_deadline(
    client: httpx.AsyncClient,  # noqa: F811
) -> None:
    ws = await make_ws(client, "ada")
    submitted = await scholarship(client, ws, timedelta(days=3))
    await remind(client, "scholarship_application", submitted, ["1d"])
    moved = await scholarship(client, ws, timedelta(days=3))
    await remind(client, "scholarship_application", moved, ["1d"])
    gen, s = await _session(client)
    await s.execute(
        text("UPDATE scholarship_applications SET status = 'submitted' WHERE id = :i"),
        {"i": submitted},
    )
    await s.execute(
        text("UPDATE scholarship_applications SET deadline_at = deadline_at + interval '7 days' "
             "WHERE id = :i"),
        {"i": moved},
    )  # fmt: skip
    gw = Recorder()
    when = datetime.now(UTC) + timedelta(days=2, hours=12)
    res = await dispatch_due(s, gw, when)
    await s.commit()
    assert (res.sent, res.cancelled, res.deferred) == (0, 1, 1)
    # At the new time it goes out.
    res = await dispatch_due(s, gw, when + timedelta(days=7))
    await s.commit()
    await gen.aclose()
    assert (res.sent, [m.title for m in gw.sent]) == (1, ["Scholarship deadline: Skoltech"])
