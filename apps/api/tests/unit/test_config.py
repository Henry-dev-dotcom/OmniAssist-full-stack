import pytest
from pydantic import ValidationError

from src.config import Settings


def test_development_defaults() -> None:
    s = Settings(_env_file=None)
    assert s.env == "development"


def test_env_override(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OMNI_LOG_LEVEL", "DEBUG")
    assert Settings(_env_file=None).log_level == "DEBUG"


def test_production_requires_config() -> None:
    with pytest.raises(ValidationError) as e:
        Settings(_env_file=None, env="production")
    msg = str(e.value)
    assert "OMNI_DATABASE_URL" in msg
    assert "OMNI_AUTH_LOCAL_SECRET" in msg  # the dev signing secret is refused
    assert "OMNI_CORS_ORIGINS" in msg


def test_production_oidc_requires_provider_config() -> None:
    with pytest.raises(ValidationError) as e:
        Settings(_env_file=None, env="production", auth_provider="oidc")
    assert "OMNI_AUTH_ISSUER" in str(e.value)


def test_production_local_valid() -> None:
    s = Settings(
        _env_file=None,
        env="production",
        database_url="postgresql://u:p@db/prod",
        auth_local_secret="x" * 40,
        cors_origins=["https://app.example.com"],
    )
    assert s.auth_provider == "local"


def test_production_valid() -> None:
    s = Settings(
        _env_file=None,
        env="production",
        database_url="postgresql://u:p@db/prod",
        auth_provider="oidc",
        auth_issuer="https://auth.example.com",
        auth_audience="omniassist-api",
        auth_client_id="omniassist-app",
        cors_origins=["https://app.example.com"],
    )
    assert s.env == "production"
