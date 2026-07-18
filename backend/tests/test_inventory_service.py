from decimal import Decimal

import pytest
from pydantic import ValidationError

from backend.app.inventory.analytics import build_daily_analytics
from backend.app.inventory.schemas import AnalyticsLedgerEntry, InventoryRestock, InventorySaleLine
from backend.app.inventory.service import InMemoryInventoryRepository, InventoryService


def test_restock_then_confirmed_sale_updates_stock_and_low_stock_state() -> None:
    repository = InMemoryInventoryRepository()
    service = InventoryService(repository)

    restocked = service.restock(
        "store-1",
        InventoryRestock(
            item_name="Ariyu",
            quantity=Decimal("10"),
            unit="kg",
            low_stock_threshold=Decimal("3"),
        ),
    )
    adjustments = service.apply_confirmed_sale(
        "store-1",
        "entry-1",
        [InventorySaleLine(item_name="ariyu", quantity=Decimal("7"), unit="kg")],
    )

    inventory = service.list_inventory("store-1")
    assert restocked.quantity_on_hand == Decimal("10")
    assert adjustments[0].status == "updated"
    assert adjustments[0].delta_quantity == Decimal("-7")
    assert adjustments[0].is_low_stock is True
    assert inventory.items[0].quantity_on_hand == Decimal("3")
    assert len(repository.transactions) == 2


def test_unknown_sale_line_is_visible_but_does_not_block_the_ledger() -> None:
    service = InventoryService(InMemoryInventoryRepository())

    adjustments = service.apply_confirmed_sale(
        "store-1",
        "entry-1",
        [InventorySaleLine(item_name="unregistered tea", quantity=Decimal("1"))],
    )

    assert adjustments[0].status == "unmatched"
    assert adjustments[0].item_id is None


def test_restock_schema_rejects_negative_inventory() -> None:
    with pytest.raises(ValidationError):
        InventoryRestock(item_name="rice", quantity=Decimal("-1"))


def test_analytics_respects_payments_and_append_only_reversal_entries() -> None:
    analytics = build_daily_analytics(
        [
            AnalyticsLedgerEntry(
                customer_id="ramesh",
                customer_name="Ramesh",
                entry_type="credit",
                amount=Decimal("100"),
                items=[InventorySaleLine(item_name="rice", quantity=Decimal("2"))],
            ),
            AnalyticsLedgerEntry(
                customer_id="ramesh",
                customer_name="Ramesh",
                entry_type="payment",
                amount=Decimal("30"),
            ),
            AnalyticsLedgerEntry(
                customer_id="sita",
                customer_name="Sita",
                entry_type="credit",
                amount=Decimal("50"),
                items=[InventorySaleLine(item_name="tea", quantity=Decimal("1"))],
            ),
            AnalyticsLedgerEntry(
                customer_id="sita",
                customer_name="Sita",
                entry_type="credit",
                amount=Decimal("20"),
                items=[InventorySaleLine(item_name="tea", quantity=Decimal("1"))],
                is_reversal=True,
            ),
        ]
    )

    assert analytics.revenue_inr == Decimal("130")
    assert analytics.payments_received_inr == Decimal("30")
    assert [(debtor.customer_name, debtor.balance) for debtor in analytics.top_debtors] == [
        ("Ramesh", Decimal("70")),
        ("Sita", Decimal("30")),
    ]
    assert [(item.item_name, item.quantity) for item in analytics.top_items] == [
        ("rice", Decimal("2")),
    ]
