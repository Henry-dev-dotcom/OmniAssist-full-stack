import uuid
from dataclasses import dataclass
from functools import lru_cache
from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from src.auth.local_provider import LocalProvider
from src.auth.provider import AuthProvider, OidcProvider, unauthenticated
from src.config import settings
from src.domain.users import repository as users
from src.infrastructure.database.session import SessionFactory, get_session


@dataclass(frozen=True)
class Actor:
    user_id: uuid.UUID
    email: str


@lru_cache
def get_provider() -> AuthProvider:
    if settings.auth_provider == "local":
        return LocalProvider(secret=settings.auth_local_secret, sessions=SessionFactory)
    return OidcProvider(
        issuer=settings.auth_issuer,
        audience=settings.auth_audience,
        client_id=settings.auth_client_id,
        client_secret=settings.auth_client_secret,
    )


Session = Annotated[AsyncSession, Depends(get_session)]
Provider = Annotated[AuthProvider, Depends(get_provider)]


async def current_actor(request: Request, session: Session, provider: Provider) -> Actor:
    header = request.headers.get("Authorization", "")
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise unauthenticated()
    identity = await provider.verify_access_token(token)
    user = await users.upsert_by_subject(session, identity)
    return Actor(user_id=user["id"], email=user["email"])


CurrentActor = Annotated[Actor, Depends(current_actor)]
