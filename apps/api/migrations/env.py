import asyncio
import os

from alembic import context
from sqlalchemy.ext.asyncio import create_async_engine

from src.config import settings
from src.infrastructure.database.engine import async_url

config = context.config
# Tests set OMNI_MIGRATION_URL to point at a throwaway database.
URL = async_url(os.environ.get("OMNI_MIGRATION_URL", settings.database_url))


def _run(connection) -> None:  # type: ignore[no-untyped-def]
    context.configure(connection=connection, target_metadata=None)
    with context.begin_transaction():
        context.run_migrations()


async def _online() -> None:
    engine = create_async_engine(URL)
    async with engine.connect() as conn:
        await conn.run_sync(_run)
    await engine.dispose()


if context.is_offline_mode():
    context.configure(url=URL, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()
else:
    asyncio.run(_online())
