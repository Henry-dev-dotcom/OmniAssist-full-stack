import uuid

import httpx

from tests.integration.test_api_flows import auth, body, client, make_ws  # noqa: F401
from tests.integration.test_sync import mut, push


def blk(ws: str, start: str, end: str, **over: object) -> dict:
    return {"workspace_id": ws, "title": "Deep work", "starts_at": start, "ends_at": end, **over}


A = ("2026-10-15T09:00:00Z", "2026-10-15T10:00:00Z")
B = ("2026-10-15T09:30:00Z", "2026-10-15T10:30:00Z")
C = ("2026-10-15T10:00:00Z", "2026-10-15T11:00:00Z")


async def test_overlap_warns_but_saves(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    h = auth("ada")
    first = await client.post("/time-blocks", json=blk(ws, *A), headers=h)
    assert first.status_code == 201 and first.json()["meta"]["warnings"] == []
    second = await client.post("/time-blocks", json=blk(ws, *B), headers=h)
    assert second.status_code == 201
    w = second.json()["meta"]["warnings"]
    assert w[0]["code"] == "TIME_BLOCK_OVERLAP"
    assert w[0]["block_ids"] == [first.json()["data"]["id"]]
    touching = await client.post("/time-blocks", json=blk(ws, *C), headers=h)
    assert touching.json()["meta"]["warnings"][0]["block_ids"] == [second.json()["data"]["id"]]


async def test_cancelled_blocks_do_not_trigger_overlap(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    h = auth("ada")
    a = (await client.post("/time-blocks", json=blk(ws, *A), headers=h)).json()["data"]
    await client.patch(f"/time-blocks/{a['id']}", json={"status": "cancelled"}, headers=h)
    r = await client.post("/time-blocks", json=blk(ws, *B), headers=h)
    assert r.json()["meta"]["warnings"] == []


async def test_validation_and_transitions(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    h = auth("ada")
    bad = await client.post("/time-blocks", json=blk(ws, A[1], A[0]), headers=h)
    assert (bad.status_code, bad.json()["error"]["code"]) == (400, "VALIDATION_ERROR")
    b = (await client.post("/time-blocks", json=blk(ws, *A), headers=h)).json()["data"]
    done = await client.patch(f"/time-blocks/{b['id']}", json={"status": "complete"}, headers=h)
    assert done.json()["data"]["status"] == "complete"
    back = await client.patch(f"/time-blocks/{b['id']}", json={"status": "in_progress"}, headers=h)
    assert (back.status_code, back.json()["error"]["code"]) == (422, "DOMAIN_RULE_VIOLATION")
    # One-sided edit that inverts the stored range is rejected too.
    inv = await client.patch(
        f"/time-blocks/{b['id']}", json={"ends_at": "2026-10-15T08:00:00Z"}, headers=h
    )
    assert inv.status_code == 400


async def test_links_and_reschedule(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    h = auth("ada")
    t = (
        await client.post("/tasks", json={"workspace_id": ws, "title": "Write"}, headers=h)
    ).json()["data"]
    p = (await client.post("/projects", json=body(ws), headers=h)).json()["data"]
    b = (
        await client.post(
            "/time-blocks", json=blk(ws, *A, task_id=t["id"], project_id=p["id"]), headers=h
        )
    ).json()["data"]
    assert (b["task_id"], b["project_id"]) == (t["id"], p["id"])
    moved = await client.patch(
        f"/time-blocks/{b['id']}", json={"starts_at": B[0], "ends_at": B[1]}, headers=h
    )
    assert moved.json()["data"]["starts_at"].startswith("2026-10-15T09:30")
    other = await make_ws(client, "bob")
    foreign = (
        await client.post("/tasks", json={"workspace_id": other, "title": "X"}, headers=auth("bob"))
    ).json()["data"]
    r = await client.post("/time-blocks", json=blk(ws, *C, task_id=foreign["id"]), headers=h)
    assert (r.status_code, r.json()["error"]["code"]) == (404, "NOT_FOUND")


async def test_range_filter_and_privacy(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    h = auth("ada")
    await client.post("/time-blocks", json=blk(ws, *A), headers=h)
    await client.post(
        "/time-blocks", json=blk(ws, "2026-10-20T09:00:00Z", "2026-10-20T10:00:00Z"), headers=h
    )
    r = await client.get(
        "/time-blocks",
        params={"workspace_id": ws, "start": "2026-10-15T00:00:00Z", "end": "2026-10-16T00:00:00Z"},
        headers=h,
    )
    assert len(r.json()["data"]) == 1
    bob = auth("bob")
    assert (
        await client.get("/time-blocks", params={"workspace_id": ws}, headers=bob)
    ).status_code == 403
    bid = r.json()["data"][0]["id"]
    assert (
        await client.patch(f"/time-blocks/{bid}", json={"title": "x"}, headers=bob)
    ).status_code == 404
    assert (await client.delete(f"/time-blocks/{bid}", headers=bob)).status_code == 404


async def test_time_blocks_sync(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    bid = str(uuid.uuid4())

    def m(op: str, changes: dict, base: int | None = None) -> dict:
        x = mut(ws, bid, op, changes, base=base)
        x["entity_type"] = "time_block"
        return x

    [c] = await push(
        client, "ada", m("create", {"title": "Offline", "starts_at": A[0], "ends_at": A[1]})
    )
    assert c["status"] == "accepted"
    [u] = await push(client, "ada", m("update", {"starts_at": B[0], "ends_at": B[1]}, 1))
    assert u["status"] == "accepted"
    [bad] = await push(client, "ada", m("update", {"status": "complete"}, 2))
    [bad2] = await push(client, "ada", m("update", {"status": "in_progress"}, 3))
    assert bad["status"] == "accepted" and bad2["error_code"] == "DOMAIN_RULE_VIOLATION"
