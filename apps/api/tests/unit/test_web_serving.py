from fastapi.testclient import TestClient

from src.main import app


def test_api_does_not_serve_frontend_files() -> None:
    client = TestClient(app)

    assert client.get("/").status_code == 404
    assert client.get("/index.html").status_code == 404
