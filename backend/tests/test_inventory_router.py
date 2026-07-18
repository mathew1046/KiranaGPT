from decimal import Decimal

import pytest
from fastapi import FastAPI, Header, HTTPException, status
from fastapi.testclient import TestClient

from backend.app.inventory.schemas import AnalyticsLedgerEntry, InventorySaleLine
from backend.app.inventory.service import InMemoryInventoryRepository, InventoryService
from backend.app.routers.inventory import build_inventory_router


def _client() -> TestClient:
    app = FastAPI()
    service = InventoryService(InMemoryInventoryRepository())

    def require_store_id(authorization: str | None = Header(default=None)) -> str:
        if authorization != "Bearer test-api-key":
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED)
        return "store-1"

    def load_daily_entries(
        store_id: str, start_date: str | None, end_date: str | None
    ) -> list[AnalyticsLedgerEntry]:
        assert store_id == "store-1"
        return [
            AnalyticsLedgerEntry(
                customer_id="ramesh",
                customer_name="Ramesh",
                entry_type="credit",
                amount=Decimal("120"),
                items=[InventorySaleLine(item_name="rice", quantity=Decimal("2"))],
            )
        ]

    app.include_router(build_inventory_router(service, require_store_id, load_daily_entries))
    return TestClient(app)


def test_inventory_routes_happy_paths() -> None:
    client = _client()
    headers = {"Authorization": "Bearer test-api-key"}

    restock = client.post(
        "/v1/inventory/restock",
        headers=headers,
        json={
            "item_name": "Rice",
            "quantity": "8",
            "unit": "kg",
            "low_stock_threshold": "2",
        },
    )
    inventory = client.get("/v1/inventory", headers=headers)
    analytics = client.get("/v1/analytics/daily?start_date=2026-07-19", headers=headers)

    assert restock.status_code == 201
    assert inventory.status_code == 200
    assert inventory.json()["items"][0]["quantity_on_hand"] == "8"
    assert analytics.status_code == 200
    assert analytics.json()["revenue_inr"] == "120"


def test_restock_route_rejects_invalid_schema() -> None:
    response = _client().post(
        "/v1/inventory/restock",
        headers={"Authorization": "Bearer test-api-key"},
        json={"item_name": "Rice", "quantity": 0},
    )

    assert response.status_code == 422


@pytest.mark.parametrize(
    ("method", "path", "body"),
    [
        ("get", "/v1/inventory", None),
        ("post", "/v1/inventory/restock", {"item_name": "Rice", "quantity": 1}),
        ("get", "/v1/analytics/daily", None),
    ],
)
def test_inventory_routes_reject_missing_or_invalid_auth(
    method: str, path: str, body: dict[str, object] | None
) -> None:
    request = getattr(_client(), method)
    response = request(path, json=body) if body is not None else request(path)

    assert response.status_code == 401
