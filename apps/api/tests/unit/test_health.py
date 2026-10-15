from fastapi.testclient import TestClient

from src.main import app

client = TestClient(app)


def test_live() -> None:
    assert client.get("/api/v1/health/live").json() == {"status": "ok"}


def test_ready() -> None:
    assert client.get("/api/v1/health/ready").status_code == 200


def test_cors_rejects_unlisted_origin() -> None:
    r = client.options(
        "/api/v1/health/live",
        headers={"Origin": "http://evil.test", "Access-Control-Request-Method": "GET"},
    )
    assert "access-control-allow-origin" not in r.headers
