# OmniAssist build phases

Source of task detail: `OmniAssist — Tasks.md` (42 tasks, 8 phases). Status as of 2026-10-16.

Status key: **Done** = built, and its server and client parts pass their tests.
**Done, with limits** = the acceptance criteria are met, with the stated gap.

Checks: 163 API tests pass against PostgreSQL (ruff and mypy clean), including the two MVP
journey tests. 108 client tests pass (`flutter analyze` clean). The web app was checked in a
browser: sign-up, sign-in, capture, and opening offline with both servers stopped.

## Phase 1: Repository and project foundation (Tasks 1-7)

| Task | Name | Status |
| --- | --- | --- |
| 1 | Monorepo scaffolding | Done |
| 2 | Shared contracts and error vocabulary | Done |
| 3 | Configuration and logging foundation | Done |
| 4 | Domain primitives and IDs | Done |
| 5 | Client navigation and design-token shell | Done |
| 6 | Backend database engine and migrations | Done |
| 7 | Client Drift database and migrations | Done (schema v2: generic records table) |

## Phase 2: Authentication and workspace foundation (Tasks 8-10)

| Task | Name | Status |
| --- | --- | --- |
| 8 | Authentication provider adapter | Done: built-in email/password (decision 0002); OIDC by configuration |
| 9 | User profile and workspace ownership | Done: onboarding/profile screen (time zone, work hours, reminders) |
| 10 | Project CRUD and local projection | Done: list, overview page, edit, archive, delete (empty projects only) |

## Phase 3: Local-first sync foundation (Tasks 11-16)

| Task | Name | Status |
| --- | --- | --- |
| 11 | Server change feed and entity versioning | Done |
| 12 | Client outbox and local mutation commands | Done |
| 13 | Push/pull API and idempotency | Done (concurrent pushes of one mutation are safe) |
| 14 | Client sync coordinator and retry policy | Done |
| 15 | Conflict records and resolution policies | Done: per-field resolver, "keep both" for text |
| 16 | Sync Center and status UI | Done: banner on every screen, refused uploads, conflicts |

## Phase 4: Planning MVP (Tasks 17-24)

| Task | Name | Status |
| --- | --- | --- |
| 17 | Task domain and repository | Done |
| 18 | Quick capture and Inbox | Done |
| 19 | Task detail, subtasks, tags, and recurrence | Done, with limits: no tag or subtask editor yet |
| 20 | Time blocks and overlap warnings | Done |
| 21 | Calendar and agenda views | Done, with limits: no drag-and-drop on the calendar (button moves) |
| 22 | Reminder domain and notification adapters | Done, with limits: in-app center only; no OS push plugin |
| 23 | Daily briefing | Done |
| 24 | Planning MVP integration checkpoint | Done (`test_mvp_journeys.py::test_planning_journey`) |

## Phase 5: Academic progress MVP (Tasks 25-27)

| Task | Name | Status |
| --- | --- | --- |
| 25 | Milestone domain and dependencies | Done: cycle checks, completion time, task links |
| 26 | Milestone dashboard and progress calculation | Done: manual vs weighted (decision 0003) |
| 27 | Activity history and audit records | Done: activity for every accepted change |

## Phase 6: Research modules (Tasks 28-33)

| Task | Name | Status |
| --- | --- | --- |
| 28 | Review schema and configurable stages | Done |
| 29 | Review board and item detail | Done: columns with drag on desktop, grouped list on mobile |
| 30 | CSV review import/export | Done: preview, mapping, row errors, one transaction |
| 31 | Analysis ledger | Done: transitions, next action creates a task |
| 32 | Experiment log and templates | Done: qPCR and primer design, autosave, finalize, revisions |
| 33 | Academic MVP integration checkpoint | Done (`test_mvp_journeys.py::test_academic_journey`) |

## Phase 7: Search, export, and notifications polish (Tasks 34-36)

| Task | Name | Status |
| --- | --- | --- |
| 34 | Local-first search and filters | Done: offline, 5,000 tasks under 500 ms; server search too |
| 35 | JSON/CSV export and account deletion | Done (decision 0004) |
| 36 | Notification center and daily briefing polish | Done, with limits: no OS push delivery |

## Phase 8: Security, accessibility, and release quality (Tasks 37-42)

| Task | Name | Status |
| --- | --- | --- |
| 37 | Authorization hardening and security review | Done: cross-user checks on every route, rate limits, security headers |
| 38 | Accessibility and responsive QA | Done, with limits: keyboard shortcuts, headings, 200% text; no screen-reader session on a device |
| 39 | Performance and sync-load testing | Done: baseline in `docs/operations.md` |
| 40 | Backup, restore, and migration rehearsal | Done: `infra/scripts/backup_restore.py`, rehearsal passed |
| 41 | Cross-platform packaging and release builds | Done for web (PWA, Docker, HTTPS compose); native builds documented, not built here |
| 42 | MVP release candidate and documentation | Done: README, deployment, operations, decisions 0001-0004 |

## Known gaps

- No OS push notifications: reminders show in the in-app notification center (needs a plugin per platform).
- No password reset or email verification for built-in sign-in (decision 0002).
- Tasks have no tag or subtask editor; recurring tasks do not create the next occurrence.
- Calendar rescheduling uses buttons, not drag-and-drop.
- Native Android/iOS/Windows/Linux builds were not produced on this machine (no SDKs).
- Open product questions in Spec 12.4 still to settle: hosting region, backup retention,
  local database encryption, attachments, email reminders.
