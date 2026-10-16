# Active work

## Completed

- [x] **Task 1 — Web-first repository migration.** Acceptance: `pnpm lint`, `pnpm typecheck`, and `pnpm build` pass; Flutter is outside the active build; `make check` runs web/API checks.
- [x] **Task 2 — API configuration and deployment baseline.** Acceptance: API starts with `uv run uvicorn`; health routes return 200 when healthy; production settings reject development credentials; the Render Blueprint validates.
- [x] **Task 3 — PWA shell and design tokens.** Added OmniAssist brand tokens and responsive shell, manifest and icons, metadata, a service worker, offline fallback, and reduced-motion behavior. Production preview and 320 px/1280 px layouts verified; PWA privacy regression tests pass.
- [x] **Task 4 — Contracts, shared types, and CI.** Added `@omniassist/contracts` envelopes, error codes and domain types; a typed API client that preserves request IDs; separate web/API workflows; and parity/runtime tests.

## In progress

- [ ] **Task 5 — Neon schema and migrations.** Continue from the plan in `docs/WEB_PWA_TASKS.md` and the original task PDF.

## Queued
- [ ] Tasks 6–10 — Database and API core.
- [ ] Tasks 11–16 — Authenticated frontend.
- [ ] Tasks 17–20 — Research frontend.
- [ ] Tasks 21–23 — Quality and PWA.
- [ ] Task 24 — Production release.

See [`docs/WEB_PWA_TASKS.md`](docs/WEB_PWA_TASKS.md) and the linked source PDF for the complete ordered plan.
