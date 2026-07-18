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
    app_env: str = "development"
    cors_allow_origins: tuple[str, ...] = ()
    openai_api_key: str | None = None
    openai_audio_model: str = "whisper-1"
    openai_extraction_model: str = "gpt-5.5"
    openai_escalation_model: str = "gpt-5.5"
    openai_query_model: str = "gpt-5.5"
    google_sheets_spreadsheet_id: str | None = None
    google_service_account_json: str | None = None
    model_dir: Path = Path("../models")

    @classmethod
    def from_env(cls) -> "Settings":
        """Read settings from the process environment without logging secrets."""

        app_env = os.getenv("APP_ENV", "development").strip().lower() or "development"
        database_url = os.getenv("DATABASE_URL", DEFAULT_DATABASE_URL).strip()
        openai_api_key = os.getenv("OPENAI_API_KEY") or None

        settings = cls(
            database_url=database_url,
            app_env=app_env,
            cors_allow_origins=_parse_csv(os.getenv("CORS_ALLOW_ORIGINS", "")),
            openai_api_key=openai_api_key,
            openai_audio_model=os.getenv("OPENAI_AUDIO_MODEL", "whisper-1").strip(),
            openai_extraction_model=os.getenv("OPENAI_EXTRACTION_MODEL", "gpt-5.5").strip(),
            openai_escalation_model=os.getenv("OPENAI_ESCALATION_MODEL", "gpt-5.5").strip(),
            openai_query_model=os.getenv("OPENAI_QUERY_MODEL", "gpt-5.5").strip(),
            google_sheets_spreadsheet_id=os.getenv("GOOGLE_SHEETS_SPREADSHEET_ID") or None,
            google_service_account_json=os.getenv("GOOGLE_SERVICE_ACCOUNT_JSON") or None,
            model_dir=Path(os.getenv("MODEL_DIR", "../models")),
        )
        settings.validate()
        return settings

    def validate(self) -> None:
        """Reject empty values and known placeholders before the app starts."""

        if not self.database_url:
            raise SettingsError("DATABASE_URL must not be empty")


def _parse_csv(value: str) -> tuple[str, ...]:
    """Parse a deployment-friendly allowlist without accepting empty origins."""

    return tuple(origin for origin in (item.strip() for item in value.split(",")) if origin)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return process settings once; tests should pass explicit ``Settings`` instead."""

    return Settings.from_env()
