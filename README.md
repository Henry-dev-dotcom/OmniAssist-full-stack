# OmniAssist

Local-first planner and research workflow app. Specs: `docs/`. Build status: `docs/PHASES.md`.

The client is one Flutter codebase. It ships first as a web app (PWA) that installs to
Android and iOS home screens; native Android/iOS builds come from the same code later.

## Setup

Needs Flutter (stable), Python 3.13+ with [uv](https://docs.astral.sh/uv/), and PostgreSQL 13+.

API:
```
cd apps/api
uv sync
uv run alembic upgrade head        # uses OMNI_DATABASE_URL, see infra/env/.env.example
uv run uvicorn src.main:app --port 8000
```

Client:
```
cd apps/client
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift code; rerun after table changes
```

## Checks
```
cd apps/api && uv run pytest && uv run ruff check src tests && uv run mypy
cd apps/client && flutter analyze && flutter test
```
API integration tests need `OMNI_TEST_DATABASE_URL` (a Postgres user that can create databases);
without it they skip.

## Web app (PWA)
```
cd apps/client
flutter build web --release --dart-define=API_BASE_URL=https://your-api.example.com/api/v1
```
Serve `build/web/` from any static host. Add that site's origin to the API's
`OMNI_CORS_ORIGINS`. Local try-out: `python -m http.server 8080 --directory build/web`.

`web/sqlite3.wasm` (sqlite3 3.7.1) and `web/drift_worker.js` (drift 2.35.2) run the offline
database in the browser. Update both when those package versions change.

Install on a phone: open the site over **HTTPS**, then
- Android (Chrome): menu → *Install app* / *Add to Home screen*.
- iOS (Safari): Share → *Add to Home Screen*.
