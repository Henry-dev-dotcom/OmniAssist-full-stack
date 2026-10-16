# OmniAssist

Local-first planner and research workflow app for researchers: tasks, time blocks, a daily
briefing, thesis and grant milestones, systematic reviews, an analysis ledger and an
experiment log, all usable offline and synced across devices.

The client is one Flutter codebase. It ships first as an installable web app (PWA) that runs
on desktop browsers and installs to Android and iOS home screens; native builds come from the
same code. The API is FastAPI on PostgreSQL.

- **Using it yourself on PC and phone: `docs/personal-setup.md`** (one command to start; Tailscale for the phone)
- Specification: `docs/SPECIFICATION.md` · Build status: `docs/PHASES.md`
- Decisions: `docs/decisions/` · Deploying: `docs/deployment.md` · Backups and baselines: `docs/operations.md`

## Run it locally

Needs Flutter (stable), Python 3.13+ with [uv](https://docs.astral.sh/uv/), and PostgreSQL 13+.

Database (once, as a PostgreSQL superuser): `psql -U postgres -f infra/create_dev_db.sql`

API:
```
cd apps/api
cp ../../infra/env/.env.example .env    # adjust the database URL/port if needed
uv sync
uv run alembic upgrade head
uv run uvicorn src.main:app --port 8000
```

Web app:
```
cd apps/client
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift code; rerun after table changes
flutter build web --release --no-web-resources-cdn
python -m http.server 8080 --directory build/web
```
Open http://localhost:8080, choose **Create an account**, and you are in.

## Checks
```
cd apps/api && uv run ruff check src tests && uv run mypy && uv run pytest
cd apps/client && flutter analyze && flutter test
```
API integration tests need `OMNI_TEST_DATABASE_URL` (a Postgres user that can create
databases, e.g. `postgresql://omni:omni@localhost:5432/postgres`); without it they skip.
CI (`.github/workflows/ci.yml`) runs all of this on every push.

## How it fits together

- Every change is written to the device's database first, with an outbox entry, in one
  transaction. A sync engine pushes the outbox and pulls the server's change feed.
- `mutation_id` makes every upload idempotent; edits to different fields merge, the same field
  edited on two devices becomes a conflict the user resolves in the Sync Center.
- The web app stores its database in the browser (`web/sqlite3.wasm`, `web/drift_worker.js`
  for sqlite3 3.7.1 and drift 2.35.2; update both with those packages) and caches itself with
  `web/sw.js`, so it opens offline.
- Sign-in is built in (email and password, decision 0002); a hosted OpenID Connect provider
  can replace it by configuration (decision 0001).
- Reminders reach phones and desktops through Web Push once VAPID keys are set
  (decision 0006); the in-app notification center works without them.

## Install on a phone
Serve the web build over **HTTPS** (see `docs/deployment.md`), then
- Android (Chrome): menu → *Install app*.
- iOS (Safari): Share → *Add to Home Screen*.
