"""Thin SQLAlchemy adapter for backend-core's append-only ledger service.

Imports of backend-core modules are deferred until a method is used.  That
keeps the LLM package importable and unit-testable while the core branch is
still being merged, without duplicating any persistence implementation.
"""

from __future__ import annotations

from decimal import Decimal
from types import SimpleNamespace
from typing import Any

from .schemas import (
    CorrectionAction,
    CorrectionExtraction,
    CorrectionRequest,
    LedgerExtraction,
    ShopCommandType,
    signed_amount,
)
from .service import (
    CorrectionAppendResult,
    LedgerAppendResult,
    ReviewRequiredError,
    StockCommandResult,
)
from .schemas import ReviewReason, TranscriptItem
from ..inventory.schemas import InventoryRestock, InventorySaleLine, InventoryUpdate
from ..inventory.service import InventoryService
from ..services.google_sheets import GoogleSheetsMirror


class SqlAlchemyLedgerGateway:
    """Map approved extraction schemas onto backend-core's ledger primitives.

    The gateway exposes append-only methods only.  It never updates or deletes
    an existing ledger row, and its use of nested transactions prevents a
    failed amendment from leaving an orphaned offset entry in the request unit
    of work.
    """

    def __init__(
        self,
        session: Any,
        *,
        inventory_service: InventoryService | None = None,
        google_sheets_mirror: GoogleSheetsMirror | None = None,
    ) -> None:
        self.session = session
        self.inventory_service = inventory_service
        self.google_sheets_mirror = google_sheets_mirror
        self._pending_inventory_updates: list[tuple[str, str, Any, str | None, Any]] = []
        self._pending_sheet_entries: list[tuple[Any, str, Any]] = []

    def append_entry(self, *, item: TranscriptItem, extraction: LedgerExtraction) -> LedgerAppendResult:
        core = _load_core()
        existing = self.session.scalar(
            core.select(core.LedgerEntry).where(core.LedgerEntry.idempotency_key == str(item.client_event_id))
        )
        if existing is not None:
            return LedgerAppendResult(entry_id=existing.id, duplicate=True)

        with self.session.begin_nested():
            customer_match = core.resolve_customer(self.session, extraction.customer_name)
            if customer_match.method == "fuzzy":
                raise ReviewRequiredError(ReviewReason.CUSTOMER_MATCH_NEEDS_REVIEW)
            entry = core.append_ledger_entry(
                self.session,
                core.LedgerMutation(
                    customer_id=customer_match.customer.id,
                    entry_type=core.LedgerEntryType(extraction.entry_type.value),
                    amount=signed_amount(extraction),
                    description=extraction.description,
                    source_transcript=item.transcript,
                    idempotency_key=str(item.client_event_id),
                    attributes=_item_attributes(extraction),
                ),
            )
        if (
            self.inventory_service is not None
            and extraction.entry_type.value == "sale"
            and extraction.item_name is not None
            and extraction.quantity is not None
        ):
            self._pending_inventory_updates.append(
                (
                    str(entry.id),
                    extraction.item_name,
                    extraction.quantity,
                    extraction.unit,
                    extraction.amount,
                )
            )
        if self.google_sheets_mirror is not None:
            self._pending_sheet_entries.append((entry, customer_match.customer.display_name, extraction))
        return LedgerAppendResult(entry_id=entry.id)

    def apply_stock_command(self, *, extraction: LedgerExtraction) -> StockCommandResult:
        """Apply one model-approved stock operation without touching the ledger."""

        if self.inventory_service is None or extraction.item_name is None:
            raise ReviewRequiredError(ReviewReason.PERSISTENCE_UNAVAILABLE)
        store_id = "default-store"
        if extraction.operation is ShopCommandType.STOCK_RESTOCK:
            if extraction.quantity is None:
                raise ReviewRequiredError(ReviewReason.INVALID_MODEL_OUTPUT)
            item = self.inventory_service.restock(
                store_id,
                InventoryRestock(
                    item_name=extraction.item_name,
                    quantity=extraction.quantity,
                    unit=extraction.unit or "unit",
                    last_price_inr=extraction.price_inr,
                ),
            )
            return StockCommandResult(item_id=item.id)

        existing = self.inventory_service.find_item(store_id, extraction.item_name)
        if existing is None:
            raise ReviewRequiredError(ReviewReason.TARGET_NOT_FOUND)
        if extraction.operation is ShopCommandType.STOCK_SET:
            if extraction.quantity is None:
                raise ReviewRequiredError(ReviewReason.INVALID_MODEL_OUTPUT)
            item = self.inventory_service.update_item(
                store_id,
                existing.id,
                InventoryUpdate(
                    quantity_on_hand=extraction.quantity,
                    unit=extraction.unit or existing.unit,
                    low_stock_threshold=existing.low_stock_threshold,
                    last_price_inr=extraction.price_inr or existing.last_price_inr,
                ),
            )
            if item is None:
                raise ReviewRequiredError(ReviewReason.TARGET_NOT_FOUND)
            return StockCommandResult(item_id=item.id)
        if extraction.operation is ShopCommandType.STOCK_REMOVE:
            if not self.inventory_service.delete_item(store_id, existing.id):
                raise ReviewRequiredError(ReviewReason.TARGET_NOT_FOUND)
            return StockCommandResult(item_id=existing.id)
        raise ReviewRequiredError(ReviewReason.INVALID_MODEL_OUTPUT)

    def correction_context(self, *, target_entry_id: Any) -> dict[str, Any] | None:
        core = _load_core()
        entry = self.session.get(core.LedgerEntry, target_entry_id)
        if entry is None:
            return None
        customer = self.session.get(core.Customer, entry.customer_id)
        return {
            "entry_id": str(entry.id),
            "customer_name": customer.display_name if customer is not None else None,
            "entry_type": entry.entry_type.value,
            "signed_amount": str(entry.amount),
            "description": entry.description,
            "created_at": entry.created_at.isoformat() if entry.created_at is not None else None,
        }

    def append_offsetting_correction(
        self,
        *,
        request: CorrectionRequest,
        correction: CorrectionExtraction,
    ) -> CorrectionAppendResult:
        core = _load_core()
        correction_key = str(request.client_correction_id)
        existing_offset = self.session.scalar(
            core.select(core.LedgerEntry).where(core.LedgerEntry.idempotency_key == correction_key)
        )
        if existing_offset is not None:
            existing_replacement = self.session.scalar(
                core.select(core.LedgerEntry).where(
                    core.LedgerEntry.idempotency_key == _replacement_idempotency_key(correction_key)
                )
            )
            return CorrectionAppendResult(
                correction_entry_id=existing_offset.id,
                replacement_entry_id=existing_replacement.id if existing_replacement is not None else None,
            )

        original = self.session.get(core.LedgerEntry, request.target_entry_id)
        if original is None:
            raise ReviewRequiredError(ReviewReason.TARGET_NOT_FOUND)
        existing_reversal = self.session.scalar(
            core.select(core.LedgerEntry).where(core.LedgerEntry.reversal_of_id == original.id)
        )
        if existing_reversal is not None:
            raise ReviewRequiredError(ReviewReason.TARGET_ALREADY_CORRECTED)

        with self.session.begin_nested():
            offset = core.append_offsetting_entry(
                self.session,
                original,
                description=f"Offset for correction {request.client_correction_id}",
                idempotency_key=correction_key,
            )
            replacement_entry = None
            if correction.action is CorrectionAction.AMEND:
                replacement = correction.replacement
                if replacement is None:  # Pydantic validation makes this defensive only.
                    raise ReviewRequiredError(ReviewReason.INVALID_MODEL_OUTPUT)
                replacement_entry = core.append_ledger_entry(
                    self.session,
                    core.LedgerMutation(
                        customer_id=original.customer_id,
                        entry_type=core.LedgerEntryType(replacement.entry_type.value),
                        amount=signed_amount(replacement),
                        description=replacement.description,
                        source_transcript=request.transcript,
                        idempotency_key=_replacement_idempotency_key(correction_key),
                        attributes=_item_attributes(replacement),
                    ),
                )
        return CorrectionAppendResult(
            correction_entry_id=offset.id,
            replacement_entry_id=replacement_entry.id if replacement_entry is not None else None,
        )

    def query_context(self, *, question: str) -> dict[str, Any] | None:
        """Return bounded local balance facts for a model to summarize.

        ``question`` is deliberately unused for database filtering: the LLM
        receives facts, not generated SQL, and cannot influence a query.
        """

        del question
        core = _load_core()
        balance = core.func.coalesce(core.func.sum(core.LedgerEntry.amount), Decimal("0.00"))
        rows = self.session.execute(
            core.select(core.Customer.display_name, balance.label("balance"))
            .outerjoin(core.LedgerEntry, core.LedgerEntry.customer_id == core.Customer.id)
            .group_by(core.Customer.id, core.Customer.display_name)
            .order_by(core.Customer.display_name.asc())
            .limit(500)
        ).all()
        return {
            "currency": "INR",
            "customer_balances": [
                {"customer_name": name, "balance": str(total or Decimal("0.00"))}
                for name, total in rows
            ],
        }

    def recent_transactions(self) -> dict[str, Any]:
        """Give extraction a small, read-only view of the latest shop activity."""

        core = _load_core()
        rows = self.session.execute(
            core.select(core.LedgerEntry, core.Customer)
            .join(core.Customer, core.Customer.id == core.LedgerEntry.customer_id)
            .order_by(core.LedgerEntry.created_at.desc(), core.LedgerEntry.id.desc())
            .limit(20)
        ).all()
        context = {
            "currency": "INR",
            "entries": [
                {
                    "customer_name": customer.display_name,
                    "entry_type": entry.entry_type.value,
                    "signed_amount": str(entry.amount),
                    "item_name": (entry.attributes or {}).get("item_name"),
                    "quantity": (entry.attributes or {}).get("quantity"),
                    "unit": (entry.attributes or {}).get("unit"),
                    "created_at": entry.created_at.isoformat() if entry.created_at else None,
                }
                for entry, customer in rows
            ],
        }
        if self.inventory_service is not None:
            stock = self.inventory_service.list_inventory("default-store").items
            context["current_stock"] = [
                {
                    "item_name": item.item_name,
                    "quantity_on_hand": str(item.quantity_on_hand),
                    "unit": item.unit,
                }
                for item in stock
            ]
        balance = core.func.coalesce(core.func.sum(core.LedgerEntry.amount), Decimal("0.00"))
        balances = self.session.execute(
            core.select(core.Customer.display_name, balance.label("balance"))
            .outerjoin(core.LedgerEntry, core.LedgerEntry.customer_id == core.Customer.id)
            .group_by(core.Customer.id, core.Customer.display_name)
            .order_by(core.Customer.display_name.asc())
            .limit(200)
        ).all()
        context["customer_balances"] = [
            {"customer_name": name, "balance": str(total or Decimal("0.00"))}
            for name, total in balances
        ]
        return context

    def commit(self) -> None:
        self.session.commit()
        if self.inventory_service is not None:
            for entry_id, item_name, quantity, unit, amount in self._pending_inventory_updates:
                self.inventory_service.apply_confirmed_sale(
                    "default-store",
                    entry_id,
                    [
                        InventorySaleLine(
                            item_name=item_name,
                            quantity=quantity,
                            unit=unit,
                            price_inr=amount,
                        )
                    ],
                )
        if self.google_sheets_mirror is not None:
            for entry, customer_name, extraction in self._pending_sheet_entries:
                self.google_sheets_mirror.append_ledger_entry(
                    entry=entry,
                    customer_name=customer_name,
                    extraction=extraction,
                )
        self._pending_inventory_updates.clear()
        self._pending_sheet_entries.clear()

    def rollback(self) -> None:
        self.session.rollback()
        self._pending_inventory_updates.clear()
        self._pending_sheet_entries.clear()


def _item_attributes(extraction: LedgerExtraction | Any) -> dict[str, Any]:
    """Keep optional product details as structured metadata rather than prose."""

    return {
        "item_name": extraction.item_name,
        "quantity": str(extraction.quantity) if extraction.quantity is not None else None,
        "unit": extraction.unit,
    }


def _replacement_idempotency_key(correction_key: str) -> str:
    """Stay inside backend-core's 128-character idempotency-key limit."""

    return f"{correction_key}:replacement"


def _load_core() -> Any:
    """Import core symbols lazily to preserve this module's standalone import."""

    from sqlalchemy import func, select

    from ..models import Customer, LedgerEntry, LedgerEntryType
    from ..services.customers import resolve_customer
    from ..services.ledger import LedgerMutation, append_ledger_entry, append_offsetting_entry

    return SimpleNamespace(
        Customer=Customer,
        LedgerEntry=LedgerEntry,
        LedgerEntryType=LedgerEntryType,
        LedgerMutation=LedgerMutation,
        append_ledger_entry=append_ledger_entry,
        append_offsetting_entry=append_offsetting_entry,
        func=func,
        resolve_customer=resolve_customer,
        select=select,
    )
