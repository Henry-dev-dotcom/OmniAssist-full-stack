from typing import Any

from fastapi import APIRouter, Request
from pydantic import BaseModel, EmailStr, Field

from src.api.responses import envelope
from src.auth.dependencies import CurrentActor, Provider, Session
from src.auth.local_provider import LocalProvider
from src.auth.provider import AuthSession
from src.config import settings
from src.domain.common.errors import DomainError, ErrorCode
from src.domain.users import repository as users

router = APIRouter(prefix="/auth", tags=["auth"])


class Credentials(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=256)


class RegisterBody(Credentials):
    display_name: str = Field(min_length=1, max_length=120)


class RefreshBody(BaseModel):
    refresh_token: str = Field(min_length=1)


def _session(s: AuthSession) -> dict[str, Any]:
    return {
        "access_token": s.access_token,
        "refresh_token": s.refresh_token,
        "expires_in": s.expires_in,
    }


@router.post("/register")
async def register(body: RegisterBody, request: Request, provider: Provider) -> dict[str, Any]:
    if not settings.allow_registration:
        raise DomainError(
            ErrorCode.DOMAIN_RULE_VIOLATION, "Creating accounts is turned off on this server."
        )
    s = await provider.register(body.email, body.password, body.display_name)
    return envelope(request, _session(s))


@router.post("/login")
async def login(body: Credentials, request: Request, provider: Provider) -> dict[str, Any]:
    return envelope(request, _session(await provider.login(body.email, body.password)))


@router.post("/refresh")
async def refresh(body: RefreshBody, request: Request, provider: Provider) -> dict[str, Any]:
    return envelope(request, _session(await provider.refresh(body.refresh_token)))


@router.post("/logout")
async def logout(
    body: RefreshBody, request: Request, provider: Provider, _actor: CurrentActor
) -> dict[str, Any]:
    await provider.logout(body.refresh_token)
    return envelope(request, {"signed_out": True})


class PasswordChange(BaseModel):
    current_password: str = Field(min_length=1, max_length=256)
    new_password: str = Field(min_length=1, max_length=256)


@router.post("/change-password")
async def change_password(
    body: PasswordChange,
    request: Request,
    provider: Provider,
    actor: CurrentActor,
    session: Session,
) -> dict[str, Any]:
    """Built-in sign-in only; a hosted provider manages passwords itself (Spec 4.1)."""
    if not isinstance(provider, LocalProvider):
        raise DomainError(
            ErrorCode.DOMAIN_RULE_VIOLATION, "Change your password with your sign-in provider."
        )
    subject = await users.subject_of(session, actor.user_id)
    if subject is None:
        raise DomainError(ErrorCode.UNAUTHENTICATED, "Sign in again.")
    s = await provider.change_password(subject, body.current_password, body.new_password)
    return envelope(request, _session(s))
