from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from backend.app.config import Settings
from backend.app.main import create_app


@pytest.fixture
def api_key() -> str:
    return "test-api-key-that-is-not-a-secret"


@pytest.fixture
def client(api_key: str):
    settings = Settings(
        database_url="sqlite+pysqlite:///:memory:",
        app_api_key=api_key,
        app_env="test",
    )
    with TestClient(create_app(settings)) as test_client:
        yield test_client


@pytest.fixture
def auth_headers(api_key: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {api_key}"}
