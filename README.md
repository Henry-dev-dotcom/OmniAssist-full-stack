# OmniAssist

Local-first planner and research workflow app for postgraduate researchers. The active client
is a Next.js 16 App Router application; the FastAPI backend remains a separate service. The
previous Flutter client is preserved in `apps/client-flutter-archive/` while the web/PWA
implementation is built from the ordered work plan.

## Repository structure

- `apps/web/` — active TypeScript, Next.js 16 and Tailwind CSS 4 application.
- `apps/api/` — FastAPI service, PostgreSQL persistence and migrations.
- `apps/client-flutter-archive/` — archived Flutter implementation; not part of the active build.
- `packages/contracts/` — shared TypeScript API envelopes, stable errors and domain models.
- `docs/` — product specification, operations, deployment and historical implementation notes.
- `TODO.md` — current milestone and immediate next task.
- Web/PWA roadmap and progress: [`docs/WEB_PWA_TASKS.md`](docs/WEB_PWA_TASKS.md); original task PDF: [`docs/OmniAssist-Web-PWA-Tasks.pdf`](docs/OmniAssist-Web-PWA-Tasks.pdf).

## Requirements

- Node.js 22 and pnpm 11.
- Python 3.13+ and [uv](https://docs.astral.sh/uv/) for the API.
- PostgreSQL 13+ for API integration tests and local migrations.

## Run the web app

From the repository root:

```sh
pnpm install
pnpm --filter @omniassist/web dev
```

## Run the API

Create a development database once (as a PostgreSQL superuser):

```sh
psql -U postgres -f infra/create_dev_db.sql
```

Then start the API:

```sh
cd apps/api
cp ../../infra/env/.env.example .env
uv sync
uv run alembic upgrade head
uv run uvicorn src.main:app --reload --port 8000
```

## Checks

From the repository root:

```sh
pnpm lint
pnpm typecheck
pnpm build
make check
```

`make check` runs web lint, typecheck, API client/PWA regression tests and production build,
followed by API lint, formatting, type checking and tests. API integration tests use
`OMNI_TEST_DATABASE_URL`; they skip when it is unset. The matching GitHub workflows are
`.github/workflows/web.yml` and `.github/workflows/api.yml`.

The web shell includes the installable PWA manifest and an offline fallback. Its service worker
only caches public static assets; it bypasses API, authorization-bearing, and all navigation
responses so user-specific data is not stored by this cache. `make check` includes the PWA
privacy and manifest regression tests.

## Product and operational docs

- Product specification: `docs/SPECIFICATION.md`
- Historical Flutter implementation status: `docs/PHASES.md`
- Current API deployment baseline: [`docs/api-deployment.md`](docs/api-deployment.md)
- Historical deployment guide and operations notes: `docs/deployment.md`, `docs/operations.md`
- Architecture decisions: `docs/decisions/`
