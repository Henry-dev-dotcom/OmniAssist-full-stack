# 0001. Generic OIDC adapter for authentication

Status: accepted

## Decision
The API verifies sign-in through a provider adapter (`src/auth/provider.py`). The first adapter speaks standard OpenID Connect: discovery, JWKS, token endpoint and revocation endpoint. No vendor is named in code. A provider is chosen by configuration: `OMNI_AUTH_ISSUER`, `OMNI_AUTH_AUDIENCE`, `OMNI_AUTH_CLIENT_ID`, and optionally `OMNI_AUTH_CLIENT_SECRET`.

## Why
- Spec 9.1 left the provider open. A generic adapter lets the team pick Auth0, Keycloak, Cognito or Supabase later without code changes.
- Provider-specific code stays in one module, so a swap touches one file.

## Consequences
- Sign-up is hosted by the provider. `POST /auth/register` returns DOMAIN_RULE_VIOLATION with a message pointing to the sign-up page.
- One local user per provider `sub`, stored in `users.auth_subject`. The user row is created on first valid token.
- The provider must allow the password grant for the in-app login screen, or the client must use the provider's hosted login with PKCE. Decide this when the provider is chosen.
- Provider error details are never returned to clients or logged.
