"""Factory for authenticated inventory and analytics routes.

The backend core wires this factory with its persistent repository and auth
dependency. Keeping it as a factory avoids hidden global state during tests.
"""

from __future__ import annotations

from collections.abc import Callable
from fastapi import APIRouter, Depends, Query

from ..inventory.analytics import DailyAnalytics, build_daily_analytics
from ..inventory.schemas import (
    AnalyticsLedgerEntry,
    InventoryItem,
    InventoryListResponse,
    InventoryRestock,
)
from ..inventory.service import InventoryService


def build_inventory_router(
    inventory_service: InventoryService,
    require_store_id: Callable[..., str],
    load_daily_entries: Callable[[str, str | None, str | None], list[AnalyticsLedgerEntry]],
) -> APIRouter:
    """Return the inventory router with injected persistence/auth hooks."""

    router = APIRouter(prefix="/v1", tags=["inventory"])

    @router.get("/inventory", response_model=InventoryListResponse)
    def get_inventory(store_id: str = Depends(require_store_id)) -> InventoryListResponse:
        return inventory_service.list_inventory(store_id)

    @router.post("/inventory/restock", response_model=InventoryItem, status_code=201)
    def restock_inventory(
        payload: InventoryRestock,
        store_id: str = Depends(require_store_id),
    ) -> InventoryItem:
        return inventory_service.restock(store_id, payload)

    @router.get("/analytics/daily", response_model=DailyAnalytics)
    def get_daily_analytics(
        store_id: str = Depends(require_store_id),
        start_date: str | None = Query(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$"),
        end_date: str | None = Query(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$"),
    ) -> DailyAnalytics:
        return build_daily_analytics(load_daily_entries(store_id, start_date, end_date))

    return router
