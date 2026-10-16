# Shared API contracts

This workspace package (`@omniassist/contracts`) is the active TypeScript contract for the web client. Import its envelope types, stable error codes, and shared domain models rather than duplicating API shapes in feature code.

```ts
import type { Project, SuccessEnvelope } from "@omniassist/contracts";
import { requestApi } from "@/lib/api/client";

const result: SuccessEnvelope<Project[]> = await requestApi<Project[]>("/api/v1/projects");
```

The canonical error-code list lives in `src/index.ts` and must match `apps/api/src/domain/common/errors.py` and [`error_codes.md`](error_codes.md). `apps/api/tests/unit/test_error_contracts.py` checks the code set, documentation, and request-ID behavior. Update all three when a code is added or removed.

Shared domain timestamps are ISO-8601 strings as serialized by FastAPI. IDs are strings (UUIDs on the server). API response payloads use `SuccessEnvelope<T>`; errors use `ErrorEnvelope`.
