from typing import Literal, Self

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

_DEV_DB = "postgresql://omni:omni@localhost:5432/omniassist"
_DEV_AUTH_SECRET = "dev-only-signing-secret-never-use-in-production"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="OMNI_", env_file=".env", extra="ignore")

    env: str = "development"
    log_level: str = "INFO"
    database_url: str = _DEV_DB
    redis_url: str = "redis://localhost:6379/0"
    auth_provider: Literal["local", "oidc"] = "local"  # decision 0002
    auth_local_secret: str = _DEV_AUTH_SECRET
    auth_issuer: str = ""
    auth_audience: str = ""
    auth_client_id: str = ""
    auth_client_secret: str = ""
    cors_origins: list[str] = []
    # Personal use: create your account, then set this to false so nobody else can.
    allow_registration: bool = True
    export_link_ttl_minutes: int = 60  # download links expire (Spec 4.11)
    # Folder holding the built web app (apps/client/build/web). When set, the API serves the
    # app too, so one address and one process run everything (decision 0007).
    web_dir: str = ""
    # Web push (decision 0006). Empty keys: reminders show in the in-app center only.
    vapid_private_key: str = ""
    vapid_public_key: str = ""
    vapid_subject: str = "mailto:admin@example.com"

    @model_validator(mode="after")
    def _require_production_config(self) -> Self:
        if self.env != "production":
            return self
        missing = []
        if self.database_url == _DEV_DB:
            missing.append("OMNI_DATABASE_URL (still the development default)")
        if self.auth_provider == "oidc":
            for name in ("auth_issuer", "auth_audience", "auth_client_id"):
                if not getattr(self, name):
                    missing.append("OMNI_" + name.upper())
        elif self.auth_local_secret == _DEV_AUTH_SECRET or len(self.auth_local_secret) < 32:
            missing.append("OMNI_AUTH_LOCAL_SECRET (32+ random characters)")
        if not self.cors_origins:
            missing.append("OMNI_CORS_ORIGINS")
        if missing:
            raise ValueError("Missing production configuration: " + ", ".join(missing))
        return self


settings = Settings()
