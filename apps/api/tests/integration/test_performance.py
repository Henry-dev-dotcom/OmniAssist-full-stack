"""Task 39: sync-load baseline. Bounds are loose so CI is stable; docs/performance.md holds
the measured numbers. Run with -s to print them."""

import time

import httpx

from tests.integration.test_api_flows import auth, client, make_ws  # noqa: F401
from tests.integration.test_research import mut, new
from tests.integration.test_sync import DEVICE


async def test_full_batch_push_pull_and_search_baseline(
    client: httpx.AsyncClient,  # noqa: F811
) -> None:
    ws = await make_ws(client, "ada")
    pid = new()
    batch = [mut(ws, "project", pid, "create", {"name": "Load", "category": "thesis"})]
    batch += [mut(ws, "task", new(), "create",
                  {"title": f"Task {i}", "project_id": pid}) for i in range(99)]  # fmt: skip

    t0 = time.perf_counter()
    r = await client.post(
        "/sync/push",
        json={"device_id": DEVICE, "protocol_version": 1, "mutations": batch},
        headers=auth("ada"),
    )
    push_s = time.perf_counter() - t0
    assert r.status_code == 200
    assert all(x["status"] == "accepted" for x in r.json()["data"]["results"])

    # A second, identical push is all replays: no work is done twice.
    t0 = time.perf_counter()
    again = await client.post(
        "/sync/push",
        json={"device_id": DEVICE, "protocol_version": 1, "mutations": batch},
        headers=auth("ada"),
    )
    replay_s = time.perf_counter() - t0
    assert again.json()["data"]["results"] == r.json()["data"]["results"]

    t0, cursor, pulled = time.perf_counter(), 0, 0
    while True:
        page = (
            await client.get(
                "/sync/pull", params={"cursor": cursor, "limit": 200}, headers=auth("ada")
            )
        ).json()["data"]
        pulled += len(page["changes"])
        cursor = page["next_cursor"]
        if not page["has_more"]:
            break
    pull_s = time.perf_counter() - t0
    assert pulled == 200  # 100 records + 100 activity events

    t0 = time.perf_counter()
    found = await client.get(
        "/search", params={"workspace_id": ws, "q": "task 9"}, headers=auth("ada")
    )
    search_s = time.perf_counter() - t0
    assert found.status_code == 200 and found.json()["data"]

    print(
        f"\npush 100: {push_s:.2f}s  replay 100: {replay_s:.2f}s  "
        f"pull 200: {pull_s:.2f}s  search: {search_s * 1000:.0f}ms"
    )
    assert push_s < 15 and replay_s < 10 and pull_s < 10 and search_s < 2
