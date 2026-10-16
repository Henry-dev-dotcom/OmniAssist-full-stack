# API deployment baseline

This is the current backend runbook for the web-first migration. The Next.js application and
FastAPI API are separate services. The Next.js app is still a foundation scaffold; the complete
production web release, auth integration, monitoring, backups, and rollback procedure are
scheduled for Task 24 in [`WEB_PWA_TASKS.md`](WEB_PWA_TASKS.md).

## Render service

The canonical Render Blueprint is [`../render.yaml`](../render.yaml) at the repository root so
Render can discover it when creating a Blueprint. The task-list PDF mentions `infra/render.yaml`,
but the repository already had a root-level manifest; do not maintain a second copy that could
become inconsistent.

The Blueprint creates `omniassist-api` with `rootDir: apps/api`, installs the locked API
requirements, applies Alembic migrations, starts Uvicorn on Render's `$PORT`, and configures
`/api/v1/health/live` as its health check. The API container uses Python 3.13 and the checked-in
`uv.lock`.

## Production environment

Set these values in Render's service environment. Never commit production credentials or place
them in the development `.env.example`.

| Variable | Production rule |
| --- | --- |
| `OMNI_ENV` | Must be `production` to activate production validation. |
| `OMNI_DATABASE_URL` | Required; use the production PostgreSQL connection string, not the development default. |
| `OMNI_AUTH_PROVIDER` | `local` or `oidc`. The current Blueprint uses `local`. |
| `OMNI_AUTH_LOCAL_SECRET` | For `local`, use at least 32 random characters; the Blueprint generates a value. The development default and short secrets are rejected. |
| `OMNI_CORS_ORIGINS` | Required JSON array of exact allowed web origins, for example `["https://app.example.com"]`; do not use `*` with bearer-token APIs. |
| `OMNI_AUTH_ISSUER` | Required when `OMNI_AUTH_PROVIDER=oidc`. |
| `OMNI_AUTH_AUDIENCE` | Required when `OMNI_AUTH_PROVIDER=oidc`. |
| `OMNI_AUTH_CLIENT_ID` | Required when `OMNI_AUTH_PROVIDER=oidc`. |
| `OMNI_AUTH_CLIENT_SECRET` | Set only when required by the configured OIDC provider. |
| `OMNI_ALLOW_REGISTRATION` | Set to `false` after initial account setup if public registration is not intended. |
| `OMNI_VAPID_PRIVATE_KEY`, `OMNI_VAPID_PUBLIC_KEY`, `OMNI_VAPID_SUBJECT` | Optional; configure together when enabling web-push delivery. |

Do not set `OMNI_WEB_DIR`: the API no longer serves the archived Flutter static build. The
Next.js frontend is served separately and its origin must be included in `OMNI_CORS_ORIGINS`.

## Health and request behavior

- `GET /api/v1/health/live` returns HTTP 200 while the API process is alive.
- `GET /api/v1/health/ready` returns HTTP 200 only when the database responds, and HTTP 503 when
  it does not.
- Responses carry an `X-Request-ID`. Structured API errors include the same ID and use safe,
  stable error envelopes; unhandled exceptions are logged server-side without exposing details to
  callers.
- CORS is restricted to the configured `OMNI_CORS_ORIGINS` list. The local example allows
  `http://localhost:3000` for the Next.js development server.

## Local API run

```sh
cd apps/api
cp ../../infra/env/.env.example .env
uv sync --frozen
uv run alembic upgrade head
uv run uvicorn src.main:app --host 127.0.0.1 --port 8000
```

To run the API tests, set `OMNI_TEST_DATABASE_URL` to a PostgreSQL database that permits the test
suite to create/drop disposable databases. Without it, database integration tests are skipped.
