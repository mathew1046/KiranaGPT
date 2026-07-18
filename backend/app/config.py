"""Runtime configuration with no dependency on a local .env loader.

Deployment environments should inject the values directly.  This keeps secrets
out of source control and lets the same settings work in Docker, systemd, and
local development after a shell or IDE has loaded ``.env``.
"""

from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
import os
from pathlib import Path


DEFAULT_DATABASE_URL = "sqlite:///./kirana.db"
DEFAULT_DEVELOPMENT_API_KEY = "local-development-key"


class SettingsError(ValueError):
    """Raised when a configuration value is unsafe for the selected runtime."""


@dataclass(frozen=True, slots=True)
class Settings:
    """All configuration consumed by the backend core.

    ``database_url`` accepts SQLite for local use and a normal SQLAlchemy
    PostgreSQL URL in deployed environments, for example
    ``postgresql+psycopg://user:password@host/kiranagpt``.
    """

    database_url: str = DEFAULT_DATABASE_URL
    app_api_key: str = DEFAULT_DEVELOPMENT_API_KEY
    app_env: str = "development"
    openai_api_key: str | None = None
    openai_transcription_model: str = "whisper-1"
    openai_extraction_model: str = "gpt-5.4-mini"
    openai_escalation_model: str = "gpt-5.4-mini"
    openai_query_model: str = "gpt-5.4-mini"
    model_dir: Path = Path("../models")

    @classmethod
    def from_env(cls) -> "Settings":
        """Read settings from the process environment without logging secrets."""

        app_env = os.getenv("APP_ENV", "development").strip().lower() or "development"
        database_url = os.getenv("DATABASE_URL", DEFAULT_DATABASE_URL).strip()
        app_api_key = os.getenv("APP_API_KEY", DEFAULT_DEVELOPMENT_API_KEY).strip()
        openai_api_key = os.getenv("OPENAI_API_KEY") or None

        settings = cls(
            database_url=database_url,
            app_api_key=app_api_key,
            app_env=app_env,
            openai_api_key=openai_api_key,
            openai_transcription_model=os.getenv("OPENAI_TRANSCRIPTION_MODEL", "whisper-1").strip(),
            openai_extraction_model=os.getenv("OPENAI_EXTRACTION_MODEL", "gpt-5.4-mini").strip(),
            openai_escalation_model=os.getenv("OPENAI_ESCALATION_MODEL", "gpt-5.4-mini").strip(),
            openai_query_model=os.getenv("OPENAI_QUERY_MODEL", "gpt-5.4-mini").strip(),
            model_dir=Path(os.getenv("MODEL_DIR", "../models")),
        )
        settings.validate()
        return settings

    def validate(self) -> None:
        """Reject empty values and known placeholders before the app starts."""

        if not self.database_url:
            raise SettingsError("DATABASE_URL must not be empty")
        if not self.app_api_key:
            raise SettingsError("APP_API_KEY must not be empty")
        if self.app_env in {"production", "prod"} and self.app_api_key in {
            DEFAULT_DEVELOPMENT_API_KEY,
            "replace-with-a-local-demo-key",
        }:
            raise SettingsError("APP_API_KEY must be a non-default secret in production")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return process settings once; tests should pass explicit ``Settings`` instead."""

    return Settings.from_env()
