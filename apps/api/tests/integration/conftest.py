"""Integration tests run against a real PostgreSQL, never SQLite.

Set OMNI_TEST_DATABASE_URL to a server you can create databases on, for example
postgresql://omni:omni@localhost:5432/postgres. Tests skip when no URL is set.

Migrations run once per session into a template database; every test then gets its own
copy (`pg_url`), which takes about a second instead of starting alembic each time.
`empty_pg_url` is a blank database for the migration tests themselves.
"""

import os
import subprocess
import sys
import uuid
from collections.abc import Iterator
from pathlib import Path

import pytest
from sqlalchemy import Engine, create_engine, text

API_DIR = Path(__file__).resolve().parents[2]


def _sync(url: str) -> str:
    return (
        url.replace("postgresql://", "postgresql+psycopg://", 1) if "+psycopg" not in url else url
    )


def _base() -> str:
    base = os.environ.get("OMNI_TEST_DATABASE_URL")
    if not base:
        pytest.skip("OMNI_TEST_DATABASE_URL not set")
    return base


@pytest.fixture(scope="session")
def _admin() -> Iterator[Engine]:
    admin = create_engine(_sync(_base()), isolation_level="AUTOCOMMIT")
    yield admin
    admin.dispose()


def _url(name: str) -> str:
    prefix, _, _ = _base().rpartition("/")
    return f"{prefix}/{name}"


@pytest.fixture(scope="session")
def _template(_admin: Engine) -> Iterator[str]:
    name = f"omni_tpl_{uuid.uuid4().hex[:12]}"
    with _admin.connect() as c:
        c.execute(text(f'CREATE DATABASE "{name}"'))
    try:
        subprocess.run(
            [sys.executable, "-m", "alembic", "upgrade", "head"],
            cwd=API_DIR,
            env={**os.environ, "OMNI_MIGRATION_URL": _url(name)},
            check=True,
            timeout=300,
        )
        yield name
    finally:
        with _admin.connect() as c:
            c.execute(text(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)'))


def _throwaway(admin: Engine, template: str | None) -> Iterator[str]:
    name = f"omni_test_{uuid.uuid4().hex[:12]}"
    copy = f' TEMPLATE "{template}"' if template else ""
    with admin.connect() as c:
        c.execute(text(f'CREATE DATABASE "{name}"{copy}'))
    try:
        yield _url(name)
    finally:
        with admin.connect() as c:
            c.execute(text(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)'))


@pytest.fixture
def pg_url(_admin: Engine, _template: str) -> Iterator[str]:
    """A fresh database with every migration applied."""
    yield from _throwaway(_admin, _template)


@pytest.fixture
def empty_pg_url(_admin: Engine) -> Iterator[str]:
    """A fresh blank database, for testing the migrations themselves."""
    yield from _throwaway(_admin, None)
