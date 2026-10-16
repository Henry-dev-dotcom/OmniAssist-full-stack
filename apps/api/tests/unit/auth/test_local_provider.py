from datetime import UTC, datetime, timedelta
from typing import Any

import jwt
import pytest

from src.auth.local_provider import (
    AUDIENCE,
    ISSUER,
    MAX_FAILURES,
    LocalProvider,
    hash_password,
    verify_password,
)
from src.domain.common.errors import DomainError, ErrorCode

SECRET = "s" * 40


def provider(clock: list[float] | None = None) -> LocalProvider:
    t = clock or [0.0]
    p = LocalProvider(secret=SECRET, sessions=None, clock=lambda: t[0])  # type: ignore[arg-type]

    async def exists(subject: str) -> bool:
        return subject != "local|deleted"

    p._exists = exists  # type: ignore[method-assign]
    return p


def token(**over: Any) -> str:
    now = datetime.now(UTC)
    claims = {
        "iss": ISSUER,
        "aud": AUDIENCE,
        "sub": "local|1",
        "email": "ada@example.com",
        "exp": now + timedelta(minutes=5),
        **over,
    }
    return jwt.encode(claims, SECRET, algorithm="HS256")


def test_password_hash_round_trip_and_salted() -> None:
    a, b = hash_password("correct horse"), hash_password("correct horse")
    assert a != b  # random salt
    assert verify_password("correct horse", a)
    assert not verify_password("wrong horse", a)
    assert not verify_password("x", "garbage")
    assert not verify_password("x", "bcrypt$1$1$1$AA==$AA==")


async def test_valid_token_gives_identity() -> None:
    who = await provider().verify_access_token(token(name="Ada"))
    assert (who.subject, who.email, who.name) == ("local|1", "ada@example.com", "Ada")


@pytest.mark.parametrize(
    "bad",
    [
        token(exp=datetime.now(UTC) - timedelta(seconds=1)),
        token(iss="someone-else"),
        token(aud="other-api"),
        jwt.encode({"iss": ISSUER, "aud": AUDIENCE, "sub": "x", "exp": 9e9}, SECRET, "HS256"),
        jwt.encode(
            {"iss": ISSUER, "aud": AUDIENCE, "sub": "x", "email": "e", "exp": 9e9},
            "w" * 40,
            "HS256",
        ),
        "not-a-jwt",
        token(sub="local|deleted"),
    ],
    ids=["expired", "issuer", "audience", "no-email", "wrong-key", "garbage", "deleted"],
)
async def test_bad_tokens_are_rejected(bad: str) -> None:
    with pytest.raises(DomainError) as e:
        await provider().verify_access_token(bad)
    assert e.value.code == ErrorCode.UNAUTHENTICATED


async def test_short_password_is_rejected_before_any_db_work() -> None:
    with pytest.raises(DomainError) as e:
        await provider().register("ada@example.com", "short", "Ada")
    assert e.value.code == ErrorCode.VALIDATION_ERROR


def test_rate_limit_blocks_after_failures_then_expires() -> None:
    clock = [1000.0]
    p = provider(clock)
    p._failures["ada@example.com"] = [clock[0]] * MAX_FAILURES
    with pytest.raises(DomainError) as e:
        p._check_rate("ada@example.com")
    assert e.value.code == ErrorCode.RATE_LIMITED
    p._check_rate("bob@example.com")  # other accounts unaffected
    clock[0] += 15 * 60 + 1
    p._check_rate("ada@example.com")
    assert "ada@example.com" not in p._failures  # stale entries are dropped
