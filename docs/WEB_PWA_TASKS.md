# OmniAssist Web/PWA task plan

This roadmap tracks the provided [Web/PWA task list PDF](OmniAssist-Web-PWA-Tasks.pdf). The PDF is the authoritative source for full task descriptions, files, dependencies, effort estimates, and acceptance criteria.

**Progress:** Task 1 complete; Task 2 is next. All other tasks are queued.

> The PDF summary says “7 phases,” but its body enumerates six numbered phases (1–6) and 24 tasks. No seventh phase is specified, so this tracker preserves the six phases actually listed rather than inventing a phase.

## Phase 1: Foundation

| Task | Outcome | Status |
| --- | --- | --- |
| 1 | Web-first repository migration | **Complete** |
| 2 | API configuration and deployment baseline | Next |
| 3 | PWA shell and design tokens | Queued |
| 4 | Contracts, shared types, and CI | Queued |

## Phase 2: Database and API Core

| Task | Outcome | Status |
| --- | --- | --- |
| 5 | Neon schema and migrations | Queued |
| 6 | Auth claims and workspace authorization | Queued |
| 7 | Project and task API | Queued |
| 8 | Calendar, reminders, and milestones API | Queued |
| 9 | Research modules API | Queued |
| 10 | Search and export API | Queued |

## Phase 3: Authenticated Frontend

| Task | Outcome | Status |
| --- | --- | --- |
| 11 | Clerk integration and protected routes | Queued |
| 12 | Web application shell | Queued |
| 13 | Onboarding and workspace UI | Queued |
| 14 | Projects and tasks UI | Queued |
| 15 | Today and calendar UI | Queued |
| 16 | Milestone UI | Queued |

## Phase 4: Research Frontend

| Task | Outcome | Status |
| --- | --- | --- |
| 17 | Review board and CSV flows | Queued |
| 18 | Analysis ledger UI | Queued |
| 19 | Experiment log UI | Queued |
| 20 | Search, notifications, export, and settings | Queued |

## Phase 5: Quality and PWA

| Task | Outcome | Status |
| --- | --- | --- |
| 21 | Browser persistence and PWA verification | Queued |
| 22 | Accessibility and responsive QA | Queued |
| 23 | Security, performance, and integration QA | Queued |

## Phase 6: Deployment

| Task | Outcome | Status |
| --- | --- | --- |
| 24 | Production release | Queued |

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
