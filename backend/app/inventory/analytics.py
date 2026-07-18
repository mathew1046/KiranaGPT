"""Pure, auditable daily analytics built from immutable ledger projections."""

from __future__ import annotations

from collections import defaultdict
from decimal import Decimal

from pydantic import BaseModel, Field

from .schemas import AnalyticsLedgerEntry


class TopItem(BaseModel):
    item_name: str
    quantity: Decimal = Field(ge=0)


class Debtor(BaseModel):
    customer_id: str
    customer_name: str
    balance: Decimal = Field(ge=0)


class DailyAnalytics(BaseModel):
    revenue_inr: Decimal = Field(ge=0)
    payments_received_inr: Decimal = Field(ge=0)
    top_items: list[TopItem]
    top_debtors: list[Debtor]


def build_daily_analytics(entries: list[AnalyticsLedgerEntry]) -> DailyAnalytics:
    """Build a daily snapshot without ever mutating ledger data.

    An offsetting correction is represented by an immutable reversal entry. It
    negates its entry type's contribution to revenue/payment/customer balance.
    """

    revenue = Decimal("0")
    payments = Decimal("0")
    balances: dict[str, Decimal] = defaultdict(lambda: Decimal("0"))
    customer_names: dict[str, str] = {}
    item_quantities: dict[str, Decimal] = defaultdict(lambda: Decimal("0"))

    for entry in entries:
        multiplier = Decimal("-1") if entry.is_reversal else Decimal("1")
        customer_names[entry.customer_id] = entry.customer_name
        if entry.entry_type == "credit":
            revenue += multiplier * entry.amount
            balances[entry.customer_id] += multiplier * entry.amount
            for item in entry.items:
                item_quantities[item.item_name] += multiplier * item.quantity
        else:
            payments += multiplier * entry.amount
            balances[entry.customer_id] -= multiplier * entry.amount

    top_items = [
        TopItem(item_name=name, quantity=quantity)
        for name, quantity in sorted(
            item_quantities.items(), key=lambda entry: (-entry[1], entry[0].casefold())
        )
        if quantity > 0
    ]
    top_debtors = [
        Debtor(
            customer_id=customer_id,
            customer_name=customer_names[customer_id],
            balance=balance,
        )
        for customer_id, balance in sorted(
            balances.items(), key=lambda entry: (-entry[1], customer_names[entry[0]].casefold())
        )
        if balance > 0
    ]
    return DailyAnalytics(
        revenue_inr=max(revenue, Decimal("0")),
        payments_received_inr=max(payments, Decimal("0")),
        top_items=top_items,
        top_debtors=top_debtors,
    )
