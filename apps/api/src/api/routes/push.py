from typing import Any

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field, HttpUrl
from sqlalchemy import text

from src.api.responses import envelope
from src.auth.dependencies import CurrentActor, Session
from src.config import settings
from src.domain.common.errors import DomainError, ErrorCode

router = APIRouter(prefix="/push", tags=["push"])


class Keys(BaseModel):
    p256dh: str = Field(min_length=1, max_length=200)
    auth: str = Field(min_length=1, max_length=100)


class SubscriptionIn(BaseModel):
    """Exactly what the browser's PushSubscription.toJSON() returns."""

    endpoint: HttpUrl
    keys: Keys


class EndpointIn(BaseModel):
    endpoint: HttpUrl


@router.get("/public-key")
async def public_key(request: Request, actor: CurrentActor) -> dict[str, Any]:
    if not settings.vapid_public_key:
        raise DomainError(ErrorCode.NOT_FOUND, "Push notifications are not set up on this server.")
    return envelope(request, {"public_key": settings.vapid_public_key})


@router.post("/subscriptions")
async def subscribe(
    body: SubscriptionIn, request: Request, actor: CurrentActor, session: Session
) -> dict[str, Any]:
    if body.endpoint.scheme != "https":
        raise DomainError(ErrorCode.VALIDATION_ERROR, "Push endpoints must use https.")
    # One row per device; signing in as someone else on that device takes it over.
    await session.execute(
        text(
            """INSERT INTO push_subscriptions (endpoint, user_id, p256dh, auth)
            VALUES (:e, :u, :p, :a)
            ON CONFLICT (endpoint) DO UPDATE SET user_id = EXCLUDED.user_id,
              p256dh = EXCLUDED.p256dh, auth = EXCLUDED.auth"""
        ),
        {"e": str(body.endpoint), "u": actor.user_id, "p": body.keys.p256dh,
         "a": body.keys.auth},
    )  # fmt: skip
    await session.commit()
    return envelope(request, {"subscribed": True})


@router.post("/subscriptions/remove")
async def unsubscribe(
    body: EndpointIn, request: Request, actor: CurrentActor, session: Session
) -> dict[str, Any]:
    await session.execute(
        text("DELETE FROM push_subscriptions WHERE endpoint = :e AND user_id = :u"),
        {"e": str(body.endpoint), "u": actor.user_id},
    )
    await session.commit()
    return envelope(request, {"subscribed": False})
