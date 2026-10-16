import re
from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient

from src.api.dependencies import request_id_middleware
from src.api.error_handlers import register_error_handlers
from src.domain.common.errors import HTTP_STATUS, DomainError, ErrorCode

ROOT = Path(__file__).resolve().parents[4]
DOC = (ROOT / "packages/contracts/error_codes.md").read_text()
ARCHIVED_DART = (ROOT / "apps/client-flutter-archive/lib/core/errors/error_codes.dart").read_text()


def _documented() -> set[str]:
    return set(re.findall(r"^\| `([A-Z_]+)` \|", DOC, re.MULTILINE))


def test_every_code_is_documented_and_vice_versa() -> None:
    assert {c.value for c in ErrorCode} == _documented()


def test_client_uses_same_names() -> None:
    dart = set(re.findall(r"\('([A-Z_]+)'\)", ARCHIVED_DART))
    assert dart == {c.value for c in ErrorCode}


def test_every_code_has_http_status() -> None:
    assert set(HTTP_STATUS) == set(ErrorCode)


def _app() -> TestClient:
    app = FastAPI()
    app.middleware("http")(request_id_middleware)
    register_error_handlers(app)

    @app.get("/domain")
    def domain() -> None:
        raise DomainError(ErrorCode.FORBIDDEN, "Not authorized.")

    @app.get("/boom")
    def boom() -> None:
        raise RuntimeError("secret internals")

    @app.get("/typed/{n}")
    def typed(n: int) -> int:
        return n

    return TestClient(app, raise_server_exceptions=False)


def test_envelope_has_code_and_request_id() -> None:
    r = _app().get("/domain")
    body = r.json()["error"]
    assert r.status_code == 403
    assert body["code"] == "FORBIDDEN"
    assert body["request_id"] == r.headers["X-Request-ID"]
    assert body["retryable"] is False


def test_validation_error_lists_fields() -> None:
    r = _app().get("/typed/abc")
    assert r.status_code == 400
    assert r.json()["error"]["details"]["fields"][0]["field"] == "path.n"


def test_unhandled_error_hides_internals() -> None:
    r = _app().get("/boom")
    assert r.status_code == 500
    assert "secret" not in r.text
    assert r.json()["error"]["retryable"] is True


def test_unknown_route_is_not_found_code() -> None:
    assert _app().get("/nope").json()["error"]["code"] == "NOT_FOUND"
