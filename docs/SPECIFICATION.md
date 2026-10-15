# OmniAssist — Specification

> Plan today, advance your research: a local-first personal planner and research-workflow app for postgraduate researchers, on Android, iOS, Windows and Linux.

**Status:** Draft for approval. Reconstructed from `OmniAssist — Implementation Plan.md`, `OmniAssist — Tasks.md`, `OmniAssist — Single-Shot Implementation Prompt.md`, `OmniAssist — Branding Guide.md` and the architecture/UX document (`OmniAssist MVP — Technical Architecture…docx`). Section numbers match the `SPECIFICATION.md §…` references in those documents. Anything the source documents leave undecided is marked `[TBD: reason]`; nothing has been guessed.

---

## 1. Overview

### 1.1 What Is OmniAssist?

OmniAssist is a cross-platform, local-first planner for individual postgraduate researchers. It combines everyday planning (tasks, calendar, focus time, reminders, a daily briefing) with research-specific tools (thesis and grant milestones, systematic-review boards, an analysis ledger, and a timestamped experiment log) in one workspace.

Researchers capture work on a phone and do detailed planning and research on a desktop. Every core action works without a network connection. The client writes to a local database first, and a synchronization engine reconciles devices in the background, with conflicts surfaced instead of silently resolved.

### 1.2 Target Audience

Individual postgraduate researchers (MSc, PhD, postdoctoral) who manage a long-horizon deliverable (thesis, grant, protocol) alongside daily lab, analysis and writing work, and who use both a phone and a Windows or Linux desktop. The MVP serves one person per workspace (Owner role). Supervisors, collaborators and lab teams are not served in the MVP (see §12.2).

### 1.3 Key Differentiators

- **Planning tied to research outcomes:** a task, a time block and a milestone are linked, so Today shows how daily work moves a thesis or grant forward.
- **Offline for all core data:** tasks, projects, milestones, time blocks, review items, analysis records and experiment entries can be read and changed with no connection.
- **Safe multi-device sync:** idempotent mutations, an ordered change feed, tombstones, and a visible conflict workflow with base, local and server snapshots.
- **Research modules in the same app:** configurable systematic-review Kanban with CSV import/export, an analysis ledger for R/Python work, and experiment entries with drafts, revisions and explicit finalization.
- **Honest privacy posture:** TLS in transit, managed encryption at rest, secure token storage, redacted telemetry. The MVP does not claim end-to-end encryption or regulated lab-notebook status.

### 1.4 Competitive Landscape

`[TBD: no competitor analysis exists in the source documents. Add one before external positioning work.]`

---

## 2. Core Concepts

| Concept | Definition |
|---|---|
| Workspace | The private data and permission boundary. Contains projects, tasks and all other records. In the MVP each workspace has one Owner. |
| Project | A long-running research or personal effort (for example a thesis or grant). Contains milestones, tasks, reviews, analyses and experiments. |
| Task | A unit of work with a status, optional due time, estimate, tags, subtasks and recurrence. May link to one project and one milestone. |
| Inbox item | A quickly captured, uncategorized task or note awaiting processing. |
| Time block | A protected span of calendar time for focused work, optionally linked to a task or project. |
| Milestone | A long-term outcome inside a project (for example "Draft Chapter 2"). Can nest and can depend on other milestones. |
| Review | A systematic-review workflow with configurable stages. |
| Review item | A study or record moved through review stages, with a decision, notes and stage history. |
| Analysis record | A ledger entry describing a code or analysis run (language, repository, commit, environment, result). OmniAssist never executes the code. |
| Experiment entry | A timestamped record of an experiment, with draft and finalized states and immutable revisions. |
| Daily briefing | The Today view: top priorities, scheduled blocks, overdue items, routines and milestones. |
| Outbox | The local queue of mutations waiting to be uploaded. |
| Mutation | One create, update or delete of an entity, identified by a client-generated `mutation_id` (idempotency key). |
| Change feed | The server's ordered sequence of entity changes, read by clients using a cursor. |
| Cursor | The position in the change feed a device has applied. |
| Tombstone | A retained record of a deletion so other devices can apply it. |
| Sync state | Per-record transfer status (`synced`, `pending_create`, `pending_update`, `pending_delete`, `conflict`, `sync_error`). It is separate from the domain status of the record. |
| Conflict | Local and server changes that cannot be merged automatically. Kept as a record with base, local and server snapshots until the user resolves it. |
| Finalized entry | An experiment entry that is read-only and changes only through a new revision. |

---

## 3. MVP Scope and Success Criteria

### 3.1 MVP Scope

The MVP delivers two journeys on top of a shared sync foundation.

**Planning MVP** (Tasks 1–24): sign in, create a workspace and project, capture tasks offline, schedule time blocks, receive reminders, complete work, and see a daily briefing, with sync across devices.

**Academic MVP** (Tasks 25–36): connect thesis and grant milestones to tasks, run a systematic review with CSV import/export, keep an analysis ledger, record experiments, and search and export everything.

**Release quality** (Tasks 37–42): authorization hardening, accessibility, performance, backup and restore, cross-platform packaging, and documentation.

The academic journey must pass end to end: create a Thesis project, add a milestone and a linked task, create a review and import records, add an analysis record with a next action, create and finalize an experiment entry, edit offline, reconnect, and verify sync and conflict behavior.

### 3.2 Success Criteria

- A first-time user reaches a populated Today view in under five minutes.
- A returning user identifies the top three priorities in under 30 seconds.
- A task is created from mobile quick capture in under 10 seconds.
- A user reschedules a task without leaving the planner.
- A user links a task to a milestone from the milestone detail screen.
- A user imports a valid CSV after reviewing a preview.
- A user finds a failed analysis record through project navigation and search.
- A user resolves a conflict without losing either version.
- A user exports workspace data without support assistance.
- Every critical flow is completable with the keyboard on desktop.

---

## 4. Functional Requirements

All features read and write the local database first and work offline unless stated.

### 4.1 Accounts and Sessions

**User Story:** As a researcher, I want to create an account and stay signed in so that my data follows me across devices.

**Description:** Email and password sign-up and sign-in through a managed authentication provider, with provider-managed password reset. Sessions refresh automatically. Refresh tokens live in platform secure storage. A valid local session lets the app open offline.

**Acceptance Criteria:**
- [ ] A user can register, sign in, refresh a session, and sign out.
- [ ] A user with a valid local session opens the app and reads local data with no network.
- [ ] Sign-out with pending mutations explains what will happen and never uploads them to a different account.
- [ ] Password reset is handled by the provider and not by custom code.

**Edge Cases:**
- Expired refresh token while offline: the app stays usable locally and asks for sign-in when a sync is required.
- Revoked session: uploads pause, local data remains readable.

**Constraints:** `[TBD: managed auth provider not selected; Implementation Plan §1.3 defers the choice to bootstrap.]`

### 4.2 Workspaces, Profile and Projects

**User Story:** As a researcher, I want separate workspaces and projects so that thesis, grant and personal work stay organized.

**Description:** Each user owns one or more private workspaces. Profile holds display name, timezone, work hours and reminder preferences. Projects have a name, category, status (active, archived), description, dates, and a progress mode and value.

**Acceptance Criteria:**
- [ ] A user can create, rename, archive and delete workspaces and projects.
- [ ] Onboarding collects timezone, work hours and reminder preferences, and every optional step is skippable.
- [ ] Project lists filter by active and archived and support search.
- [ ] Every query and mutation is authorized against user and workspace.

**Edge Cases:**
- A user with no workspace sees an empty state with a one-click creation path.
- Deleting a project with linked records: `[TBD: cascade versus block behavior is not defined in the source documents.]`

### 4.3 Tasks, Quick Capture and Inbox

**User Story:** As a researcher, I want to capture and manage tasks in seconds so that nothing is lost between meetings and experiments.

**Description:** Tasks have a title, description, status, priority, due time, estimated minutes, tags, parent task (subtasks), optional project and milestone links, and an optional recurrence rule. Quick capture is available from every primary area and creates an Inbox item. Inbox items become project-linked tasks or are archived. Completing a task records a completion time. Completing a recurring task affects only the current occurrence by default.

**Acceptance Criteria:**
- [ ] Task create, read, update, delete and complete work offline and sync later.
- [ ] Quick capture saves locally with no network call and shows "Saved on this device".
- [ ] An empty title is rejected and the entered content is kept.
- [ ] Invalid status transitions are rejected with a stable error code.
- [ ] A task links only to a project and milestone in the same workspace.
- [ ] Invalid recurrence rules are rejected with field-level guidance.
- [ ] A completed task cannot receive new reminders unless reopened.

**Edge Cases:**
- Same task completed on two devices: one completion is recorded.
- Task deleted on one device while edited on another: deletion wins in the active list; a tombstone and activity record are kept (§4.12).

**Constraints:** Allowed task statuses and priority levels: `[TBD: value lists are not defined in the source documents.]`

### 4.4 Time Blocks and Calendar

**User Story:** As a researcher, I want to protect focus time and see my day, week and month so that I schedule realistic work.

**Description:** Time blocks have a title, category, start, end, status, and optional task and project links. Calendar views are Today, agenda, week and month. Unscheduled tasks stay visible in a tray. Desktop supports drag to reschedule; every drag action has a button or edit alternative. Mobile uses tap to edit.

**Acceptance Criteria:**
- [ ] A block with an end earlier than its start is rejected.
- [ ] An overlapping block shows a warning and can still be saved.
- [ ] Rescheduling offline updates the view immediately and queues sync.
- [ ] All four views show tasks and blocks; unscheduled tasks remain visible.
- [ ] Status transitions for blocks are validated.

### 4.5 Reminders and Notifications

**User Story:** As a researcher, I want timely, non-intrusive reminders so that deadlines do not slip.

**Description:** Preset and custom reminder offsets, calculated in the user's timezone, with multi-level urgency and quiet hours. Delivery history records sent, dismissed, snoozed, failed and acted-on states. An in-app notification center works when the operating system permission is denied. Notification content stays on the device and in the user's workspace, not in analytics.

**Acceptance Criteria:**
- [ ] Completing or rescheduling a task removes obsolete reminders.
- [ ] Quiet hours and urgency are respected.
- [ ] The notification center supports unread, dismissed, snoozed, failed and acted-on states.
- [ ] Denied OS permission shows an in-app route to the notification center.
- [ ] Channel preferences and quiet hours are editable.

**Edge Cases:**
- Mobile operating systems limit background execution: scheduling uses platform adapters, and missed delivery is recorded as failed, not hidden.
- Email fallback: `[TBD: push/desktop only versus email fallback; Architecture §15 leaves this open.]`

### 4.6 Daily Briefing (Today)

**User Story:** As a researcher, I want one screen that tells me what matters today so that I start work without planning overhead.

**Description:** Today shows top priorities, scheduled blocks, overdue items, routines, upcoming deadlines and milestone progress. Items can be completed, snoozed, rescheduled or opened. Sync status is visible but unobtrusive.

**Acceptance Criteria:**
- [ ] Today loads entirely from local data offline.
- [ ] The empty state offers creation actions.
- [ ] The view stays useful with no tasks, no milestones, or while offline.
- [ ] Offline text reads "Saved on this device" or "N changes waiting to sync".

### 4.7 Milestones, Progress and Activity History

**User Story:** As a researcher, I want to break a thesis or grant into milestones and see risk early so that I can correct course.

**Description:** Milestones have a title, description, status, due time, optional parent, dependencies, weight, completion time, and a progress value in manual or weighted mode. The dashboard shows a timeline, progress, upcoming, at-risk and blocked items. A task can be created from a milestone. Overdue milestones are flagged without changing status automatically. Activity events record changes to milestones, tasks, reviews, analyses and experiments in chronological order.

**Acceptance Criteria:**
- [ ] Cyclic parent or dependency relationships are rejected.
- [ ] Setting a milestone Complete records a completion time.
- [ ] Manual and weighted progress modes are visibly distinct.
- [ ] Progress is between 0 and 100.
- [ ] The timeline shows status and stage changes in chronological order.

**Edge Cases:**
- Complete versus an older status update on two devices: the newest accepted version wins unless the user reopens it.
- Two devices set different due dates: manual conflict.

**Constraints:** Milestone status values and the weighted progress formula: `[TBD: not defined in the source documents.]`

### 4.8 Systematic Review

**User Story:** As a researcher, I want a board for screening studies so that review decisions are consistent and traceable.

**Description:** A review has configurable stages. Default stages: Protocol, Screening, Full Text, Extraction, Synthesis. Users rename, reorder, add and archive stages; names are unique within a review. A review item has a title or citation, source identifier, decision, reviewer, tags, notes, external URL and current stage. Every move creates a stage-history event. Desktop shows columns with counts; mobile shows lists grouped by stage with a stage selector. CSV import maps columns after a preview; export includes stable IDs and current stages.

**Acceptance Criteria:**
- [ ] A new review gets the default stages.
- [ ] Moving an item works offline, creates an activity event, and preserves stage history.
- [ ] CSV import previews headers, maps required fields, and shows row-level errors before anything is written.
- [ ] A valid import is applied in one transaction or is fully recoverable.
- [ ] File size, row count, column count and cell length are limited.
- [ ] Export contains stable IDs, statuses and decision fields.

**Constraints:** CSV limits: `[TBD: numeric limits for file size, rows, columns and cell length are not defined.]`

### 4.9 Analysis Ledger

**User Story:** As a researcher, I want to track analysis runs so that I know what ran, what failed and what to do next.

**Description:** Each record holds project and milestone links, title, purpose, language (R or Python), repository URL, branch, commit, data-source reference, environment, status, last run, result, error and next action. A next action can create a linked task. The system never executes code from a record.

**Acceptance Criteria:**
- [ ] All ledger fields are editable and persisted.
- [ ] Status transitions are validated.
- [ ] A failed record is findable through project navigation and search.
- [ ] Different-field edits on two devices merge automatically.

**Constraints:** Analysis status values: `[TBD: not defined in the source documents.]`

### 4.10 Experiment Log

**User Story:** As a researcher, I want timestamped experiment records with a clear history so that results are traceable.

**Description:** Entries hold project, template, title, occurred time, objective, protocol, variables, materials, observations, deviations, result summary and next steps. Templates: qPCR and primer design. Drafts autosave locally. Finalization is an explicit action that makes the entry read-only; later changes create a new revision and preserve the previous one. The UI states that OmniAssist is not a validated regulated electronic lab notebook.

**Acceptance Criteria:**
- [ ] Templates provide starter fields.
- [ ] Autosave never finalizes an entry.
- [ ] A finalized entry is never silently overwritten; a new revision keeps the earlier body.
- [ ] Concurrent edits to the same body field produce a visible conflict.
- [ ] The not-regulated notice is shown.

### 4.11 Search, Export and Account Deletion

**User Story:** As a researcher, I want to find and take my data so that I stay in control of it.

**Description:** Local-first search covers tasks, projects, milestones, review items, analyses and notes, with filters by type, project, status, tag, priority and date. Server search enforces authorization. Export produces JSON and CSV through a background job with expiring download links. Account deletion requires explicit confirmation and revokes sessions.

**Acceptance Criteria:**
- [ ] Offline search returns local results.
- [ ] Local task search returns within 500 ms on a representative dataset.
- [ ] Export includes IDs, relationships, active and archived records, and sync-relevant metadata, and does not block the API request.
- [ ] Download links expire according to configuration.
- [ ] Deletion is confirmed, revokes sessions, and its behavior is documented and tested.

**Constraints:** Deletion window and backup purge timing: `[TBD: data retention policy not set.]`

### 4.12 Offline-First Synchronization

**User Story:** As a researcher, I want my changes to be safe and available on every device so that I never lose work.

**Description:** Each user action runs in one local transaction that updates the record, an activity event, sync metadata and an outbox mutation. A sync coordinator pushes batched mutations and pulls changes after a cursor. The server assigns monotonic change sequences and entity versions.

**Sync rules:**
- `mutation_id` is idempotent. A repeat returns the earlier result and creates no duplicate record or activity event. The same ID with a different request returns `IDEMPOTENCY_KEY_REUSED`.
- The pull cursor advances only after the changes commit locally.
- Deletes create tombstones that propagate through the change feed.
- Network errors, timeouts, 408, 429 and 5xx retry with jittered exponential backoff (5 s, 15 s, 1 min, 5 min, 15 min, then capped). 400, 401, 403, 404 and validation errors do not retry without a new action.
- Different-field edits merge automatically. Completion plus a title or note edit keeps both. Completion suppresses future reminders. Review moves keep stage history and the latest valid stage wins.
- Experiment body edits and conflicting milestone due dates require manual resolution.
- Resolution choices: keep local, keep server, or merge supported fields. A resolution is a new mutation with an activity event.
- Sync states shown to the user: Offline, Saved locally, Waiting to sync, Syncing, Synced just now, Sync error, Conflict.

**Acceptance Criteria:**
- [ ] Create, edit and complete work offline; after reconnecting the server receives exactly one of each.
- [ ] Pending mutations survive an app restart.
- [ ] Different-field edits on two devices merge; same-field experiment edits create a visible conflict.
- [ ] A server deletion applies as a tombstone and updates lists.
- [ ] Loss of connectivity during a push retries without duplicate activity events.
- [ ] The Sync Center lists state, pending count, last success, errors and conflicts, and allows manual retry.
- [ ] Sync state is reachable from every screen.

**Constraints:** Tombstone retention period: `[TBD: conservative value to be set; never remove a tombstone only because one device has synced.]` Attachments sync separately from record metadata (placeholder, signed upload, checksum, download on demand); offline attachment scope: `[TBD: metadata-only versus local upload; Architecture §15 leaves this open.]`

---

## 5. Architecture Overview

### 5.1 System Components

- **Client (Flutter/Dart):** presentation, application commands, domain rules, and data layer over a local SQLite database.
- **Sync engine:** outbox, cursor, retry, conflict handling and status, inside the client.
- **API (FastAPI):** authentication, authorization, CRUD, sync, exports and notifications.
- **Server database (PostgreSQL):** canonical data, change feed, tombstones, activity and audit.
- **Background workers:** reminder dispatch, exports, cleanup.
- **Object storage (S3-compatible):** attachments and export files.
- **Auth provider:** managed OIDC or equivalent.

### 5.2 Component Interactions

The client reads and writes SQLite; screens never call HTTP or SQL directly. The sync engine talks to the API over HTTPS. The API reads and writes PostgreSQL and queues jobs for workers. The backend is a modular monolith with background workers, with no microservices, event broker or search cluster in the MVP.

### 5.3 External Integrations

| Integration | Purpose | If unavailable |
|---|---|---|
| Managed auth provider | Sign-in, tokens, password reset | Local session keeps the app usable; sign-in and sync wait |
| Object storage | Attachments, exports | Exports and uploads fail with a retryable error; records unaffected |
| OS notification services | Reminder delivery | In-app notification center still works |

Future integrations (reference managers, GitHub, PubMed) are not in the MVP (§12.2, §13).

---

## 6. Data Model

### 6.1 Core Entities

Every synchronized entity has a client-generated sortable UUID, `workspace_id`, UTC `created_at`, `updated_at`, `updated_by`, `version`, and a deletion marker. Entities:

- **User:** id, email, display name, timezone, preferences.
- **Workspace:** owner, name, archive/delete metadata.
- **Project:** workspace, name, category, status, description, dates, progress mode and value.
- **Task:** project, milestone, parent task, title, description, status, priority, due time, estimated minutes, recurrence rule, completion time.
- **TimeBlock:** task and project links, title, category, start, end, status.
- **Milestone:** project, parent milestone, title, description, status, due time, progress value and mode, weight, completion time.
- **Review, ReviewStage, ReviewItem, ReviewItemEvent:** as in §4.8; the event records prior stage, next stage, decision metadata, actor and time.
- **AnalysisRecord:** as in §4.9.
- **ExperimentEntry, ExperimentRevision:** as in §4.10; revisions are immutable snapshots.
- **Notification:** linked entity, reminder time, urgency, channel, delivery status.
- **ActivityEvent:** actor, entity, action, summary-safe metadata, time (append-only).
- **AuditEvent:** actor, entity, action, request ID, time. Never stores sensitive content.
- **Attachment:** metadata, storage key, upload state, checksum.
- **SyncChange, SyncMutation, SyncConflict:** server change feed entries, idempotency records, and conflict snapshots (base, local, server).

Client-only tables: `sync_state`, `outbox_mutations`, `conflict_records`, `local_search_index`, attachment state.

### 6.2 Relationships

- User → owns → Workspaces.
- Workspace → contains → Projects, Tasks, Notifications, Activity.
- Project → contains → Milestones, Tasks, Reviews, Analyses, ExperimentEntries.
- Task → links to → one Project and one Milestone (optional); Task → has many → Subtasks.
- Milestone → nests under → Milestone; Milestone → depends on → Milestones.
- Review → has many → Stages and Items; Item → has many → Events.
- ExperimentEntry → has many → Revisions.

Database constraints enforce workspace scope, valid dates, progress 0–100, unique review stage names and positions, and valid foreign keys.

### 6.3 Data Lifecycle

Records are created locally first. Deletion is a tombstone, then cleanup after the retention rules allow it. Activity and audit events are append-only. Finalized experiment entries are never edited in place. Account deletion removes user data per the documented policy `[TBD: retention and backup purge window]`.

---

## 7. API Surface

### 7.1 API Style

Versioned REST under `/api/v1`, JSON bodies, ISO 8601 UTC timestamps, cursor pagination, idempotency keys on mutations, response envelope `{"data": {}, "meta": {"request_id": "…"}}`. Ordinary synchronized writes go through the sync endpoints; entity endpoints are online fallbacks.

### 7.2 Endpoint Overview

| Method | Path | Description | Auth |
|---|---|---|---|
| POST | /auth/register, /auth/login, /auth/refresh, /auth/logout | Account and session | Public / Required |
| GET, PATCH | /me | Profile and preferences | Required |
| GET, POST | /workspaces | List and create | Required |
| GET, POST, PATCH, DELETE | /projects, /projects/{id} | Projects | Required |
| GET, POST, PATCH, DELETE | /tasks, /tasks/{id} | Tasks | Required |
| GET, POST, PATCH, DELETE | /milestones, /milestones/{id} | Milestones | Required |
| GET, POST | /reviews/{id}/items | Review items | Required |
| POST, GET | /reviews/{id}/import, /reviews/{id}/export | CSV portability | Required |
| GET, POST, PATCH | /analysis-records | Analysis ledger | Required |
| GET, POST, PATCH | /experiment-entries | Experiments and revisions | Required |
| GET | /search | Authorized server search | Required |
| POST, GET | /exports, /exports/{id} | Async export jobs | Required |
| GET | /notifications | Reminder history | Required |
| GET | /sync/pull?cursor= | Pull change feed | Required |
| POST | /sync/push | Push mutation batch | Required |
| GET | /sync/conflicts | List conflicts | Required |
| POST | /sync/conflicts/{id}/resolve | Resolve a conflict | Required |
| GET | /health/live, /health/ready | Liveness and readiness | Public |

### 7.3 Authentication & Authorization

Bearer tokens issued through the managed provider; every request is authorized against the authenticated user and the target workspace. Queued mutations are re-validated on arrival.

### 7.4 Rate Limiting

Applied to auth, sync and export endpoints. `[TBD: numeric limits and header format are not defined.]`

### 7.5 Error Format

```json
{
  "error": {
    "code": "VERSION_CONFLICT",
    "message": "Human-readable safe message",
    "details": {},
    "request_id": "req_uuid",
    "retryable": false
  }
}
```

Codes are stable and machine-readable (for example `VALIDATION_ERROR`, `VERSION_CONFLICT`, `IDEMPOTENCY_KEY_REUSED`). Conflict errors add `entity_type`, `entity_id`, `server_version` and `client_version`. Messages are safe to show; code and version fields drive client behavior.

---

## 8. User Interface

### 8.1 Interface Type

Flutter application with responsive layouts for Android, iOS, Windows and Linux.

### 8.2 Key Screens

| ID | Screen | Purpose |
|---|---|---|
| S01 | Welcome | Explain value, start setup |
| S02 | Sign in / create account | Authenticate |
| S03 | Onboarding | Timezone, work hours, reminders |
| S04 | Workspace switcher | Select or create workspace |
| S05 | Today | Daily briefing and next actions |
| S06 | Calendar | Day, week, month, agenda |
| S07 | Quick capture | Task, note, reminder, inbox item |
| S08 | Inbox | Process uncategorized items |
| S09 | Project list | Browse projects |
| S10 | Project overview | Progress and linked work |
| S11 | Milestone dashboard | Timeline, at risk, blocked |
| S12 | Task detail/edit | View and edit a task |
| S13 | Time-block editor | Plan protected work |
| S14 | Review board | Move review items |
| S15 | Review item detail | Decision, notes, history |
| S16 | Analysis ledger | Track analyses |
| S17 | Analysis record detail | Run result and next action |
| S18 | Experiment log | Browse entries |
| S19 | Experiment entry editor | Draft, finalize, revise |
| S20 | Search | Find authorized records |
| S21 | Notifications | Reminders and delivery state |
| S22 | Sync Center | Sync state and errors |
| S23 | Conflict resolution | Compare and resolve |
| S24 | Settings / privacy | Account, export, deletion |

Each screen defines its loading, empty, error, offline and populated states. Sync Center shows state, pending count, last sync and errors; the sync banner is visible from every screen and routes to conflicts. Required wireflows: activation, daily planning, academic project, CSV import, offline capture, and conflict resolution.

### 8.3 Responsive Requirements and Accessibility

- **Mobile:** bottom navigation (Today, Calendar, Projects, Inbox, More); persistent capture action; grouped lists instead of Kanban columns; bottom sheets for quick edits and full-screen forms for long research entries; no drag-and-drop required.
- **Desktop:** persistent sidebar; split panes for list and detail; keyboard shortcuts for capture, search, task completion and board movement; resizable panels; drag-and-drop as an enhancement only.
- **Shared:** WCAG 2.2 AA principles; visible focus; scalable text; status shown by icon, text and color together; drafts autosave locally and never finalize silently; back navigation keeps drafts.
- Visual identity follows `OmniAssist — Branding Guide.md`.

---

## 9. Security Model

### 9.1 Authentication

Managed provider, email and password, provider-managed reset. Refresh tokens in platform secure storage. Authentication endpoints are rate limited.

### 9.2 Authorization

MVP role: Owner of a private workspace. Every entity query and mutation is checked for user and workspace. Least privilege applies to services and workers.

### 9.3 Data Protection

TLS in transit; managed server-side encryption at rest; protected local database handling `[TBD: file-level versus field-level local encryption]`. True end-to-end encryption is out of scope for the MVP; the product must not describe itself as end-to-end encrypted. Logs, analytics and crash reports are redacted and never contain task, note, experiment or review content.

### 9.4 Input Validation

Validate at the API boundary and again in the domain. CSV imports are bounded and previewed. Attachments use signed URLs, type allowlists, size limits and checksums.

### 9.5 Auditing

Audit events record actor, action, entity, time and request ID, and never store sensitive content.

---

## 10. Deployment Model

### 10.1 Target Environments and Platforms

Client platforms: Android, iOS, Windows, Linux (feature parity with platform-adapted layouts). Server environments: development, staging, production.

### 10.2 Distribution Method

Android and iOS beta builds; Windows installer; Linux package (`[TBD: AppImage, Flatpak or deb]`). API as a Docker image.

### 10.3 Configuration

Typed environment configuration, `.env.example`, secrets in CI secrets or managed secret storage. Startup validates required production secrets.

### 10.4 System Requirements

`[TBD: minimum OS versions and hardware are not defined.]`

### 10.5 Backup and Recovery

Managed PostgreSQL point-in-time recovery where available, daily logical export, object storage versioning, and a quarterly restore test. Recovery point and time targets: `[TBD: must be set before public beta.]`

---

## 11. Performance Requirements

### 11.1 Response Time Targets

- Local task search: under 500 ms on a representative dataset.
- Quick capture to saved: under 10 seconds end to end for the user; the local write is immediate.
- API p95 for ordinary reads and writes: `[TBD: target not set; Task 39 measures and documents a baseline.]`

### 11.2 Throughput Targets

Sync handles bounded batches without duplicate application. `[TBD: batch size, concurrent users and data volume targets.]`

### 11.3 Resource Limits

`[TBD: client storage, memory and server resource limits.]` Telemetry tracks sync duration, batch sizes, retries, conflict rate, unresolved conflicts, cursor lag and attachment failures, without content.

---

## 12. Constraints & Non-Goals

### 12.1 Technical Constraints

- Mobile operating systems restrict background execution and notification scheduling.
- Linux distributions vary in notification, secure-storage and packaging support.
- Core flows must not depend on the network.
- Business rules must be independent of UI and HTTP code.

### 12.2 Non-Goals

- **Collaboration and supervisor access:** the MVP is individual-first with the Owner role only.
- **Voice capture and natural-language task parsing:** deferred.
- **Direct Zotero, Rayyan, GitHub or PubMed integrations:** deferred.
- **Local LLMs and automatic schedule optimization:** deferred.
- **True end-to-end encryption:** changes search, recovery, export and sync; deferred.
- **Arbitrary code execution** (Python or R) on the client or server.
- **Reference-management database, laboratory instrument connectivity, rich media processing.**
- **Regulated electronic lab notebook compliance:** the app must not claim it.
- **Real-time collaborative editing.**

### 12.3 Assumptions

- Users own a phone and a desktop and want both.
- A managed auth provider meets the security needs.
- Researchers accept explicit conflict resolution for research notes.

### 12.4 Open Questions

- **[TBD: Authentication provider]** Managed OIDC versus custom FastAPI auth. Leaning managed (Implementation Plan §1.3).
- **[TBD: Local database encryption]** File-level, field-level, or both.
- **[TBD: Sync granularity]** Field-level patches for all entities versus record-level for complex ones.
- **[TBD: Attachments]** Metadata-only versus local upload/download in the MVP.
- **[TBD: Notification channels]** Push and desktop only versus email fallback.
- **[TBD: Linux packaging format]** AppImage, Flatpak or deb.
- **[TBD: Data residency and retention]** Hosting region, backup duration, deletion window, recovery policy.
- **[TBD: Background job library]** Dramatiq or RQ.
- **[TBD: Status and priority value lists]** For tasks, milestones and analyses.

---

## 13. Future Considerations

- **Collaboration:** supervisor and lab sharing with additional roles.
- **Integrations:** reference managers, GitHub, PubMed, calendar services.
- **Security:** optional end-to-end encryption with per-workspace keys.
- **Planning:** automatic schedule suggestions, voice capture and natural-language entry.
- **Search:** server-side full-text search as data grows.
