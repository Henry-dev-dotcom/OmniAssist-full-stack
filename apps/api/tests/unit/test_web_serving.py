from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient

from src.main import _AppFiles


def test_app_files_are_served_fresh_and_api_routes_win(tmp_path: Path) -> None:
    (tmp_path / "index.html").write_text("<html>app</html>")
    (tmp_path / "sqlite3.wasm").write_bytes(b"\0asm")
    app = FastAPI()

    @app.get("/api/v1/ping")
    def ping() -> dict[str, str]:
        return {"pong": "yes"}

    app.mount("/", _AppFiles(directory=tmp_path, html=True), name="web")
    c = TestClient(app)

    assert c.get("/api/v1/ping").json() == {"pong": "yes"}  # mounted last, so API first
    page = c.get("/")
    assert page.text == "<html>app</html>"
    assert page.headers["cache-control"] == "no-cache"
    wasm = c.get("/sqlite3.wasm")
    assert wasm.headers["content-type"] == "application/wasm"  # browsers refuse it otherwise
    assert c.get("/missing.js").status_code == 404
