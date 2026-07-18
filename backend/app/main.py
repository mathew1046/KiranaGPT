"""FastAPI application factory for KiranaGPT."""

from __future__ import annotations

from contextlib import asynccontextmanager
from decimal import Decimal
from typing import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select

from .config import Settings, get_settings
from .database import Database
from .inventory.schemas import AnalyticsLedgerEntry, InventorySaleLine
from .inventory.service import InMemoryInventoryRepository, InventoryService
from .models import Customer, LedgerEntry
from .routers.inventory import build_inventory_router
from .routes.core import core_router, public_router
from .routes.llm import create_llm_router
from .routers.voice import voice_router


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
    if resolved_settings.cors_allow_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=list(resolved_settings.cors_allow_origins),
            allow_credentials=False,
            allow_methods=["GET", "POST", "OPTIONS"],
            allow_headers=["Accept", "Content-Type"],
        )
    app.state.settings = resolved_settings
    app.state.database = database
    inventory_service = InventoryService(InMemoryInventoryRepository())
    app.state.inventory_service = inventory_service

    def default_store_id() -> str:
        return "default-store"

    def load_daily_entries(
        _store_id: str, start_date: str | None, end_date: str | None
    ) -> list[AnalyticsLedgerEntry]:
        """Project immutable ledger rows into the analytics service contract."""

        del start_date, end_date  # Date-range filtering is added with store persistence.
        with database.session_factory() as session:
            rows = session.execute(
                select(LedgerEntry, Customer).join(Customer, Customer.id == LedgerEntry.customer_id)
            ).all()
        projections: list[AnalyticsLedgerEntry] = []
        for entry, customer in rows:
            attributes = entry.attributes or {}
            quantity = attributes.get("quantity")
            line_items = (
                [
                    InventorySaleLine(
                        item_name=str(attributes.get("item_name")),
                        quantity=Decimal(str(quantity)),
                        unit=attributes.get("unit"),
                    )
                ]
                if attributes.get("item_name") and quantity is not None
                else []
            )
            projections.append(
                AnalyticsLedgerEntry(
                    customer_id=str(customer.id),
                    customer_name=customer.display_name,
                    entry_type="credit" if entry.amount >= 0 else "payment",
                    amount=abs(Decimal(entry.amount)),
                    items=line_items,
                    is_reversal=entry.reversal_of_id is not None,
                )
            )
        return projections

    app.include_router(public_router)
    app.include_router(core_router)
    app.include_router(create_llm_router())
    app.include_router(voice_router)
    app.include_router(
        build_inventory_router(inventory_service, default_store_id, load_daily_entries)
    )
    return app


app = create_app()
