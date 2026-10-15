# Sync protocol v1

Client mutates SQLite first, then uploads queued mutations. Server assigns a monotonic `sequence` per change and an `entity_version` per entity.

## Push: `POST /api/v1/sync/push`

```json
{"device_id": "uuid", "protocol_version": 1, "cursor": 921,
 "mutations": [{"mutation_id": "uuid", "workspace_id": "uuid", "entity_type": "task",
   "entity_id": "uuid", "operation": "update", "base_version": 4,
   "changes": {"status": "complete", "completed_at": "2026-10-14T18:00:00Z"}}]}
```

- `operation`: `create`, `update` or `delete`.
- `mutation_id` is the idempotency key. A repeat returns the earlier result. Same ID with a different request hash returns `IDEMPOTENCY_KEY_REUSED`.
- Each mutation returns `accepted` (with the new `entity_version`), `conflict`, or `rejected` (with an error code).

## Pull: `GET /api/v1/sync/pull?cursor=<n>`

```json
{"changes": [{"sequence": 922, "entity_type": "milestone", "entity_id": "uuid",
   "operation": "update", "entity_version": 5, "payload": {"status": "at_risk"}}],
 "next_cursor": 922, "has_more": false, "conflicts": []}
```

- Cursor is the last applied `sequence`. Start at 0.
- Delete changes carry a tombstone (`operation: "delete"`, no payload).
- Client applies a page in one local transaction and stores `next_cursor` in that same transaction.
- Loop while `has_more` is true.

## Conflict shape

```json
{"conflict_id": "uuid", "entity_type": "experiment_entry", "entity_id": "uuid",
 "base": {}, "local": {}, "server": {}, "status": "open"}
```

Resolution is a new mutation: keep local, keep server, or merge fields.

## Retry

Retry network errors, timeouts, 408, 429 and 5xx at 5s, 15s, 1m, 5m, 15m, then a capped interval, with jitter. Do not retry 400, 401, 403, 404 or validation errors without a new user action.
