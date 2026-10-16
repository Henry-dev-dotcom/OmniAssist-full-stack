from fastapi.testclient import TestClient

from src.main import app

client = TestClient(app)


def test_live() -> None:
    assert client.get("/api/v1/health/live").json() == {"status": "ok"}


def test_ready_reports_database_state() -> None:
    from src.infrastructure.database.session import get_session

    class _Up:
        async def execute(self, *_: object) -> None:
            return None

    class _Down:
        async def execute(self, *_: object) -> None:
            raise OSError("connection refused")

    for session, code in ((_Up(), 200), (_Down(), 503)):
        app.dependency_overrides[get_session] = lambda s=session: s
        try:
            assert client.get("/api/v1/health/ready").status_code == code
        finally:
            app.dependency_overrides.clear()


def test_cors_rejects_unlisted_origin() -> None:
    r = client.options(
        "/api/v1/health/live",
        headers={"Origin": "http://evil.test", "Access-Control-Request-Method": "GET"},
    )
    assert "access-control-allow-origin" not in r.headers


def test_security_headers() -> None:
    h = client.get("/api/v1/health/live").headers
    assert h["x-content-type-options"] == "nosniff"
    assert h["x-frame-options"] == "DENY"
    assert h["referrer-policy"] == "no-referrer"


def test_registration_can_be_turned_off(monkeypatch: object) -> None:
    from src.config import settings

    monkeypatch.setattr(settings, "allow_registration", False)  # type: ignore[attr-defined]
    r = client.post(
        "/api/v1/auth/register",
        json={"email": "a@example.com", "password": "long-enough-pw", "display_name": "A"},
    )
    assert r.status_code == 422
    assert "turned off" in r.json()["error"]["message"]
