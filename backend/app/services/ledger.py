"""Append-only ledger operations and read models."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal
from typing import Any
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..models import Customer, LedgerEntry, LedgerEntryType


@dataclass(frozen=True, slots=True)
class LedgerMutation:
    """Validated input for one new ledger event.

    Amounts use signed INR balance semantics.  A correction should call
    ``append_offsetting_entry`` rather than alter the original event.
    """

    customer_id: UUID
    entry_type: LedgerEntryType
    amount: Decimal
    description: str | None = None
    source_transcript: str | None = None
    idempotency_key: str | None = None
    attributes: dict[str, Any] | None = None
    reversal_of_id: UUID | None = None


class DuplicateLedgerEventError(ValueError):
    """Raised when a client retries an event with an existing idempotency key."""


def append_ledger_entry(session: Session, mutation: LedgerMutation) -> LedgerEntry:
    """Append one immutable event after checking basic business invariants."""

    if mutation.amount == 0:
        raise ValueError("ledger amount must not be zero")
    if session.get(Customer, mutation.customer_id) is None:
        raise LookupError("customer does not exist")
    if mutation.idempotency_key:
        existing = session.scalar(
            select(LedgerEntry).where(LedgerEntry.idempotency_key == mutation.idempotency_key)
        )
        if existing is not None:
            raise DuplicateLedgerEventError("ledger event already exists for this idempotency key")

    entry = LedgerEntry(
        customer_id=mutation.customer_id,
        entry_type=mutation.entry_type,
        amount=mutation.amount,
        description=mutation.description,
        source_transcript=mutation.source_transcript,
        idempotency_key=mutation.idempotency_key,
        attributes=mutation.attributes,
        reversal_of_id=mutation.reversal_of_id,
    )
    session.add(entry)
    session.flush()
    return entry


def append_offsetting_entry(
    session: Session,
    original: LedgerEntry,
    *,
    description: str | None = None,
    idempotency_key: str | None = None,
) -> LedgerEntry:
    """Create the immutable inverse required for a correction workflow."""

    return append_ledger_entry(
        session,
        LedgerMutation(
            customer_id=original.customer_id,
            entry_type=LedgerEntryType.ADJUSTMENT,
            amount=-original.amount,
            description=description or f"Offset for ledger entry {original.id}",
            idempotency_key=idempotency_key,
            reversal_of_id=original.id,
        ),
    )


@dataclass(frozen=True, slots=True)
class CustomerLedger:
    customer: Customer
    entries: list[LedgerEntry]
    balance: Decimal


def get_customer_ledger(session: Session, customer_id: UUID, *, limit: int = 50) -> CustomerLedger | None:
    """Return newest ledger entries and the all-time signed customer balance."""

    customer = session.get(Customer, customer_id)
    if customer is None:
        return None
    entries = list(
        session.scalars(
            select(LedgerEntry)
            .where(LedgerEntry.customer_id == customer_id)
            .order_by(LedgerEntry.created_at.desc(), LedgerEntry.id.desc())
            .limit(limit)
        )
    )
    balance = session.scalar(
        select(func.coalesce(func.sum(LedgerEntry.amount), Decimal("0.00"))).where(
            LedgerEntry.customer_id == customer_id
        )
    )
    return CustomerLedger(customer=customer, entries=entries, balance=Decimal(balance or 0))
