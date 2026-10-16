# Known limitations and release gates

This list reflects the repository state on 2026-10-16. Re-check it before each release.

- **No production stack is provisioned by this repository.** Provider accounts are not the same as
  a Vercel project, Render service or production database; the release runbook requires explicit
  target URLs and owner choices.
- **Render Free is not a production option for this stack.** Render says Free instances are for
  testing and not production; Free web services spin down after 15 minutes idle. Free Postgres is
  limited to 1 GB, expires after 30 days (then has a 14-day upgrade grace period before deletion),
  and has no Render-provided backups or managed pooling. A zero-cost-only deployment needs a
  different owner-approved, production-suitable backend/database or must be treated as a demo.
  See [Render Free limits](https://render.com/docs/free) and
  [Render Postgres backups](https://render.com/docs/postgresql-backups).
- **API-backed records are online-first.** The service worker caches only public static assets and
  the generic offline page; it does not queue writes for later synchronization.
- **Experiment drafts are browser-local and unencrypted.** Each is capped at 256 KiB and expires
  after 30 days. Do not use a shared device for sensitive drafts.
- **Registration policy must be decided before public exposure.** The Render Blueprint defaults
  `OMNI_ALLOW_REGISTRATION` to `true`; CORS does not block direct API clients. Do not leave public
  registration open unless that is the intended product policy.
- **Push delivery is optional and not enabled by default.** VAPID credentials and end-to-end delivery
  checks are required before promising web-push reminders.
- **Physical install and assistive-technology checks remain outstanding.** Automated Chromium/axe
  and 320 px layout checks passed, but real Android Chrome, iOS Safari, keyboard-only feature flows
  and a screen-reader session remain release-time validation.
- **Production SLOs and backup objectives are not set here.** The recorded API timings are local
  smoke measurements, not production p95s. Decide alerting, backup retention, recovery point/time
  objectives, and run a restore rehearsal before release sign-off.
