# 0002. Built-in email/password login until a hosted provider is chosen

Status: accepted (2026-10-15). Amends 0001: OIDC stays available behind `OMNI_AUTH_PROVIDER=oidc`.

## Decision
`OMNI_AUTH_PROVIDER=local` (the default) signs users in with `src/auth/local_provider.py`, which
implements the same `AuthProvider` interface as `OidcProvider`. The client gets a "Create account"
mode on the sign-in screen, backed by `POST /auth/register`.

- Passwords: stdlib scrypt (N=2^14, r=8, p=1, 16-byte salt), compared in constant time. Minimum 8 characters.
- Access tokens: HS256 JWTs signed with `OMNI_AUTH_LOCAL_SECRET`, valid 15 minutes.
- Refresh tokens: 32 random bytes, stored only as SHA-256, valid 30 days, rotated on every refresh, revoked on logout.
- Brute force: 10 failed logins per email per 15 minutes returns `RATE_LIMITED`. Unknown emails pay the same hash cost as known ones.
- Production refuses to start with the development signing secret.

## Why
The user wants to use the app now. No provider has been picked, and a generic adapter with no provider means nobody can sign in.

## Consequences
- No password reset or email verification yet. A forgotten password needs a database fix.
- The failed-login counter is per API process (`shortcut:` comment in the provider).
- Switching to a hosted provider later: set `OMNI_AUTH_PROVIDER=oidc` and its settings. Existing local users get new `users` rows unless their `auth_subject` is migrated to the provider's `sub`. Plan that migration when the provider is chosen.
