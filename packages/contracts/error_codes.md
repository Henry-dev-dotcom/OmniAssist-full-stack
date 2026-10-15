# Error codes

Every API error uses this envelope. `request_id` is always present.

```json
{"error": {"code": "VALIDATION_ERROR", "message": "Safe, human-readable text", "details": {}, "request_id": "req_uuid", "retryable": false}}
```

Success responses use `{"data": {}, "meta": {"request_id": "req_uuid"}}`.

Version conflicts add `entity_type`, `entity_id`, `server_version`, `client_version` to `details`.

| Code | HTTP | Retryable | Meaning |
|---|---:|---|---|
| `VALIDATION_ERROR` | 400 | no | Malformed or invalid input. `details.fields` lists problems. |
| `UNAUTHENTICATED` | 401 | no | Missing, expired or invalid token. Sign in again. |
| `FORBIDDEN` | 403 | no | Actor may not access this workspace or record. |
| `NOT_FOUND` | 404 | no | Record missing or tombstoned. |
| `VERSION_CONFLICT` | 409 | no | `base_version` does not match the server version. |
| `IDEMPOTENCY_KEY_REUSED` | 409 | no | Same `mutation_id` sent with a different request hash. |
| `DOMAIN_RULE_VIOLATION` | 422 | no | Valid shape, but breaks a rule (for example an invalid task transition). |
| `RATE_LIMITED` | 429 | yes | Too many requests. Back off. |
| `DEPENDENCY_UNAVAILABLE` | 503 | yes | Storage or provider unavailable. |
| `INTERNAL_ERROR` | 500 | yes | Unhandled failure. Quote `request_id` when reporting. |

Adding a code: update this table, `apps/api/src/domain/common/errors.py` and
`apps/client/lib/core/errors/error_codes.dart`. `test_error_contracts.py` fails if they differ.
