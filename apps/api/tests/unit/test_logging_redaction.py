import json
import logging

from src.infrastructure.observability.logging import (
    REDACTED,
    JsonFormatter,
    redact,
    request_id_var,
)


def _format(fields: dict[str, object]) -> dict[str, object]:
    rec = logging.LogRecord("t", logging.INFO, "f", 1, "msg", None, None)
    rec.fields = fields
    return json.loads(JsonFormatter().format(rec))  # type: ignore[no-any-return]


def test_redacts_tokens_passwords_and_research_content() -> None:
    out = _format(
        {
            "access_token": "abc",
            "password": "pw",
            "note_body": "unpublished result",
            "title": "My thesis",
            "status": "ok",
        }
    )
    assert out["access_token"] == REDACTED
    assert out["password"] == REDACTED
    assert out["note_body"] == REDACTED
    assert out["title"] == REDACTED
    assert out["status"] == "ok"


def test_redacts_nested() -> None:
    assert redact({"a": [{"refresh_token": "x"}]}) == {"a": [{"refresh_token": REDACTED}]}


def test_includes_request_id() -> None:
    token = request_id_var.set("req_123")
    try:
        assert _format({})["request_id"] == "req_123"
    finally:
        request_id_var.reset(token)
