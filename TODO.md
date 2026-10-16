# Active work

## Completed

- [x] **Task 1 — Web-first repository migration.** Acceptance: `pnpm lint`, `pnpm typecheck`, and `pnpm build` pass; Flutter is outside the active build; `make check` runs web/API checks.
- [x] **Task 2 — API configuration and deployment baseline.** Acceptance: API starts with `uv run uvicorn`; health routes return 200 when healthy; production settings reject development credentials; the Render Blueprint validates.
- [x] **Task 3 — PWA shell and design tokens.** Added OmniAssist brand tokens and responsive shell, manifest and icons, metadata, a service worker, offline fallback, and reduced-motion behavior. Production preview and 320 px/1280 px layouts verified; PWA privacy regression tests pass.
- [x] **Task 4 — Contracts, shared types, and CI.** Added `@omniassist/contracts` envelopes, error codes and domain types; a typed API client that preserves request IDs; separate web/API workflows; and parity/runtime tests.

## Completed in Phase 4
- [x] **Tasks 17–20 — Research frontend.** Added project-scoped review boards with editable stages, stage history and bounded CSV preview/import/export; an editable R/Python analysis ledger with status transitions and next-action tasks; experiment templates, local draft recovery, finalization and revision access; and search, notification actions/preferences, background export controls, profile settings and confirmed account deletion. API-backed records remain online-first; unsaved experiment form drafts persist locally.

## Completed in Phase 5
- [x] **Task 21 — Browser persistence and PWA verification.** Experiment drafts are capped at 256 KiB, expire after 30 days, recover after reload, and are never added to service-worker caches; platform install guidance and production browser tests added.
- [x] **Task 22 — Accessibility and responsive QA.** Chromium + axe WCAG 2.1 AA checks pass for landing and research screens; 320 px overflow and keyboard skip-link tests pass. Physical screen-reader/device testing remains a pre-release manual check.
- [x] **Task 23 — Security, performance, and integration QA.** API lint, formatting, typing, and all 187 PostgreSQL-backed API tests pass; web route guard, no-private-cache, offline-shell and browser integration tests pass. Local 100-mutation API timings are recorded in `docs/operations.md`.

## Completed in Phase 2

- [x] **Task 5 — Neon schema and migrations.** PostgreSQL migrations cover users, workspaces, projects, tasks, time blocks, milestones, reviews, analyses, experiments, notifications, activities, exports, sync state, and preferences. Upgrade, downgrade, and constraint coverage are exercised in the migration suite; typed SQLAlchemy mappings now cover the persisted Phase 2 entities.
- [x] **Task 6 — Auth claims and workspace authorization.** JWT/OIDC issuer, audience, signature, and expiry verification; provider-subject mapping; personal workspace ownership; and safe cross-workspace authorization responses are implemented.
- [x] **Task 7 — Project and task API.** CRUD, validation, statuses, tags, subtasks, due dates, recurrence, completion timestamps, tombstones, workspace-scoped links, and stable paginated list responses are implemented.
- [x] **Task 8 — Calendar, reminders, and milestones API.** Time blocks validate dates, return overlap warnings without blocking saves, support task/project links, and expose reminder/notification state with quiet-hours rules; milestone dependency and progress rules are enforced through the workspace-scoped domain repositories and sync API.
- [x] **Task 9 — Research modules API.** Review stages/items and history, bounded research records, analysis transitions, experiment finalization/revisions, and safe content handling are implemented through the workspace-scoped domain repositories and sync API.
- [x] **Task 10 — Search and export API.** Authorized workspace search, JSON/CSV background exports with expiring signed downloads, rate limiting, and explicit account deletion are implemented.
- [x] **Task 11 — Authenticated frontend entry.** Added sign-in/sign-up forms wired to the configured API auth provider, browser session persistence, bearer-token API requests, protected app/onboarding routes, redirect behavior, and sign-out.
- [x] **Task 12 — Web application shell.** Added a responsive authenticated shell with desktop sidebar, mobile bottom navigation, workspace identity, active-route states, keyboard-visible focus, reduced-motion support, and accessible labels.
- [x] **Task 13 — Onboarding and workspace UI.** Added first-run workspace creation and empty/loading/error states with API-backed workspace setup.
- [x] **Task 14 — Projects and tasks UI.** Added project/task list views, creation flows, progress indicators, priorities/statuses, and Today next-action summaries.
- [x] **Task 15 — Today and calendar UI.** Added Today dashboard metrics, open-task focus, calendar/time-block view, and overlap-aware planning copy tied to the Phase 2 API.
- [x] **Task 16 — Milestone UI.** Added milestone progress view with project checkpoint empty states and responsive progress rows.
## In progress
- [ ] **Task 24 — Production release.** Verify deployment configuration and secrets, deploy the web/API/database stack, run HTTPS health and authenticated smoke checks, then complete Android/iOS installation checks before declaring release.

See [`docs/WEB_PWA_TASKS.md`](docs/WEB_PWA_TASKS.md) and the linked source PDF for the complete ordered plan.
