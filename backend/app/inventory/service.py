"""Append-only inventory bookkeeping independent of database implementation."""

from __future__ import annotations

from collections.abc import Iterable
from decimal import Decimal
from typing import Protocol
from uuid import uuid4

from .schemas import (
    InventoryAdjustment,
    InventoryItem,
    InventoryListResponse,
    InventoryRestock,
    InventorySaleLine,
)


def _normalized_name(item_name: str) -> str:
    return " ".join(item_name.casefold().split())


class InventoryRepository(Protocol):
    def get_by_name(self, store_id: str, item_name: str) -> InventoryItem | None: ...

    def save(self, item: InventoryItem) -> InventoryItem: ...

    def list_for_store(self, store_id: str) -> list[InventoryItem]: ...

    def record_transaction(
        self,
        *,
        store_id: str,
        item_id: str,
        ledger_entry_id: str | None,
        delta_quantity: Decimal,
    ) -> None: ...


class InMemoryInventoryRepository:
    """Small deterministic repository for tests and offline demonstrations."""

    def __init__(self) -> None:
        self._items: dict[str, InventoryItem] = {}
        self.transactions: list[dict[str, object]] = []

    def get_by_name(self, store_id: str, item_name: str) -> InventoryItem | None:
        normalized = _normalized_name(item_name)
        for item in self._items.values():
            if item.store_id == store_id and _normalized_name(item.item_name) == normalized:
                return item.model_copy(deep=True)
        return None

    def save(self, item: InventoryItem) -> InventoryItem:
        self._items[item.id] = item.model_copy(deep=True)
        return item.model_copy(deep=True)

    def list_for_store(self, store_id: str) -> list[InventoryItem]:
        return [
            item.model_copy(deep=True)
            for item in self._items.values()
            if item.store_id == store_id
        ]

    def record_transaction(
        self,
        *,
        store_id: str,
        item_id: str,
        ledger_entry_id: str | None,
        delta_quantity: Decimal,
    ) -> None:
        self.transactions.append(
            {
                "store_id": store_id,
                "item_id": item_id,
                "ledger_entry_id": ledger_entry_id,
                "delta_quantity": delta_quantity,
            }
        )


class InventoryService:
    """Updates stock only after confirmed ledger sales are supplied.

    Unknown inventory items intentionally return an ``unmatched`` adjustment instead
    of blocking a confirmed ledger entry. This keeps the ledger authoritative while
    giving the UI a visible inventory follow-up.
    """

    def __init__(self, repository: InventoryRepository) -> None:
        self._repository = repository

    def restock(self, store_id: str, payload: InventoryRestock) -> InventoryItem:
        existing = self._repository.get_by_name(store_id, payload.item_name)
        if existing is None:
            item = InventoryItem(
                id=str(uuid4()),
                store_id=store_id,
                item_name=payload.item_name,
                unit=payload.unit or "unit",
                quantity_on_hand=payload.quantity,
                low_stock_threshold=payload.low_stock_threshold or Decimal("0"),
                last_price_inr=payload.last_price_inr,
            )
        else:
            item = existing.model_copy(
                update={
                    "quantity_on_hand": existing.quantity_on_hand + payload.quantity,
                    "unit": payload.unit or existing.unit,
                    "low_stock_threshold": (
                        payload.low_stock_threshold
                        if payload.low_stock_threshold is not None
                        else existing.low_stock_threshold
                    ),
                    "last_price_inr": (
                        payload.last_price_inr
                        if payload.last_price_inr is not None
                        else existing.last_price_inr
                    ),
                }
            )
        saved = self._repository.save(item)
        self._repository.record_transaction(
            store_id=store_id,
            item_id=saved.id,
            ledger_entry_id=None,
            delta_quantity=payload.quantity,
        )
        return saved

    def apply_confirmed_sale(
        self,
        store_id: str,
        ledger_entry_id: str,
        lines: Iterable[InventorySaleLine],
    ) -> list[InventoryAdjustment]:
        adjustments: list[InventoryAdjustment] = []
        for line in lines:
            item = self._repository.get_by_name(store_id, line.item_name)
            if item is None:
                adjustments.append(
                    InventoryAdjustment(
                        item_id=None,
                        item_name=line.item_name,
                        delta_quantity=-line.quantity,
                        status="unmatched",
                    )
                )
                continue

            # Do not permit negative stock silently. We deduct only what is on hand;
            # the shortfall stays visible through low-stock state rather than corrupting
            # inventory arithmetic.
            actual_deduction = min(item.quantity_on_hand, line.quantity)
            updated = item.model_copy(
                update={
                    "quantity_on_hand": item.quantity_on_hand - actual_deduction,
                    "last_price_inr": line.price_inr or item.last_price_inr,
                }
            )
            saved = self._repository.save(updated)
            self._repository.record_transaction(
                store_id=store_id,
                item_id=saved.id,
                ledger_entry_id=ledger_entry_id,
                delta_quantity=-actual_deduction,
            )
            adjustments.append(
                InventoryAdjustment(
                    item_id=saved.id,
                    item_name=saved.item_name,
                    delta_quantity=-actual_deduction,
                    status="updated",
                    is_low_stock=saved.is_low_stock,
                )
            )
        return adjustments

    def list_inventory(self, store_id: str) -> InventoryListResponse:
        items = sorted(
            self._repository.list_for_store(store_id), key=lambda item: item.item_name.casefold()
        )
        return InventoryListResponse(
            items=items,
            low_stock_items=[item for item in items if item.is_low_stock],
        )
