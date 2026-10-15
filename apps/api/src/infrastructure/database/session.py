from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from src.config import settings
from src.infrastructure.database.engine import make_engine

engine = make_engine(settings.database_url)
SessionFactory = async_sessionmaker(engine, expire_on_commit=False)


async def get_session() -> AsyncIterator[AsyncSession]:
    """FastAPI dependency. Write routes call `await session.commit()` themselves, so the
    commit is finished before the response is sent. An unhandled error rolls back."""
    async with SessionFactory() as session:
        yield session
