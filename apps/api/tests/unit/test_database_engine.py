from sqlalchemy.dialects.postgresql.asyncpg import PGDialect_asyncpg
from sqlalchemy.engine import make_url

from src.infrastructure.database.engine import async_url


def test_neon_tls_parameters_are_normalized_for_asyncpg() -> None:
    url = async_url(
        "postgresql://user:pass@host/db?channel_binding=require&sslmode=require&application_name=omni"
    )
    parsed = make_url(url)
    assert parsed.drivername == "postgresql+asyncpg"
    assert parsed.query == {"ssl": "require", "application_name": "omni"}

    driver_options = PGDialect_asyncpg().create_connect_args(parsed)[1]
    assert driver_options["ssl"] == "require"
    assert "sslmode" not in driver_options
    assert "channel_binding" not in driver_options
