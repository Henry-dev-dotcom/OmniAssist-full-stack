# Production deployment and release checklist

This is the current hosted deployment path for OmniAssist:

```text
Next.js web app → Vercel
FastAPI API     → Render
PostgreSQL      → Neon or another explicitly selected managed PostgreSQL service
```

**A production release is not complete until the exact service URLs, authentication policy,
backup/restore plan, and rollback path are verified.** Do not commit provider credentials or
paste database URLs, client secrets, or signing keys into chat.

## 1. Confirm the release target

Before provisioning or changing provider settings, record:

- The Vercel workspace/project and chosen production domain.
- The Render workspace/service and plan. Confirm any cost before creating or upgrading resources.
- The managed PostgreSQL provider/project, region, backup retention, and recovery-point objective.
- The authentication mode (`local` or a specific OIDC provider), owner-account bootstrap method,
  and whether registration is private or public.
- The exact allowed browser origins and the release commit SHA.

The checked-in Render Blueprint defines `omniassist-api`, but does not create a database. It
requires the operator to provide `OMNI_DATABASE_URL` and `OMNI_CORS_ORIGINS`.

## 2. Configure PostgreSQL and Render

1. Select an existing production PostgreSQL database or provision one under the approved provider
   and plan. For Neon, use the pooled TLS connection string.
2. In Render, create or select the service from the root [`render.yaml`](../render.yaml).
3. Set `OMNI_DATABASE_URL` to the production connection string and `OMNI_CORS_ORIGINS` to a
   temporary deny-by-default origin until the final Vercel origin is known. Keep the generated
   `OMNI_AUTH_LOCAL_SECRET`; never substitute the development secret.
4. Confirm `OMNI_ENV=production`, the intended auth provider and registration policy. The Blueprint
   currently enables local registration, so do not expose that default publicly without a controlled
   owner bootstrap plan.
5. Deploy the API. The Render start command runs `alembic upgrade head` before starting Uvicorn.
6. Verify `GET /api/v1/health/live` and `GET /api/v1/health/ready` return HTTP 200.

See [`api-deployment.md`](api-deployment.md) and [`../infra/neon.md`](../infra/neon.md) for
provider details.

## 3. Configure and deploy the web app

1. In Vercel, import `Henry-dev-dotcom/OmniAssist-full-stack` into the approved workspace and use
   the repository root. [`vercel.json`](../vercel.json) configures the Next.js build.
2. Set the **Production** environment variable `NEXT_PUBLIC_API_URL` to the Render API base URL,
   including `/api/v1` (for example, `https://<service>.onrender.com/api/v1`). This is the actual
   variable read by the web client; do not use the old Flutter-era `API_BASE_URL` name.
3. Deploy the approved release SHA. Verify the build points at the production API, not localhost.

## 4. Lock CORS and verify authentication

1. Set Render's `OMNI_CORS_ORIGINS` to the exact HTTPS Vercel production origin, without a trailing
   slash; include the custom domain only if it is also intentionally supported.
2. Restart/redeploy the API and confirm browser preflight and authenticated requests succeed from
   the production origin.
3. Verify the selected auth flow, owner-account bootstrap, sign-in, sign-out and token refresh. If
   using OIDC, configure and test the selected provider's exact issuer, audience, client, and
   callback settings before opening the site.
4. Disable public account registration unless multi-user public registration is the explicit
   product decision. CORS is not an access-control mechanism for direct API clients.

## 5. Release verification

- Web page loads over HTTPS and points to the configured API.
- API liveness and database readiness checks pass; migrations are at Alembic head.
- Sign-in, account policy, create-task, project view and research read/write flows pass against the
  production API.
- Export downloads, notifications and settings behave as configured.
- No API/private or credentialed response is cached by the service worker; the generic offline
  page works without a connection.
- Complete the real-device Android Chrome and iOS Safari install and create-task smoke checks.
- Verify provider alerts, database backup retention, and at least one restore rehearsal.

Automated release checks run through [Web CI](../.github/workflows/web.yml) and
[API CI](../.github/workflows/api.yml). Local performance timings in [`operations.md`](operations.md)
are smoke baselines, not production SLOs.

## 6. Rollback

- Keep the release commit SHA, Vercel deployment, and Render deploy ID in the release record.
- On a web/API regression, roll back to the last known-good deployment from the provider dashboard
  or revert the release commit and redeploy it.
- Do **not** blindly downgrade PostgreSQL migrations during an application rollback. Take and
  verify a database backup first; follow the tested restore procedure in [`operations.md`](operations.md)
  if a schema/data rollback is required.
- Record the incident, migration state, recovery point and the follow-up fix before redeploying.

## Current readiness limits

No production Vercel project, Render service, or database target is assumed by this repository.
A selected domain, PostgreSQL URL, auth/registration decision, backup policy and rollback rehearsal
must be confirmed before declaring the release complete. Render's official documentation says its
Free instances are not for production; Free web services sleep after 15 idle minutes, and Free
Postgres is limited to 1 GB, expires 30 days after creation, and has no provider backups or managed
connection pooling. With a zero-cost-only limit, do not deploy this Render stack as production; use a
different owner-approved production-suitable backend/database or treat it as a non-production demo.
Do not upgrade or purchase a paid plan without a new explicit approval. See [Render Free limits](https://render.com/docs/free), [Render Postgres backups](https://render.com/docs/postgresql-backups), and [`known-limitations.md`](known-limitations.md).
