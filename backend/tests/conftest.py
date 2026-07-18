from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from backend.app.config import Settings
from backend.app.main import create_app


@pytest.fixture
def client():
    settings = Settings(
        database_url="sqlite+pysqlite:///:memory:",
        app_env="test",
    )
    with TestClient(create_app(settings)) as test_client:
        yield test_client
