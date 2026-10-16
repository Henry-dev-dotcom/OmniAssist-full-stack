# 0003. Generic record store, and the values the spec left open

Status: accepted (2026-10-16).

## Decisions

**Client storage for research entities.** Milestones, reviews, review items, analysis records,
experiment entries, experiment revisions and activity events share one Drift table, `records`
(`apps/client/lib/database/tables/record_tables.dart`), holding each entity as JSON with API field
names. Pulled changes merge per field exactly like typed tables: a field with an unsent local
edit keeps the local value. Tasks, projects and time blocks keep their typed tables.
The server stays strictly typed and validated (`src/domain/common/records.py` plus one module
per entity), because it is the trust boundary.

**Status lists** (Spec 12.4):
- Tasks: `inbox, planned, in_progress, complete, snoozed, cancelled, archived` (existing).
- Milestones: `not_started, in_progress, at_risk, blocked, complete, archived`.
- Analyses: `planned, running, succeeded, failed, blocked, archived`. Allowed moves are in
  `analyses/schemas.py` `TRANSITIONS`; an archived record comes back only through `planned`.
  Moving into running, succeeded or failed stamps `last_run_at`.
- Review decisions: `include, exclude, maybe` or none.

**Weighted milestone progress** (Spec 4.7): the weighted average of child milestones' progress
(weight defaults to 1); with no children, the share of linked tasks that are complete. Computed
on the device; the server stores only manual progress values. Complete is always 100%.

**Routines** on Today are recurring tasks (tasks with a recurrence rule) due today or undated.

**CSV import limits** (Spec 4.8): 5 MB, 5,000 rows, 50 columns, 10,000 characters per cell.
Every row is validated before anything is written, and a valid import is one local transaction.
Export cells that start with `= + - @` are prefixed with `'` so spreadsheets never run them.

**Deleting a project with linked work** (Spec 4.2): refused on client and server while it still
has live tasks, milestones, reviews, analyses or experiments. The user archives it instead.

**Review stages**: names are unique per review (case-insensitive); at least one stays active;
a stage that still holds items cannot be archived. Stages are never removed, only archived.

**Experiments**: finalizing stores an immutable snapshot in `experiment_revisions`. Editing a
finalized entry starts the next revision as a draft; the finalized one stays in the history.

**Activity history** is written by the server for every accepted mutation and reaches devices
through the change feed. Metadata holds field names and short enum values only, never content.

## Why
Typed client tables cost about 150 lines of sync code per entity; six entities shared one
generic merge instead. The open values had to be fixed to build and test the features; each is
the simplest rule that satisfies the acceptance criteria.

## Consequences
- Client queries on record-backed entities filter in Dart. Fine for one researcher's data;
  move a hot query to `json_extract` if a workspace grows past tens of thousands of records.
- Changing a status list needs a migration (server CHECK constraints) and a client update.
