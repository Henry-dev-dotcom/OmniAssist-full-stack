# OmniAssist Web/PWA task plan

This roadmap tracks the provided [Web/PWA task list PDF](OmniAssist-Web-PWA-Tasks.pdf). The PDF is the authoritative source for full task descriptions, files, dependencies, effort estimates, and acceptance criteria.

**Progress:** Tasks 1–23 complete (with documented device-test limits); Task 24 is in progress and blocked on production targets and owner choices.

> The PDF summary says “7 phases,” but its body enumerates six numbered phases (1–6) and 24 tasks. No seventh phase is specified, so this tracker preserves the six phases actually listed rather than inventing a phase.

> Task 2 keeps the existing Render Blueprint at the repository root (`render.yaml`), rather than copying it to `infra/render.yaml`, so Render's automatic Blueprint discovery and the single source of truth remain intact.

## Phase 1: Foundation

| Task | Outcome | Status |
| --- | --- | --- |
| 1 | Web-first repository migration | **Complete** |
| 2 | API configuration and deployment baseline | **Complete** |
| 3 | PWA shell and design tokens | **Complete** |
| 4 | Contracts, shared types, and CI | **Complete** |

## Phase 2: Database and API Core

| Task | Outcome | Status |
| --- | --- | --- |
| 5 | Neon schema and migrations | **Complete** |
| 6 | Auth claims and workspace authorization | **Complete** |
| 7 | Project and task API | **Complete** |
| 8 | Calendar, reminders, and milestones API | **Complete** |
| 9 | Research modules API | **Complete** |
| 10 | Search and export API | **Complete** |

## Phase 3: Authenticated Frontend

| Task | Outcome | Status |
| --- | --- | --- |
| 11 | Authenticated provider integration and protected routes | **Complete** |
| 12 | Web application shell | **Complete** |
| 13 | Onboarding and workspace UI | **Complete** |
| 14 | Projects and tasks UI | **Complete** |
| 15 | Today and calendar UI | **Complete** |
| 16 | Milestone UI | **Complete** |

## Phase 4: Research Frontend

| Task | Outcome | Status |
| --- | --- | --- |
| 17 | Review board and CSV flows | **Complete** |
| 18 | Analysis ledger UI | **Complete** |
| 19 | Experiment log UI | **Complete** |
| 20 | Search, notifications, export, and settings | **Complete** |

## Phase 5: Quality and PWA

| Task | Outcome | Status |
| --- | --- | --- |
| 21 | Browser persistence and PWA verification | **Complete** |
| 22 | Accessibility and responsive QA | **Complete (automated; physical screen-reader/device checks remain)** |
| 23 | Security, performance, and integration QA | **Complete** |

Phase 5 verification: bounded browser-local experiment drafts (256 KiB per entry, 30-day expiry); Chromium production tests cover reload recovery, the offline shell, private-route redirects, a keyboard skip link, axe WCAG 2.1 AA checks and 320 px overflow. Service-worker tests assert API and credentialed requests are never cached. API CI provides PostgreSQL; local validation passed all 187 API tests, including integration/security and performance cases. Physical Android Chrome/iOS Safari install prompts and an assistive-technology session remain release-time manual checks. API-backed research mutations are online-first; Phase 5 does not add an offline mutation outbox.

## Phase 6: Deployment

| Task | Outcome | Status |
| --- | --- | --- |
| 24 | Production release | **In progress — blocked by zero-cost production suitability and owner choices** |

Phase 6 preflight (2026-10-16): the signed-in Vercel workspace contains no visible OmniAssist project; the selected Render workspace returned no existing service or database to target; and no alternative production PostgreSQL target is confirmed. The user authorized only free-tier resources. Render's free web service idles out and its free Postgres expires after 30 days without provider backups, so that stack cannot meet production acceptance; see the official links in [`deployment.md`](deployment.md). No OmniAssist project, service, database or deployment was created or changed. The web client now fails clearly rather than sending production API requests to localhost when `NEXT_PUBLIC_API_URL` is missing; the deployment runbook documents the correct Vercel variable.

## Milestones

| Milestone | After task | Result |
| --- | ---: | --- |
| Foundation | 4 | Web shell and API checks pass |
| Data layer | 10 | Authenticated CRUD API works |
| Core product | 16 | Planning workflow works |
| Research MVP | 20 | Research modules and settings work |
| Quality | 23 | Security, accessibility, PWA, and E2E gates pass |
| Release | 24 | Vercel/Render/Neon deployment is usable |

## Dependency sequence

```text
T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10
               ↘ T11 → T12 → T13 → T14 → T15 → T16
                                        ↘ T17 → T18 → T19 → T20
T3 + T12–T20 → T21 → T22 → T23 → T24
```
