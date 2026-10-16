# Active work

## Completed

- [x] **Task 1 — Web-first repository migration.** Acceptance: `pnpm lint`, `pnpm typecheck`, and `pnpm build` pass; Flutter is outside the active build; `make check` runs web/API checks.
- [x] **Task 2 — API configuration and deployment baseline.** Acceptance: API starts with `uv run uvicorn`; health routes return 200 when healthy; production settings reject development credentials; the Render Blueprint validates.
- [x] **Task 3 — PWA shell and design tokens.** Added OmniAssist brand tokens and responsive shell, manifest and icons, metadata, a service worker, offline fallback, and reduced-motion behavior. Production preview and 320 px/1280 px layouts verified; PWA privacy regression tests pass.
- [x] **Task 4 — Contracts, shared types, and CI.** Added `@omniassist/contracts` envelopes, error codes and domain types; a typed API client that preserves request IDs; separate web/API workflows; and parity/runtime tests.

## In progress
- [ ] Tasks 17–20 — Research frontend.

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
- [ ] Tasks 21–23 — Quality and PWA.
- [ ] Task 24 — Production release.

See [`docs/WEB_PWA_TASKS.md`](docs/WEB_PWA_TASKS.md) and the linked source PDF for the complete ordered plan.
