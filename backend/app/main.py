"""FastAPI application factory for KiranaGPT."""

from __future__ import annotations

from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI

from .config import Settings, get_settings
from .database import Database
from .routes.core import protected_router, public_router


def create_app(settings: Settings | None = None) -> FastAPI:
    """Create an app instance with isolated settings and database ownership."""

    resolved_settings = settings or get_settings()
    database = Database(resolved_settings.database_url)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        app.state.database.create_schema()
        yield
        app.state.database.dispose()

    app = FastAPI(
        title="KiranaGPT API",
        version="0.1.0",
        description="Offline-tolerant Kirana ledger backend. Raw audio is never persisted.",
        lifespan=lifespan,
    )
    app.state.settings = resolved_settings
    app.state.database = database
    app.include_router(public_router)
    app.include_router(protected_router)
    return app


app = create_app()
