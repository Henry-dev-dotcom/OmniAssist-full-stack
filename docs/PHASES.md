# OmniAssist build phases

Source of task detail: `OmniAssist — Tasks.md` (42 tasks, 8 phases). Status as of 2026-10-15.

Status key:
- Done: written, and the server part passes its tests.
- Unrun: written, but the Flutter code has never been compiled or tested. Run `flutter pub get`, `make gen`, `flutter analyze`, `flutter test` and fix what they report.
- Partial: some acceptance criteria are still open.
- To do: not started.

Server checks: 115 tests pass against PostgreSQL 16. ruff and mypy are clean.

Client checks (2026-10-15): first compile. `flutter analyze` is clean and 78 tests pass. The web build
(PWA) runs in the browser with the offline database in IndexedDB. Fixes it needed: package versions
that never resolved, Riverpod 3 `StateProvider` import, Drift dates losing UTC (now stored as text,
see `apps/client/build.yaml`), a Calendar crash when signed out, and pulled server updates being
blocked by a task's own unsent create.

## Phase 1: Repository and project foundation (Tasks 1-7)

| Task | Name | Status |
| --- | --- | --- |
| 1 | Monorepo scaffolding | Done |
| 2 | Shared contracts and error vocabulary | Done |
| 3 | Configuration and logging foundation | Done |
| 4 | Domain primitives and IDs | Done |
| 5 | Client navigation and design-token shell | Done |
| 6 | Backend database engine and migrations | Done |
| 7 | Client Drift database and migrations | Done |

## Phase 2: Authentication and workspace foundation (Tasks 8-10)

| Task | Name | Status |
| --- | --- | --- |
| 8 | Authentication provider adapter | Partial: generic OIDC adapter works; no provider chosen yet |
| 9 | User profile and workspace ownership | Partial: API done; no profile or workspace screens |
| 10 | Project CRUD and local projection | Partial: list and create work; no edit or detail screen |

## Phase 3: Local-first sync foundation (Tasks 11-16)

| Task | Name | Status |
| --- | --- | --- |
| 11 | Server change feed and entity versioning | Done |
| 12 | Client outbox and local mutation commands | Done |
| 13 | Push/pull API and idempotency | Done |
| 14 | Client sync coordinator and retry policy | Done |
| 15 | Conflict records and resolution policies | Partial: server records conflicts; no resolution screen |
| 16 | Sync Center and status UI | Done |

## Phase 4: Planning MVP (Tasks 17-24)

| Task | Name | Status |
| --- | --- | --- |
| 17 | Task domain and repository | Done |
| 18 | Quick capture and Inbox | Done |
| 19 | Task detail, subtasks, tags, and recurrence | Partial: detail screen only |
| 20 | Time blocks and overlap warnings | Done |
| 21 | Calendar and agenda views | Done; no drag-and-drop yet (button moves instead) |
| 22 | Reminder domain and notification adapters | Done; no push provider chosen |
| 23 | Daily briefing | To do (next) |
| 24 | Planning MVP integration checkpoint | To do |

## Phase 5: Academic progress MVP (Tasks 25-27)

| Task | Name | Status |
| --- | --- | --- |
| 25 | Milestone domain and dependencies | To do |
| 26 | Milestone dashboard and progress calculation | To do |
| 27 | Activity history and audit records | To do |

## Phase 6: Research modules (Tasks 28-33)

| Task | Name | Status |
| --- | --- | --- |
| 28 | Review schema and configurable stages | To do |
| 29 | Review board and item detail | To do |
| 30 | CSV review import/export | To do |
| 31 | Analysis ledger | To do |
| 32 | Experiment log and templates | To do |
| 33 | Academic MVP integration checkpoint | To do |

## Phase 7: Search, export, and notifications polish (Tasks 34-36)

| Task | Name | Status |
| --- | --- | --- |
| 34 | Local-first search and filters | To do |
| 35 | JSON/CSV export and account deletion | To do |
| 36 | Notification center and daily briefing polish | To do |

## Phase 8: Security, accessibility, and release quality (Tasks 37-42)

| Task | Name | Status |
| --- | --- | --- |
| 37 | Authorization hardening and security review | To do |
| 38 | Accessibility and responsive QA | To do |
| 39 | Performance and sync-load testing | To do |
| 40 | Backup, restore, and migration rehearsal | To do |
| 41 | Cross-platform packaging and release builds | To do |
| 42 | MVP release candidate and documentation | To do |

## Known gaps

- Nobody can sign in until an auth provider is chosen (decision 0001), so the web app stops at the sign-in screen.
- API integration tests were not re-run on this machine: the local PostgreSQL 13 has no `omni` user yet.
- No auth provider is chosen.
- No conflict resolution screen.
- Two simultaneous pushes with the same `mutation_id` can still cause a 500 error.
- Tasks have no tags, subtasks, recurrence or milestone links.
- Signing out leaves local data on the device.
- Device reminders and server reminders do not sync with each other.
- Push delivery needs a platform plugin; today reminders appear in the in-app center only.
