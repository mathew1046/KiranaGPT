"""Persistence models for customer identity, speaker profiles, and the ledger."""

from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
from enum import Enum
from typing import Any
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, DateTime, Enum as SqlEnum, ForeignKey, Index, JSON, Numeric, String, Text, UniqueConstraint, event
from sqlalchemy.orm import Mapped, Session, mapped_column, relationship
from sqlalchemy.types import Uuid

from .database import Base


def utc_now() -> datetime:
    """Return an aware UTC timestamp suitable for all persisted events."""

    return datetime.now(timezone.utc)


class LedgerEntryType(str, Enum):
    """How an entry changes the customer's outstanding balance."""

    SALE = "sale"
    PAYMENT = "payment"
    ADJUSTMENT = "adjustment"


class Customer(Base):
    """A customer identity, deliberately independent from a speaker profile."""

    __tablename__ = "customers"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    display_name: Mapped[str] = mapped_column(String(160), nullable=False)
    normalized_name: Mapped[str] = mapped_column(String(160), nullable=False, index=True)
    phone_number: Mapped[str | None] = mapped_column(String(32), nullable=True, unique=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, onupdate=utc_now, nullable=False
    )

    ledger_entries: Mapped[list["LedgerEntry"]] = relationship(back_populates="customer")
    speaker_profiles: Mapped[list["SpeakerProfile"]] = relationship(back_populates="customer")

    __table_args__ = (
        Index("ix_customers_normalized_name_phone", "normalized_name", "phone_number"),
    )


class SpeakerProfile(Base):
    """A numeric voice embedding only; no raw audio is ever stored here."""

    __tablename__ = "speaker_profiles"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    customer_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("customers.id", ondelete="CASCADE"), nullable=False, index=True
    )
    embedding: Mapped[list[float]] = mapped_column(JSON, nullable=False)
    dimensions: Mapped[int] = mapped_column(nullable=False)
    enrolled_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now, nullable=False)
    is_active: Mapped[bool] = mapped_column(default=True, nullable=False)

    customer: Mapped[Customer] = relationship(back_populates="speaker_profiles")

    __table_args__ = (
        CheckConstraint("dimensions > 0", name="ck_speaker_profiles_dimensions_positive"),
    )


class LedgerEntry(Base):
    """An immutable, signed customer balance mutation.

    ``amount`` is a signed INR amount: a positive value increases what the
    customer owes; a negative value reduces it.  Corrections must be new rows
    linked through ``reversal_of_id`` rather than updates to historical rows.
    """

    __tablename__ = "ledger_entries"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    customer_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("customers.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    entry_type: Mapped[LedgerEntryType] = mapped_column(
        SqlEnum(LedgerEntryType, native_enum=False, length=24), nullable=False
    )
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), default="INR", nullable=False)
    description: Mapped[str | None] = mapped_column(String(500), nullable=True)
    source_transcript: Mapped[str | None] = mapped_column(Text, nullable=True)
    idempotency_key: Mapped[str | None] = mapped_column(String(128), nullable=True, unique=True)
    reversal_of_id: Mapped[UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("ledger_entries.id", ondelete="RESTRICT"), nullable=True, index=True
    )
    attributes: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now, nullable=False, index=True)

    customer: Mapped[Customer] = relationship(back_populates="ledger_entries")

    __table_args__ = (
        CheckConstraint("amount <> 0", name="ck_ledger_entries_amount_nonzero"),
        CheckConstraint("length(currency) = 3", name="ck_ledger_entries_currency_code"),
        Index("ix_ledger_entries_customer_created", "customer_id", "created_at"),
    )


class InventoryRecord(Base):
    """Current stock for one named item in the MVP's default shop."""

    __tablename__ = "inventory_records"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    store_id: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    item_name: Mapped[str] = mapped_column(String(120), nullable=False)
    normalized_name: Mapped[str] = mapped_column(String(120), nullable=False)
    unit: Mapped[str] = mapped_column(String(24), nullable=False, default="unit")
    quantity_on_hand: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False, default=0)
    low_stock_threshold: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False, default=0)
    last_price_inr: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now, onupdate=utc_now, nullable=False)

    __table_args__ = (
        UniqueConstraint("store_id", "normalized_name", name="uq_inventory_store_item"),
    )


class ImmutableLedgerError(RuntimeError):
    """Raised if application code attempts to mutate or delete a ledger row."""


@event.listens_for(Session, "before_flush")
def _prevent_ledger_rewrites(session: Session, _flush_context: object, _instances: object) -> None:
    """Guard the central append-only invariant at the ORM boundary."""

    for instance in session.deleted:
        if isinstance(instance, LedgerEntry):
            raise ImmutableLedgerError("ledger entries are append-only and cannot be deleted")
    for instance in session.dirty:
        if isinstance(instance, LedgerEntry) and session.is_modified(instance, include_collections=False):
            raise ImmutableLedgerError("ledger entries are append-only and cannot be updated")
