# 0005. Task tags, recurrence rules and subtasks

Status: accepted (2026-10-16).

## Tags
A JSON list on the task (`tasks.tags`, migration 0006; client schema v3), up to 50 tags of
1–60 characters. Same shape as review item tags, so search and sync treat them alike. The
older `tags` / `task_tags` tables from migration 0001 stay unused.

## Recurrence rules
A subset of RFC 5545 RRULE, validated on the server (`domain/tasks/recurrence.py`) and the
client (`features/tasks/recurrence.dart`) with the same messages:
`FREQ=DAILY|WEEKLY|MONTHLY|YEARLY`, optional `INTERVAL=1..365`, optional `BYDAY=MO,...`
(weekly only). The app shows plain choices (daily, every weekday, weekly on chosen days,
monthly, yearly, every N); users never type the rule.

A repeating task needs a due date. Completing it finishes this occurrence only (Spec 4.3) and
creates the next one on the device, so it works offline. The rule moves to the new task, so
unticking and re-ticking the old one never makes a duplicate. Monthly and yearly rules keep
the day of month, clamped to the month's last day (31 January → 28 February).

## Subtasks
`parent_task_id`, one level shown in the task screen. The server refuses a parent that would
put a task inside its own subtask.
