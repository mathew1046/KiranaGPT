"""Validated inventory contracts shared by the API and ledger service."""

from __future__ import annotations

from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class InventoryItem(BaseModel):
    """The current stock state for one store item."""

    model_config = ConfigDict(str_strip_whitespace=True)

    id: str
    store_id: str
    item_name: str = Field(min_length=1, max_length=120)
    unit: str = Field(default="unit", min_length=1, max_length=24)
    quantity_on_hand: Decimal = Field(ge=0)
    low_stock_threshold: Decimal = Field(default=0, ge=0)
    last_price_inr: Decimal | None = Field(default=None, ge=0)

    @property
    def is_low_stock(self) -> bool:
        return self.quantity_on_hand <= self.low_stock_threshold


class InventoryRestock(BaseModel):
    """A manual stock addition. Restocks must always be positive."""

    model_config = ConfigDict(str_strip_whitespace=True)

    item_name: str = Field(min_length=1, max_length=120)
    quantity: Decimal = Field(gt=0)
    unit: str | None = Field(default=None, min_length=1, max_length=24)
    low_stock_threshold: Decimal | None = Field(default=None, ge=0)
    last_price_inr: Decimal | None = Field(default=None, ge=0)


class InventorySaleLine(BaseModel):
    """A confirmed structured sale line that may decrement known inventory."""

    model_config = ConfigDict(str_strip_whitespace=True)

    item_name: str = Field(min_length=1, max_length=120)
    quantity: Decimal = Field(gt=0)
    unit: str | None = Field(default=None, min_length=1, max_length=24)
    price_inr: Decimal | None = Field(default=None, ge=0)


class InventoryAdjustment(BaseModel):
    """Auditable result of one inventory operation."""

    item_id: str | None
    item_name: str
    delta_quantity: Decimal
    status: Literal["updated", "unmatched"]
    is_low_stock: bool = False


class InventoryListResponse(BaseModel):
    items: list[InventoryItem]
    low_stock_items: list[InventoryItem]


class AnalyticsLedgerEntry(BaseModel):
    """Small analytics projection; do not expose source transcripts here."""

    customer_id: str
    customer_name: str
    entry_type: Literal["credit", "payment"]
    amount: Decimal = Field(gt=0)
    items: list[InventorySaleLine] = Field(default_factory=list)
    is_reversal: bool = False

    @field_validator("customer_name")
    @classmethod
    def customer_name_is_present(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("customer_name must not be blank")
        return value
