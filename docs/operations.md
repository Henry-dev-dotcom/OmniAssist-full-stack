# Operations

## Backup and restore (Task 40, Spec 10.5)

`infra/scripts/backup_restore.py` wraps `pg_dump` and `pg_restore` (custom format):

```
python infra/scripts/backup_restore.py backup   --url postgresql://omni:PASS@HOST:5432/omniassist --out omni-YYYYMMDD.dump
python infra/scripts/backup_restore.py restore  --url postgresql://omni:PASS@HOST:5432/omniassist --file omni-YYYYMMDD.dump
python infra/scripts/backup_restore.py rehearse --url postgresql://omni:PASS@HOST:5432/omniassist
```

Set `PG_BIN` to the PostgreSQL `bin` folder if the tools are not on PATH. With the Docker
deployment, run them inside the database container:
`docker compose ... exec postgres pg_dump -U omni -Fc omniassist > omni.dump`.

**Rehearsal** dumps the database, restores it into a scratch database, compares every table's
row count and the migration version, prints a table, and drops the scratch database. It exits
non-zero on any mismatch. Run it after every migration and at least quarterly.

Last rehearsal: 2026-10-16 on the development database: 29 tables matched, migration 0005,
`REHEARSAL PASSED`.

Recommended policy (not yet decided, Spec 12.4): daily logical backup kept 30 days, plus the
hosting provider's point-in-time recovery where available. Recovery point and time targets
must be set before a public beta.

## Migrations

`uv run alembic upgrade head` (the API container does this on start). Every migration has a
downgrade, and `tests/integration/test_migrations.py` checks up, down and up again.

## Performance baseline (Task 39)

Measured 2026-10-16 on a Windows laptop, PostgreSQL 13, one API process
(`tests/integration/test_performance.py`, run with `-s`):

| Operation | Time |
| --- | --- |
| Push a full batch of 100 mutations | 1.00 s |
| Replay the same 100 (idempotent, no work) | 0.15 s |
| Pull 200 changes (100 records + 100 activity events) | 0.10 s |
| Server search across all entity types | 0.11 s |
| Local search over 5,000 tasks on the device | under 500 ms (Spec 11.1, asserted in client tests) |

Re-measured 2026-10-16 in the Manus Ubuntu sandbox against local PostgreSQL 16 and the
Python 3.14 test environment (`uv run pytest -q -s tests/integration/test_performance.py`):

| Operation | Time |
| --- | --- |
| Push a full batch of 100 mutations | 0.73 s |
| Replay the same 100 (idempotent) | 0.06 s |
| Pull 200 changes | 0.03 s |
| Server search | 26 ms |

These are a local smoke baseline, not production p95/SLO measurements; load, network and
database topology differ from deployment.

The API p95 target is still open (Spec 11.1); use these as the starting point.

## Monitoring

Every response carries `X-Request-ID`; logs are JSON with that id and never contain task,
note, experiment or review content (`src/infrastructure/observability/logging.py`).
`GET /api/v1/health/live` and `/health/ready` are for load balancers.
