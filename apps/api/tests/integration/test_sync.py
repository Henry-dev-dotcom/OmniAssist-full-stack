import uuid
from typing import Any

import httpx

from tests.integration.test_api_flows import auth, body, client, make_ws  # noqa: F401

DEVICE = str(uuid.uuid4())


def mut(ws: str, entity: str, op: str, changes: dict[str, Any], base: int | None = None) -> dict:
    return {
        "mutation_id": str(uuid.uuid4()), "workspace_id": ws, "entity_type": "project",
        "entity_id": entity, "operation": op, "base_version": base, "changes": changes,
    }  # fmt: skip


async def push(c: httpx.AsyncClient, who: str, *ms: dict) -> list[dict]:
    r = await c.post(
        "/sync/push",
        json={"device_id": DEVICE, "protocol_version": 1, "mutations": list(ms)},
        headers=auth(who),
    )
    assert r.status_code == 200, r.text
    return r.json()["data"]["results"]


async def pull(
    c: httpx.AsyncClient, who: str, cursor: int = 0, *, activity: bool = False, **q: Any
) -> dict:
    """Pulls one page; activity events are left out unless asked for."""
    r = await c.get("/sync/pull", params={"cursor": cursor, **q}, headers=auth(who))
    assert r.status_code == 200, r.text
    data: dict = r.json()["data"]
    if not activity:
        data["changes"] = [x for x in data["changes"] if x["entity_type"] != "activity_event"]
    return data


async def test_push_create_then_pull(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    pid = str(uuid.uuid4())
    [res] = await push(
        client, "ada", mut(ws, pid, "create", {"name": "Sync me", "category": "thesis"})
    )
    assert (res["status"], res["entity_version"]) == ("accepted", 1)
    page = await pull(client, "ada")
    assert [(c["entity_id"], c["operation"]) for c in page["changes"]] == [(pid, "create")]
    assert page["changes"][0]["payload"]["name"] == "Sync me"
    again = await pull(client, "ada", page["next_cursor"])
    assert again["changes"] == [] and again["next_cursor"] == page["next_cursor"]


async def test_replayed_mutation_is_idempotent(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    m = mut(ws, str(uuid.uuid4()), "create", {"name": "Once", "category": "thesis"})
    first = (await push(client, "ada", m))[0]
    second = (await push(client, "ada", m))[0]
    assert first == second
    feed = (await pull(client, "ada", activity=True))["changes"]
    # One record and one activity event: the replay duplicated neither (Spec 4.12).
    assert sorted(c["entity_type"] for c in feed) == ["activity_event", "project"]


async def test_reused_mutation_id_with_other_body_rejected(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    pid = str(uuid.uuid4())
    m = mut(ws, pid, "create", {"name": "A", "category": "thesis"})
    await push(client, "ada", m)
    other = {**m, "changes": {"name": "B", "category": "thesis"}}
    [res] = await push(client, "ada", other)
    assert res["error_code"] == "IDEMPOTENCY_KEY_REUSED"


async def test_update_merges_other_fields_and_conflicts_on_same_field(
    client: httpx.AsyncClient,  # noqa: F811
) -> None:
    ws = await make_ws(client, "ada")
    pid = str(uuid.uuid4())
    await push(client, "ada", mut(ws, pid, "create", {"name": "Base", "category": "thesis"}))
    # Another device renames (version 1 -> 2).
    await push(client, "ada", mut(ws, pid, "update", {"name": "Renamed"}, base=1))
    # Stale edit to a different field merges.
    [merged] = await push(client, "ada", mut(ws, pid, "update", {"status": "on_hold"}, base=1))
    assert (merged["status"], merged["entity_version"]) == ("accepted", 3)
    # Stale edit to the same field is a conflict, and the server keeps its value.
    [clash] = await push(client, "ada", mut(ws, pid, "update", {"name": "Mine"}, base=1))
    assert clash["status"] == "conflict" and clash["server"]["name"] == "Renamed"
    rows = (await client.get("/projects", params={"workspace_id": ws}, headers=auth("ada"))).json()
    assert rows["data"][0]["name"] == "Renamed" and rows["data"][0]["status"] == "on_hold"


async def test_one_bad_mutation_does_not_block_others(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    bad = mut(ws, str(uuid.uuid4()), "create", {"name": "", "category": "thesis"})
    good = mut(ws, str(uuid.uuid4()), "create", {"name": "Good", "category": "thesis"})
    r_bad, r_good = await push(client, "ada", bad, good)
    assert r_bad["error_code"] == "VALIDATION_ERROR" and r_good["status"] == "accepted"


async def test_delete_is_a_tombstone(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    pid = str(uuid.uuid4())
    await push(client, "ada", mut(ws, pid, "create", {"name": "Bye", "category": "thesis"}))
    [res] = await push(client, "ada", mut(ws, pid, "delete", {}, base=1))
    assert res["status"] == "accepted"
    ops = [c["operation"] for c in (await pull(client, "ada"))["changes"]]
    assert ops == ["create", "delete"]


async def test_rest_changes_appear_in_feed_and_pull_paginates(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    for n in range(3):
        await client.post("/projects", json=body(ws, name=f"P{n}"), headers=auth("ada"))
    first = await pull(client, "ada", limit=2)
    assert len(first["changes"]) == 2 and first["has_more"] is True
    rest = await pull(client, "ada", first["next_cursor"], limit=2)
    assert len(rest["changes"]) == 1 and rest["has_more"] is False


async def test_sync_is_private_between_users(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    pid = str(uuid.uuid4())
    await push(client, "ada", mut(ws, pid, "create", {"name": "Secret", "category": "thesis"}))
    assert (await pull(client, "bob"))["changes"] == []
    [res] = await push(
        client, "bob", mut(ws, str(uuid.uuid4()), "create", {"name": "X", "category": "thesis"})
    )
    assert res["error_code"] == "FORBIDDEN"
    [res2] = await push(client, "bob", mut(ws, pid, "update", {"name": "Hijack"}, base=1))
    assert res2["error_code"] == "FORBIDDEN"
