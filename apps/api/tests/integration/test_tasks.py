import uuid

import httpx

from tests.integration.test_api_flows import auth, body, client, make_ws  # noqa: F401
from tests.integration.test_sync import mut, pull, push


def task(ws: str, **over: object) -> dict:
    return {"workspace_id": ws, "title": "Write methods", **over}


async def test_task_defaults_and_crud(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    h = auth("ada")
    r = await client.post("/tasks", json=task(ws), headers=h)
    assert r.status_code == 201, r.text
    t = r.json()["data"]
    assert (t["status"], t["priority"], t["completed_at"]) == ("inbox", "normal", None)
    r = await client.patch(
        f"/tasks/{t['id']}", json={"title": "Methods v2", "priority": "high"}, headers=h
    )
    assert (r.json()["data"]["title"], r.json()["data"]["priority"]) == ("Methods v2", "high")
    d = await client.delete(f"/tasks/{t['id']}", headers=h)
    assert d.json()["data"]["deleted"] is True
    rows = await client.get("/tasks", params={"workspace_id": ws}, headers=h)
    assert rows.json()["data"] == []


async def test_complete_sets_and_clears_completion_time(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    h = auth("ada")
    t = (await client.post("/tasks", json=task(ws), headers=h)).json()["data"]
    done = (await client.patch(f"/tasks/{t['id']}", json={"status": "complete"}, headers=h)).json()[
        "data"
    ]
    assert done["completed_at"] is not None
    again = (await client.patch(f"/tasks/{t['id']}", json={"status": "planned"}, headers=h)).json()[
        "data"
    ]
    assert again["completed_at"] is None
    born_done = (await client.post("/tasks", json=task(ws, status="complete"), headers=h)).json()[
        "data"
    ]
    assert born_done["completed_at"] is not None


async def test_filters_by_status_and_project(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    h = auth("ada")
    proj = (await client.post("/projects", json=body(ws), headers=h)).json()["data"]
    a = (
        await client.post("/tasks", json=task(ws, title="A", project_id=proj["id"]), headers=h)
    ).json()["data"]
    await client.post("/tasks", json=task(ws, title="B", status="planned"), headers=h)

    async def ids(**q: str) -> list[str]:
        r = await client.get("/tasks", params={"workspace_id": ws, **q}, headers=h)
        return [x["id"] for x in r.json()["data"]]

    assert await ids(project_id=proj["id"]) == [a["id"]]
    assert len(await ids(status="planned")) == 1
    assert len(await ids()) == 2


async def test_links_must_stay_inside_the_workspace(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws_a = await make_ws(client, "ada")
    ws_b = await make_ws(client, "bob")
    foreign = (await client.post("/projects", json=body(ws_b), headers=auth("bob"))).json()["data"]
    r = await client.post("/tasks", json=task(ws_a, project_id=foreign["id"]), headers=auth("ada"))
    assert (r.status_code, r.json()["error"]["code"]) == (404, "NOT_FOUND")
    t = (await client.post("/tasks", json=task(ws_a), headers=auth("ada"))).json()["data"]
    own = await client.patch(
        f"/tasks/{t['id']}", json={"parent_task_id": t["id"]}, headers=auth("ada")
    )
    assert own.json()["error"]["code"] == "DOMAIN_RULE_VIOLATION"
    sub = (
        await client.post("/tasks", json=task(ws_a, parent_task_id=t["id"]), headers=auth("ada"))
    ).json()["data"]
    assert sub["parent_task_id"] == t["id"]


async def test_cross_user_access_blocked(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    t = (await client.post("/tasks", json=task(ws), headers=auth("ada"))).json()["data"]
    bob = auth("bob")
    assert (await client.get("/tasks", params={"workspace_id": ws}, headers=bob)).status_code == 403
    assert (await client.post("/tasks", json=task(ws), headers=bob)).status_code == 403
    assert (
        await client.patch(f"/tasks/{t['id']}", json={"title": "x"}, headers=bob)
    ).status_code == 404
    assert (await client.delete(f"/tasks/{t['id']}", headers=bob)).status_code == 404


async def test_validation(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    for bad in (task(ws, title=""), task(ws, status="nope"), task(ws, estimated_minutes=0),
                task(ws, due_at="2026-01-01T00:00:00")):  # fmt: skip
        r = await client.post("/tasks", json=bad, headers=auth("ada"))
        assert r.status_code == 400, bad


async def test_tasks_sync_create_update_merge_delete(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    tid = str(uuid.uuid4())
    m = mut(ws, tid, "create", {"title": "Offline task"})
    m["entity_type"] = "task"
    [res] = await push(client, "ada", m)
    assert (res["status"], res["entity_version"]) == ("accepted", 1)

    def upd(changes: dict, base: int) -> dict:
        u = mut(ws, tid, "update", changes, base=base)
        u["entity_type"] = "task"
        return u

    await push(client, "ada", upd({"title": "Renamed"}, 1))
    [merged] = await push(client, "ada", upd({"status": "complete"}, 1))
    assert merged["status"] == "accepted"
    [clash] = await push(client, "ada", upd({"title": "Mine"}, 1))
    assert clash["status"] == "conflict" and clash["server"]["title"] == "Renamed"
    rows = (await client.get("/tasks", params={"workspace_id": ws}, headers=auth("ada"))).json()[
        "data"
    ]
    assert rows[0]["status"] == "complete" and rows[0]["completed_at"] is not None
    # The completion time travels in the change feed so other devices see it.
    last = (await pull(client, "ada"))["changes"][-1]
    assert last["payload"]["status"] == "complete" and last["payload"]["completed_at"]
    gone = mut(ws, tid, "delete", {}, base=3)
    gone["entity_type"] = "task"
    [d] = await push(client, "ada", gone)
    assert d["status"] == "accepted"


async def test_sync_task_cannot_link_foreign_project(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws_a = await make_ws(client, "ada")
    ws_b = await make_ws(client, "bob")
    foreign = (await client.post("/projects", json=body(ws_b), headers=auth("bob"))).json()["data"]
    m = mut(ws_a, str(uuid.uuid4()), "create", {"title": "X", "project_id": foreign["id"]})
    m["entity_type"] = "task"
    [res] = await push(client, "ada", m)
    assert res["status"] == "rejected" and res["error_code"] == "NOT_FOUND"
