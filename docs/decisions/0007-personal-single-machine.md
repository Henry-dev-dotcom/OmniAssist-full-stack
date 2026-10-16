# 0007. Personal use: one local server, reached privately from the phone

Status: accepted (2026-10-16). Supersedes the "rent a server" assumption in `deployment.md`
for a single owner; that guide stays valid for hosting elsewhere.

## Decision
- The API also serves the built web app (`OMNI_WEB_DIR`), so one process on one port runs
  everything. The app uses the address it was opened from for its API calls, so the same build
  works at `localhost`, a Tailscale address, or behind any proxy. `API_BASE_URL` is only for an
  API hosted elsewhere.
- `scripts/start-omniassist.ps1` starts the database, migrates, and runs the API (and the
  reminder sender when push keys exist). It listens on `127.0.0.1` only unless `-BindAll`.
- The phone connects over Tailscale (`tailscale serve`), which provides HTTPS inside a private
  network. HTTPS is required for installing the app, the offline service worker and push.
- `OMNI_ALLOW_REGISTRATION=false` closes sign-up after the owner's account exists.

## Why
Phones treat plain `http://` LAN addresses as insecure, which disables the features that make
the app usable on a phone. Tailscale gives a real certificate without a public server, a domain,
or open router ports, and nobody outside the owner's devices can reach it.

## Consequences
- The PC must be on for the phone to sync or for push reminders to arrive. The phone keeps
  working offline and catches up later.
- Backups are the owner's job (`infra/scripts/backup_restore.py`, documented in
  `docs/personal-setup.md`).
