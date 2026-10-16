# Managed PostgreSQL setup (Neon)

This repository does not create a Neon project or database. Choose the owner account, region,
plan, backup retention and recovery objectives before provisioning production data.

1. Create or select a Neon project in the approved region and create the production database.
2. Copy the **pooled TLS connection string** from the Neon console. Keep it private; do not put it
   in Git, a Vercel variable, a ticket, or chat.
3. Enter it as Render's `OMNI_DATABASE_URL` through the Render service's protected environment
   settings. The API converts the standard `postgresql://` URL to its async PostgreSQL driver.
4. Render's start command runs `uv run --no-sync alembic upgrade head` before Uvicorn. Verify the
   migration version and `/api/v1/health/ready` after the first deployment.
5. Confirm provider backup/PITR retention and perform a restore rehearsal before production
   sign-off. The repo's general backup/restore procedure is in [`../docs/operations.md`](../docs/operations.md).

Do not run production migrations manually from a workstation using a copied credential. For
connection or migration failures, inspect Render logs and Neon connection limits without exposing
connection strings.
