from typing import Any

from fastapi import APIRouter, Request
from pydantic import BaseModel, Field, field_validator

from src.api.responses import envelope
from src.auth.dependencies import CurrentActor, Session
from src.domain.notifications import service
from src.domain.users import repository

router = APIRouter(tags=["users"])


class ProfileUpdate(BaseModel):
    display_name: str | None = Field(default=None, min_length=1, max_length=120)
    timezone: str | None = None
    preferences: dict[str, Any] | None = None

    @field_validator("timezone")
    @classmethod
    def _iana(cls, v: str | None) -> str | None:
        if v is None:
            return v
        from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

        try:
            ZoneInfo(v)
        except (ZoneInfoNotFoundError, ValueError):
            raise ValueError("unknown IANA time zone") from None
        return v

    @field_validator("preferences")
    @classmethod
    def _notification_prefs(cls, v: dict[str, Any] | None) -> dict[str, Any] | None:
        if v is not None:
            service.validate_preferences(v)
        return v


def _user_out(u: dict[str, Any]) -> dict[str, Any]:
    return {k: (str(v) if k == "id" else v) for k, v in u.items()}


@router.get("/me")
async def get_me(request: Request, actor: CurrentActor, session: Session) -> dict[str, Any]:
    row = await repository.update_profile(session, actor.user_id, {})
    return envelope(request, _user_out(row))


@router.patch("/me")
async def patch_me(
    body: ProfileUpdate, request: Request, actor: CurrentActor, session: Session
) -> dict[str, Any]:
    row = await repository.update_profile(
        session, actor.user_id, body.model_dump(exclude_unset=True)
    )
    return envelope(request, _user_out(row))
