"""MVP checkpoints (Tasks 24 and 33): the planning and academic journeys from Spec 3.1,
end to end through sync, as two devices of one user would run them."""

import uuid
from typing import Any

import httpx

from tests.integration.test_api_flows import auth, client, make_ws  # noqa: F401
from tests.integration.test_research import mut, new


class Device:
    """One client: queues mutations while 'offline', pushes them on reconnect, pulls."""

    def __init__(self, c: httpx.AsyncClient, who: str) -> None:
        self.c, self.who, self.id = c, who, str(uuid.uuid4())
        self.outbox: list[dict[str, Any]] = []
        self.cursor = 0

    def queue(self, m: dict[str, Any]) -> None:
        self.outbox.append(m)

    async def sync(self) -> list[dict[str, Any]]:
        r = await self.c.post(
            "/sync/push",
            json={"device_id": self.id, "protocol_version": 1, "mutations": self.outbox},
            headers=auth(self.who),
        )
        assert r.status_code == 200, r.text
        results: list[dict[str, Any]] = r.json()["data"]["results"]
        self.outbox = []
        page = (
            await self.c.get("/sync/pull", params={"cursor": self.cursor}, headers=auth(self.who))
        ).json()["data"]
        self.cursor = page["next_cursor"]
        return results


async def test_planning_journey(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada", "Personal")
    phone = Device(client, "ada")
    pid, tid, block = new(), new(), new()

    # 1-2. Create a project, then capture a task while offline.
    phone.queue(mut(ws, "project", pid, "create", {"name": "Thesis", "category": "thesis"}))
    phone.queue(mut(ws, "task", tid, "create", {"title": "Write intro"}))
    # 3. Assign project and due date. 4. Create a time block. 5. Complete it, still offline.
    phone.queue(mut(ws, "task", tid, "update",
                    {"project_id": pid, "status": "planned",
                     "due_at": "2026-10-20T17:00:00Z"}, 1))  # fmt: skip
    phone.queue(mut(ws, "time_block", block, "create", {
        "title": "Focus: intro", "category": "focus", "task_id": tid,
        "starts_at": "2026-10-20T09:00:00Z", "ends_at": "2026-10-20T11:00:00Z",
    }))  # fmt: skip
    phone.queue(mut(ws, "task", tid, "update", {"status": "complete"}, 2))

    # 6. Reconnect: everything lands exactly once.
    results = await phone.sync()
    assert [r["status"] for r in results] == ["accepted"] * 5
    tasks = (await client.get("/tasks", params={"workspace_id": ws}, headers=auth("ada"))).json()
    [task] = tasks["data"]
    assert (task["status"], task["project_id"]) == ("complete", pid)
    assert task["completed_at"] is not None
    # A lost acknowledgement makes the phone push again: no duplicates anywhere.
    phone.outbox = [mut(ws, "task", tid, "create", {"title": "Write intro"})]
    phone.outbox[0]["mutation_id"] = results[1]["mutation_id"]
    [again] = await phone.sync()
    assert again == results[1]
    activity = (
        await client.get("/activity", params={"workspace_id": ws}, headers=auth("ada"))
    ).json()["data"]
    assert sum(1 for e in activity if e["entity_id"] == tid and e["action"] == "created") == 1
    blocks = (
        await client.get(
            "/time-blocks",
            params={
                "workspace_id": ws,
                "start": "2026-10-20T00:00:00Z",
                "end": "2026-10-21T00:00:00Z",
            },
            headers=auth("ada"),
        )  # fmt: skip
    ).json()["data"]
    assert [b["task_id"] for b in blocks] == [tid]


async def test_academic_journey(client: httpx.AsyncClient) -> None:  # noqa: F811
    ws = await make_ws(client, "ada", "Lab")
    laptop, phone = Device(client, "ada"), Device(client, "ada")
    pid, ms, task, review, a1, exp = (new() for _ in range(6))

    # Thesis project, a milestone and a linked task.
    laptop.queue(mut(ws, "project", pid, "create", {"name": "PhD", "category": "thesis"}))
    laptop.queue(mut(ws, "milestone", ms, "create", {"project_id": pid, "title": "Chapter 2"}))
    laptop.queue(mut(ws, "task", task, "create",
                     {"title": "Draft 2.1", "project_id": pid, "milestone_id": ms}))  # fmt: skip
    # A review with imported records (a CSV import is one batch of creates).
    laptop.queue(mut(ws, "review", review, "create", {"project_id": pid, "name": "SLR"}))
    items = [new() for _ in range(3)]
    for i, item in enumerate(items):
        laptop.queue(mut(ws, "review_item", item, "create",
                         {"review_id": review, "title": f"Study {i}"}))  # fmt: skip
    # An analysis with a next action, and an experiment that gets finalized.
    laptop.queue(mut(ws, "analysis_record", a1, "create", {
        "project_id": pid, "milestone_id": ms, "title": "Mixed model",
        "language": "r", "next_action": "Refit with random slopes",
    }))  # fmt: skip
    laptop.queue(mut(ws, "experiment_entry", exp, "create", {
        "project_id": pid, "title": "qPCR 1", "template_type": "qpcr",
        "occurred_at": "2026-10-16T09:00:00Z", "observations": "Ct 21",
    }))  # fmt: skip
    laptop.queue(mut(ws, "experiment_entry", exp, "update", {"state": "finalized"}, 1))
    assert all(r["status"] == "accepted" for r in await laptop.sync())

    # Both devices edit offline: different fields merge, the same body field conflicts.
    laptop.queue(mut(ws, "analysis_record", a1, "update", {"status": "failed"}, 1))
    phone.queue(mut(ws, "analysis_record", a1, "update", {"error_details": "singular fit"}, 1))
    laptop.queue(mut(ws, "experiment_entry", exp, "update", {"observations": "Ct 22"}, 2))
    phone.queue(mut(ws, "experiment_entry", exp, "update", {"observations": "Ct 23"}, 2))
    first = await laptop.sync()
    second = await phone.sync()
    assert [r["status"] for r in first] == ["accepted", "accepted"]
    assert [r["status"] for r in second] == ["accepted", "conflict"]

    [rec] = (
        await client.get("/analysis-records", params={"workspace_id": ws}, headers=auth("ada"))
    ).json()["data"]
    assert (rec["status"], rec["error_details"]) == ("failed", "singular fit")
    # The failed record is findable through search.
    hits = (
        await client.get(
            "/search",
            params={"workspace_id": ws, "q": "mixed", "status": "failed"},
            headers=auth("ada"),
        )  # fmt: skip
    ).json()["data"]
    assert [h["id"] for h in hits] == [a1]
    # The finalized revision 1 is kept; the laptop's edit started revision 2.
    revs = (await client.get(f"/experiment-entries/{exp}/revisions", headers=auth("ada"))).json()
    assert [r["snapshot"]["observations"] for r in revs["data"]] == ["Ct 21"]
    # The conflict keeps both versions until the user resolves it.
    [conflict] = (
        await client.get("/sync/conflicts", params={"workspace_id": ws}, headers=auth("ada"))
    ).json()["data"]
    assert conflict["local_payload"]["observations"] == "Ct 23"
    assert conflict["server_payload"]["observations"] == "Ct 22"
