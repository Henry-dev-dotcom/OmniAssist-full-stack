"""Integration tests run against a real PostgreSQL, never SQLite.

Set OMNI_TEST_DATABASE_URL to a server you can create databases on, for example
`make up` then postgresql://omni:omni@localhost:5432/postgres. Each test gets a fresh
throwaway database that is dropped afterwards. Tests skip when no URL is set.
"""

import os
import uuid
from collections.abc import Iterator

import pytest
from sqlalchemy import create_engine, text


def _sync(url: str) -> str:
    return (
        url.replace("postgresql://", "postgresql+psycopg://", 1) if "+psycopg" not in url else url
    )


@pytest.fixture
def pg_url() -> Iterator[str]:
    base = os.environ.get("OMNI_TEST_DATABASE_URL")
    if not base:
        pytest.skip("OMNI_TEST_DATABASE_URL not set")
    name = f"omni_test_{uuid.uuid4().hex[:12]}"
    admin = create_engine(_sync(base), isolation_level="AUTOCOMMIT")
    with admin.connect() as c:
        c.execute(text(f'CREATE DATABASE "{name}"'))
    prefix, _, _ = base.rpartition("/")
    try:
        yield f"{prefix}/{name}"
    finally:
        with admin.connect() as c:
            c.execute(text(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)'))
        admin.dispose()
