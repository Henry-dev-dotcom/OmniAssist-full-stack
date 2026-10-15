"""Milestones, reviews, analyses, experiments and activity through /sync/push."""

import uuid
from typing import Any

import httpx

from tests.integration.test_api_flows import auth, client, make_ws  # noqa: F401
from tests.integration.test_sync import pull, push


def mut(
    ws: str, kind: str, eid: str, op: str, changes: dict[str, Any], base: int | None = None
) -> dict[str, Any]:
    return {
        "mutation_id": str(uuid.uuid4()), "workspace_id": ws, "entity_type": kind,
        "entity_id": eid, "operation": op, "base_version": base, "changes": changes,
    }  # fmt: skip


def new() -> str:
    return str(uuid.uuid4())


async def project(c: httpx.AsyncClient, ws: str) -> str:
    pid = new()
    [r] = await push(c, "ada", mut(ws, "project", pid, "create",
                                   {"name": "Thesis", "category": "thesis"}))  # fmt: skip
    assert r["status"] == "accepted", r
    return pid


async def ok(c: httpx.AsyncClient, *ms: dict[str, Any], who: str = "ada") -> list[dict]:
    results = await push(c, who, *ms)
    for r in results:
        assert r["status"] == "accepted", r
    return results


async def get(c: httpx.AsyncClient, path: str, **q: Any) -> Any:
    r = await c.get(path, params=q, headers=auth("ada"))
    assert r.status_code == 200, r.text
    return r.json()["data"]


async def test_milestone_rules_and_task_link(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    pid = await project(client, ws)
    a, b, child = new(), new(), new()
    await ok(
        client,
        mut(ws, "milestone", a, "create", {"project_id": pid, "title": "Chapter 1"}),
        mut(ws, "milestone", b, "create",
            {"project_id": pid, "title": "Chapter 2", "depends_on": [a]}),
        mut(ws, "milestone", child, "create",
            {"project_id": pid, "title": "Lit review", "parent_id": a}),
    )  # fmt: skip
    # A depends on B, which depends on A: a cycle.
    [cyc] = await push(client, "ada", mut(ws, "milestone", a, "update", {"depends_on": [b]}, 1))
    assert cyc["error_code"] == "DOMAIN_RULE_VIOLATION"
    # Parent loop: A under its own child.
    [loop] = await push(client, "ada", mut(ws, "milestone", a, "update", {"parent_id": child}, 1))
    assert loop["error_code"] == "DOMAIN_RULE_VIOLATION"
    [bad] = await push(client, "ada", mut(ws, "milestone", a, "update", {"progress_value": 120}, 1))
    assert bad["error_code"] == "VALIDATION_ERROR"

    await ok(client, mut(ws, "milestone", a, "update", {"status": "complete"}, 1))
    [m] = [x for x in await get(client, "/milestones", workspace_id=ws) if x["id"] == a]
    assert m["status"] == "complete" and m["completed_at"] is not None
    [mb] = [x for x in await get(client, "/milestones", workspace_id=ws) if x["id"] == b]
    assert mb["depends_on"] == [a]

    # A task links to a milestone in the same workspace only.
    tid = new()
    await ok(client, mut(ws, "task", tid, "create", {"title": "Draft", "milestone_id": a}))
    other_ws = await make_ws(client, "ada", "Other")
    [cross] = await push(
        client, "ada", mut(other_ws, "task", new(), "create", {"title": "X", "milestone_id": a})
    )
    assert cross["error_code"] == "NOT_FOUND"


async def test_review_stages_items_and_history(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    pid = await project(client, ws)
    rid, item = new(), new()
    await ok(client, mut(ws, "review", rid, "create", {"project_id": pid, "name": "SLR"}))
    [review] = await get(client, "/reviews", workspace_id=ws)
    names = [st["name"] for st in review["stages"]]
    assert names == ["Protocol", "Screening", "Full Text", "Extraction", "Synthesis"]
    first, second = review["stages"][0]["id"], review["stages"][1]["id"]

    await ok(client, mut(ws, "review_item", item, "create",
                         {"review_id": rid, "title": "Smith 2020", "tags": ["rct"]}))  # fmt: skip
    await ok(client, mut(ws, "review_item", item, "update",
                         {"stage_id": second, "decision": "include"}, 1))  # fmt: skip
    [it] = await get(client, f"/reviews/{rid}/items")
    assert (it["stage_id"], it["decision"], it["tags"]) == (second, "include", ["rct"])
    history = await get(client, f"/review-items/{item}/history")
    assert [(h["from_stage_id"], h["to_stage_id"]) for h in history] == [
        (None, first),
        (first, second),
    ]

    stages = review["stages"]
    dup = [*stages, {"id": new(), "name": "screening", "archived": False}]
    [r1] = await push(client, "ada", mut(ws, "review", rid, "update", {"stages": dup}, 1))
    assert r1["error_code"] == "DOMAIN_RULE_VIOLATION"
    busy = [{**st, "archived": st["id"] == second} for st in stages]
    [r2] = await push(client, "ada", mut(ws, "review", rid, "update", {"stages": busy}, 1))
    assert r2["error_code"] == "DOMAIN_RULE_VIOLATION"  # stage still has an item
    renamed = [stages[1], {**stages[0], "name": "Plan"}, *stages[2:]]  # rename + reorder
    await ok(client, mut(ws, "review", rid, "update", {"stages": renamed}, 1))
    [review] = await get(client, "/reviews", workspace_id=ws)
    assert [st["name"] for st in review["stages"]][:2] == ["Screening", "Plan"]


async def test_analysis_transitions_and_run_time(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    pid = await project(client, ws)
    aid = new()
    await ok(client, mut(ws, "analysis_record", aid, "create",
                         {"project_id": pid, "title": "Mixed model", "language": "r"}))  # fmt: skip
    await ok(client, mut(ws, "analysis_record", aid, "update",
                         {"status": "failed", "error_details": "singular fit"}, 1))  # fmt: skip
    [rec] = await get(client, "/analysis-records", workspace_id=ws, status="failed")
    assert rec["last_run_at"] is not None and rec["error_details"] == "singular fit"
    await ok(client, mut(ws, "analysis_record", aid, "update", {"status": "archived"}, 2))
    [bad] = await push(
        client, "ada", mut(ws, "analysis_record", aid, "update", {"status": "succeeded"}, 3)
    )
    assert bad["error_code"] == "DOMAIN_RULE_VIOLATION"


async def test_experiment_finalize_and_revision(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    pid = await project(client, ws)
    eid = new()
    await ok(client, mut(ws, "experiment_entry", eid, "create", {
        "project_id": pid, "title": "qPCR run 1", "template_type": "qpcr",
        "occurred_at": "2026-10-15T09:00:00Z", "observations": "Ct 21",
    }))  # fmt: skip
    await ok(client, mut(ws, "experiment_entry", eid, "update", {"state": "finalized"}, 1))
    # Editing a finalized entry starts revision 2 as a draft; revision 1 is kept.
    await ok(client, mut(ws, "experiment_entry", eid, "update", {"observations": "Ct 22"}, 2))
    [entry] = await get(client, "/experiment-entries", workspace_id=ws)
    assert (entry["state"], entry["revision_number"], entry["observations"]) == (
        "draft",
        2,
        "Ct 22",
    )
    [rev] = await get(client, f"/experiment-entries/{eid}/revisions")
    assert (rev["revision_number"], rev["snapshot"]["observations"]) == (1, "Ct 21")
    # Revisions travel through the change feed for offline history.
    feed = (await pull(client, "ada"))["changes"]
    assert any(c["entity_type"] == "experiment_revision" for c in feed)


async def test_activity_timeline_and_conflict_resolution(
    client: httpx.AsyncClient,  # noqa: F811
) -> None:
    ws = await make_ws(client, "ada")
    pid = await project(client, ws)
    mid = new()
    await ok(client, mut(ws, "milestone", mid, "create", {"project_id": pid, "title": "M"}))
    await ok(client, mut(ws, "milestone", mid, "update", {"due_at": "2026-12-01T00:00:00Z"}, 1))
    [clash] = await push(
        client, "ada", mut(ws, "milestone", mid, "update", {"due_at": "2026-11-01T00:00:00Z"}, 1)
    )
    assert clash["status"] == "conflict"
    events = await get(client, "/activity", workspace_id=ws, entity_id=mid)
    assert [e["action"] for e in events] == ["updated", "created"]  # newest first
    assert events[0]["metadata"]["fields"] == ["due_at"]

    [open_c] = await get(client, "/sync/conflicts", workspace_id=ws)
    r = await client.post(
        f"/sync/conflicts/{open_c['id']}/resolve", json={"resolution": "keep_server"},
        headers=auth("ada"),
    )  # fmt: skip
    assert r.status_code == 200
    assert await get(client, "/sync/conflicts", workspace_id=ws) == []
    again = await client.post(
        f"/sync/conflicts/{open_c['id']}/resolve", json={"resolution": "keep_local"},
        headers=auth("bob"),
    )  # fmt: skip
    assert again.status_code == 404  # resolved, and never someone else's


async def test_other_users_cannot_read_or_write(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada")
    pid = await project(client, ws)
    rid = new()
    await ok(client, mut(ws, "review", rid, "create", {"project_id": pid, "name": "SLR"}))
    for path in ("/milestones", "/reviews", "/analysis-records", "/experiment-entries",
                 "/activity", "/sync/conflicts"):  # fmt: skip
        r = await client.get(path, params={"workspace_id": ws}, headers=auth("bob"))
        assert r.status_code in (403, 404), (path, r.status_code)
    r = await client.get(f"/reviews/{rid}/items", headers=auth("bob"))
    assert r.status_code == 404
    [w] = await push(client, "bob", mut(ws, "review", rid, "update", {"name": "Mine"}, 1))
    assert w["error_code"] == "FORBIDDEN"
