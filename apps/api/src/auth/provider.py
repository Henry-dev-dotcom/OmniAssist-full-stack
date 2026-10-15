"""Auth provider adapter. Provider-specific code lives only in this module.

OidcProvider speaks standard OpenID Connect (discovery, JWKS, token and revocation
endpoints), so Auth0, Keycloak, Cognito, Supabase and similar providers work by
configuration. Sign-up is provider-hosted in OIDC, so `register` is unsupported here.
"""

from dataclasses import dataclass
from typing import Any, Protocol

import httpx
import jwt

from src.domain.common.errors import DomainError, ErrorCode

UNAUTHENTICATED_MSG = "Your session is invalid or has expired. Sign in again."


@dataclass(frozen=True)
class Identity:
    subject: str
    email: str
    name: str | None = None


@dataclass(frozen=True)
class AuthSession:
    access_token: str
    refresh_token: str | None
    expires_in: int


class AuthProvider(Protocol):
    async def register(self, email: str, password: str, display_name: str) -> AuthSession: ...
    async def login(self, email: str, password: str) -> AuthSession: ...
    async def refresh(self, refresh_token: str) -> AuthSession: ...
    async def logout(self, refresh_token: str) -> None: ...
    async def verify_access_token(self, token: str) -> Identity: ...


def unauthenticated(message: str = UNAUTHENTICATED_MSG) -> DomainError:
    return DomainError(ErrorCode.UNAUTHENTICATED, message)


def unavailable() -> DomainError:
    return DomainError(ErrorCode.DEPENDENCY_UNAVAILABLE, "Sign-in is temporarily unavailable.")


class OidcProvider:
    def __init__(
        self,
        *,
        issuer: str,
        audience: str,
        client_id: str,
        client_secret: str = "",
        http: httpx.AsyncClient | None = None,
    ) -> None:
        self._issuer = issuer.rstrip("/")
        self._audience = audience
        self._client_id = client_id
        self._client_secret = client_secret
        self._http = http or httpx.AsyncClient(timeout=10)
        self._config: dict[str, Any] | None = None
        self._jwks: dict[str, Any] | None = None

    async def _get_json(self, url: str) -> dict[str, Any]:
        try:
            r = await self._http.get(url)
            r.raise_for_status()
            data: dict[str, Any] = r.json()
            return data
        except (httpx.HTTPError, ValueError):
            raise unavailable() from None

    async def _discovery(self) -> dict[str, Any]:
        if self._config is None:
            url = f"{self._issuer}/.well-known/openid-configuration"
            self._config = await self._get_json(url)
        return self._config

    async def _signing_key(self, kid: str | None, *, refresh: bool = False) -> Any:
        if self._jwks is None or refresh:
            self._jwks = await self._get_json((await self._discovery())["jwks_uri"])
        for jwk in self._jwks.get("keys", []):
            if jwk.get("kid") == kid:
                return jwt.PyJWK(jwk).key
        if not refresh:  # keys may have rotated
            return await self._signing_key(kid, refresh=True)
        return None

    async def verify_access_token(self, token: str) -> Identity:
        try:
            kid = jwt.get_unverified_header(token).get("kid")
            key = await self._signing_key(kid)
            if key is None:
                raise unauthenticated()
            claims = jwt.decode(
                token,
                key,
                algorithms=["RS256", "ES256"],
                audience=self._audience,
                issuer=self._issuer,
                options={"require": ["exp", "sub"]},
            )
        except jwt.PyJWTError:
            raise unauthenticated() from None  # never echo provider details
        email = claims.get("email")
        if not email:
            raise unauthenticated()
        return Identity(subject=claims["sub"], email=email, name=claims.get("name"))

    async def _token_request(self, form: dict[str, str]) -> AuthSession:
        config = await self._discovery()
        form = {"client_id": self._client_id, **form}
        if self._client_secret:
            form["client_secret"] = self._client_secret
        try:
            r = await self._http.post(config["token_endpoint"], data=form)
        except httpx.HTTPError:
            raise unavailable() from None
        if r.status_code >= 500:
            raise unavailable()
        if r.status_code >= 400:
            raise unauthenticated("Email or password is incorrect.")
        body = r.json()
        return AuthSession(
            access_token=body["access_token"],
            refresh_token=body.get("refresh_token"),
            expires_in=int(body.get("expires_in", 3600)),
        )

    async def register(self, email: str, password: str, display_name: str) -> AuthSession:
        raise DomainError(
            ErrorCode.DOMAIN_RULE_VIOLATION,
            "Create your account on the sign-up page, then sign in.",
        )

    async def login(self, email: str, password: str) -> AuthSession:
        return await self._token_request(
            {
                "grant_type": "password",
                "username": email,
                "password": password,
                "scope": "openid email profile offline_access",
            }
        )

    async def refresh(self, refresh_token: str) -> AuthSession:
        return await self._token_request(
            {"grant_type": "refresh_token", "refresh_token": refresh_token}
        )

    async def logout(self, refresh_token: str) -> None:
        endpoint = (await self._discovery()).get("revocation_endpoint")
        if not endpoint:
            return
        form = {
            "token": refresh_token,
            "token_type_hint": "refresh_token",
            "client_id": self._client_id,
        }
        if self._client_secret:
            form["client_secret"] = self._client_secret
        try:
            await self._http.post(endpoint, data=form)
        except httpx.HTTPError:
            raise unavailable() from None
