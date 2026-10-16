"""Built-in email/password sign-in (decision 0002). Swappable for OidcProvider by config.

Passwords: scrypt with a random salt. Access tokens: short-lived HS256 JWTs. Refresh
tokens: random, stored only as SHA-256, rotated on every use, revoked on logout.
"""

import asyncio
import base64
import hashlib
import hmac
import secrets
import time
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Any

import jwt
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from src.auth.provider import AuthSession, Identity, unauthenticated
from src.domain.common.errors import DomainError, ErrorCode
from src.domain.common.ids import new_uuid7

ISSUER = "omniassist-local"
AUDIENCE = "omniassist-api"
ACCESS_TTL_SECONDS = 15 * 60
REFRESH_TTL = timedelta(days=30)
MIN_PASSWORD_LENGTH = 8
MAX_FAILURES = 10
FAILURE_WINDOW_SECONDS = 15 * 60
_SCRYPT_N, _SCRYPT_R, _SCRYPT_P = 2**14, 8, 1


def _b64(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode()


def _sha256(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=_SCRYPT_N, r=_SCRYPT_R, p=_SCRYPT_P)
    return f"scrypt${_SCRYPT_N}${_SCRYPT_R}${_SCRYPT_P}${_b64(salt)}${_b64(digest)}"


def verify_password(password: str, stored: str) -> bool:
    try:
        algo, n, r, p, salt, digest = stored.split("$")
        if algo != "scrypt":
            return False
        got = hashlib.scrypt(
            password.encode(),
            salt=base64.urlsafe_b64decode(salt),
            n=int(n),
            r=int(r),
            p=int(p),
        )
        return hmac.compare_digest(got, base64.urlsafe_b64decode(digest))
    except ValueError:
        return False


# Unknown emails are checked against this, so timing does not reveal which accounts exist.
_DUMMY_HASH = hash_password(secrets.token_urlsafe(16))


class LocalProvider:
    def __init__(
        self,
        *,
        secret: str,
        sessions: async_sessionmaker[AsyncSession],
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._secret = secret
        self._sessions = sessions
        self._clock = clock
        # shortcut: failed-login counts live in this process only, move to Redis when
        # the API runs more than one worker.
        self._failures: dict[str, list[float]] = {}

    async def register(self, email: str, password: str, display_name: str) -> AuthSession:
        if len(password) < MIN_PASSWORD_LENGTH:
            raise DomainError(
                ErrorCode.VALIDATION_ERROR,
                f"Use a password with at least {MIN_PASSWORD_LENGTH} characters.",
                {"field": "password"},
            )
        subject = f"local|{new_uuid7()}"
        hashed = await asyncio.to_thread(hash_password, password)
        async with self._sessions() as s:
            try:
                await s.execute(
                    text(
                        """INSERT INTO local_credentials
                          (subject, email, display_name, password_hash)
                        VALUES (:sub, :email, :name, :hash)"""
                    ),
                    {"sub": subject, "email": email, "name": display_name, "hash": hashed},
                )
            except IntegrityError:
                raise DomainError(
                    ErrorCode.DOMAIN_RULE_VIOLATION,
                    "An account with this email already exists. Sign in instead.",
                ) from None
            session = await self._issue(s, subject, email, display_name)
            await s.commit()
        return session

    async def login(self, email: str, password: str) -> AuthSession:
        key = email.lower()
        self._check_rate(key)
        async with self._sessions() as s:
            row = (
                (
                    await s.execute(
                        text(
                            """SELECT subject, email, display_name, password_hash
                            FROM local_credentials WHERE lower(email) = :email"""
                        ),
                        {"email": key},
                    )
                )
                .mappings()
                .one_or_none()
            )
            stored = row["password_hash"] if row else _DUMMY_HASH
            ok = await asyncio.to_thread(verify_password, password, stored)
            if row is None or not ok:
                self._failures.setdefault(key, []).append(self._clock())
                raise unauthenticated("Email or password is incorrect.")
            self._failures.pop(key, None)
            session = await self._issue(s, row["subject"], row["email"], row["display_name"])
            await s.commit()
        return session

    async def refresh(self, refresh_token: str) -> AuthSession:
        async with self._sessions() as s:
            # Revoke-and-read in one statement: a token can be exchanged exactly once.
            row = (
                (
                    await s.execute(
                        text(
                            """UPDATE local_refresh_tokens t SET revoked_at = now()
                            FROM local_credentials c
                            WHERE t.token_hash = :hash AND t.revoked_at IS NULL
                              AND t.expires_at > now() AND c.subject = t.subject
                            RETURNING c.subject, c.email, c.display_name"""
                        ),
                        {"hash": _sha256(refresh_token)},
                    )
                )
                .mappings()
                .one_or_none()
            )
            if row is None:
                raise unauthenticated()
            session = await self._issue(s, row["subject"], row["email"], row["display_name"])
            await s.commit()
        return session

    async def logout(self, refresh_token: str) -> None:
        async with self._sessions() as s:
            await s.execute(
                text(
                    """UPDATE local_refresh_tokens SET revoked_at = now()
                    WHERE token_hash = :hash AND revoked_at IS NULL"""
                ),
                {"hash": _sha256(refresh_token)},
            )
            await s.commit()

    async def verify_access_token(self, token: str) -> Identity:
        try:
            claims: dict[str, Any] = jwt.decode(
                token,
                self._secret,
                algorithms=["HS256"],
                audience=AUDIENCE,
                issuer=ISSUER,
                options={"require": ["exp", "sub", "email"]},
            )
        except jwt.PyJWTError:
            raise unauthenticated() from None
        if not await self._exists(claims["sub"]):
            raise unauthenticated()  # deleted account: its unexpired tokens die with it
        return Identity(subject=claims["sub"], email=claims["email"], name=claims.get("name"))

    async def _exists(self, subject: str) -> bool:
        async with self._sessions() as s:
            row = await s.execute(
                text("SELECT 1 FROM local_credentials WHERE subject = :sub"), {"sub": subject}
            )
            return row.first() is not None

    def _check_rate(self, key: str) -> None:
        cutoff = self._clock() - FAILURE_WINDOW_SECONDS
        recent = [t for t in self._failures.get(key, []) if t > cutoff]
        if recent:
            self._failures[key] = recent
        else:
            self._failures.pop(key, None)  # keeps the map from growing with stale emails
        if len(recent) >= MAX_FAILURES:
            raise DomainError(
                ErrorCode.RATE_LIMITED, "Too many sign-in attempts. Try again in 15 minutes."
            )

    async def _issue(
        self, s: AsyncSession, subject: str, email: str, name: str | None
    ) -> AuthSession:
        now = datetime.now(UTC)
        access = jwt.encode(
            {
                "iss": ISSUER,
                "aud": AUDIENCE,
                "sub": subject,
                "email": email,
                "name": name,
                "iat": now,
                "exp": now + timedelta(seconds=ACCESS_TTL_SECONDS),
            },
            self._secret,
            algorithm="HS256",
        )
        refresh = secrets.token_urlsafe(32)
        await s.execute(
            text(
                """INSERT INTO local_refresh_tokens (token_hash, subject, expires_at)
                VALUES (:hash, :sub, :exp)"""
            ),
            {"hash": _sha256(refresh), "sub": subject, "exp": now + REFRESH_TTL},
        )
        return AuthSession(
            access_token=access, refresh_token=refresh, expires_in=ACCESS_TTL_SECONDS
        )
