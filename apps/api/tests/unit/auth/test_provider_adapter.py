import time
from typing import Any

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from src.auth.provider import OidcProvider
from src.domain.common.errors import DomainError, ErrorCode

ISS, AUD = "https://idp.test", "omni-api"


@pytest.fixture(scope="module")
def key() -> rsa.RSAPrivateKey:
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


def _jwks(key: rsa.RSAPrivateKey, kid: str) -> dict[str, Any]:
    jwk = jwt.algorithms.RSAAlgorithm.to_jwk(key.public_key(), as_dict=True)
    return {"keys": [{**jwk, "kid": kid, "alg": "RS256", "use": "sig"}]}


def _token(key: rsa.RSAPrivateKey, **over: Any) -> str:
    claims = {
        "iss": ISS, "aud": AUD, "sub": "u1", "email": "ada@example.com",
        "exp": int(time.time()) + 600,
    }  # fmt: skip
    claims.update(over)
    return jwt.encode(claims, key, algorithm="RS256", headers={"kid": "k1"})


def _provider(key: rsa.RSAPrivateKey, token_status: int = 200) -> OidcProvider:
    def handler(req: httpx.Request) -> httpx.Response:
        path = req.url.path
        if path.endswith("openid-configuration"):
            return httpx.Response(
                200,
                json={
                    "jwks_uri": f"{ISS}/jwks",
                    "token_endpoint": f"{ISS}/token",
                    "revocation_endpoint": f"{ISS}/revoke",
                },
            )
        if path == "/jwks":
            return httpx.Response(200, json=_jwks(key, "k1"))
        if path == "/token":
            if token_status != 200:
                return httpx.Response(token_status, text="secret provider detail")
            return httpx.Response(
                200, json={"access_token": "a", "refresh_token": "r", "expires_in": 60}
            )
        return httpx.Response(200)

    http = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return OidcProvider(issuer=ISS, audience=AUD, client_id="cid", http=http)


async def test_valid_token_returns_identity(key: rsa.RSAPrivateKey) -> None:
    who = await _provider(key).verify_access_token(_token(key))
    assert (who.subject, who.email) == ("u1", "ada@example.com")


@pytest.mark.parametrize(
    "over",
    [{"exp": 1}, {"aud": "other"}, {"iss": "https://evil.test"}],
    ids=["expired", "wrong-audience", "wrong-issuer"],
)
async def test_bad_claims_are_unauthenticated(key: rsa.RSAPrivateKey, over: dict[str, Any]) -> None:
    with pytest.raises(DomainError) as e:
        await _provider(key).verify_access_token(_token(key, **over))
    assert e.value.code == ErrorCode.UNAUTHENTICATED


async def test_token_signed_by_other_key_rejected(key: rsa.RSAPrivateKey) -> None:
    other = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    with pytest.raises(DomainError) as e:
        await _provider(key).verify_access_token(_token(other))
    assert e.value.code == ErrorCode.UNAUTHENTICATED


async def test_garbage_token_rejected(key: rsa.RSAPrivateKey) -> None:
    with pytest.raises(DomainError) as e:
        await _provider(key).verify_access_token("not-a-jwt")
    assert e.value.code == ErrorCode.UNAUTHENTICATED


async def test_login_ok_and_provider_failure_hidden(key: rsa.RSAPrivateKey) -> None:
    s = await _provider(key).login("a@b.co", "pw")
    assert (s.access_token, s.refresh_token, s.expires_in) == ("a", "r", 60)
    with pytest.raises(DomainError) as e:
        await _provider(key, 401).login("a@b.co", "bad")
    assert e.value.code == ErrorCode.UNAUTHENTICATED
    assert "secret" not in e.value.message
    with pytest.raises(DomainError) as e2:
        await _provider(key, 503).login("a@b.co", "pw")
    assert e2.value.code == ErrorCode.DEPENDENCY_UNAVAILABLE


async def test_register_is_unsupported(key: rsa.RSAPrivateKey) -> None:
    with pytest.raises(DomainError) as e:
        await _provider(key).register("a@b.co", "pw", "A")
    assert e.value.code == ErrorCode.DOMAIN_RULE_VIOLATION
