"""Validated HTTP and structured-output schemas for LLM processing.

Only text transcripts cross this boundary.  In particular, all request models
reject unknown fields, which makes accidental audio payloads invalid rather
than silently accepting or storing them.
"""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from enum import Enum
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


class StrictSchema(BaseModel):
    """Shared safe schema configuration for public and model output payloads."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class LedgerEventType(str, Enum):
    """Event types which backend-core can persist directly."""

    SALE = "sale"
    PAYMENT = "payment"


class ShopCommandType(str, Enum):
    """One state change the shopkeeper can ask the voice agent to make."""

    CREDIT_SALE = "credit_sale"
    CREDIT_PAYMENT = "credit_payment"
    STOCK_RESTOCK = "stock_restock"
    STOCK_SET = "stock_set"
    STOCK_REMOVE = "stock_remove"


class ProcessingRoute(str, Enum):
    """The deterministic inference path used for a result."""

    PRIMARY = "primary"
    ESCALATED = "escalated"
    OFFLINE = "offline"


class IngestStatus(str, Enum):
    SYNCED = "synced"
    NEEDS_REVIEW = "needs_review"
    DUPLICATE = "duplicate"


class QueryStatus(str, Enum):
    ANSWERED = "answered"
    NEEDS_REVIEW = "needs_review"


class CorrectionStatus(str, Enum):
    CORRECTED = "corrected"
    NEEDS_REVIEW = "needs_review"


class CorrectionAction(str, Enum):
    CANCEL = "cancel"
    AMEND = "amend"


class ReviewReason(str, Enum):
    """Public-safe failure codes; none contain transcripts or provider errors."""

    MODEL_UNAVAILABLE = "model_unavailable"
    INVALID_MODEL_OUTPUT = "invalid_model_output"
    CONFIDENCE_BELOW_THRESHOLD = "confidence_below_threshold"
    ESCALATION_FAILED = "escalation_failed"
    PERSISTENCE_UNAVAILABLE = "persistence_unavailable"
    CUSTOMER_MATCH_NEEDS_REVIEW = "customer_match_needs_review"
    TARGET_NOT_FOUND = "target_not_found"
    TARGET_ALREADY_CORRECTED = "target_already_corrected"
    QUERY_CONTEXT_UNAVAILABLE = "query_context_unavailable"


class TranscriptItem(StrictSchema):
    """One locally queued transcript, intentionally without any audio field."""

    client_event_id: UUID
    transcript: str = Field(min_length=1, max_length=4_000)
    captured_at: datetime | None = None
    speaker_id: UUID | None = None
    locale: str = Field(default="en-IN", min_length=2, max_length=16)


class IngestRequest(StrictSchema):
    """A bounded sync batch from the client's local transcript queue."""

    items: list[TranscriptItem] = Field(min_length=1, max_length=50)


class LedgerExtraction(StrictSchema):
    """Strict structured output before the voice agent changes shop state.

    ``amount`` is always a positive absolute INR value.  The persistence
    gateway assigns its signed ledger impact: sales are positive and payments
    are negative.  Nullable fields intentionally have no defaults so strict
    JSON Schema output must include them as either a value or ``null``.
    """

    operation: ShopCommandType = ShopCommandType.CREDIT_SALE
    entry_type: LedgerEventType | None = None
    customer_name: str | None = Field(default=None, min_length=1, max_length=160)
    amount: Decimal | None = Field(default=None, gt=0, max_digits=12, decimal_places=2)
    description: str | None = Field(default=None, max_length=500)
    item_name: str | None = Field(max_length=160)
    quantity: Decimal | None = Field(gt=0, max_digits=10, decimal_places=3)
    unit: str | None = Field(max_length=32)
    price_inr: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=2)
    confidence: float = Field(ge=0, le=1)

    @model_validator(mode="after")
    def require_complete_item_details(self) -> "LedgerExtraction":
        if self.operation in {ShopCommandType.CREDIT_SALE, ShopCommandType.CREDIT_PAYMENT}:
            expected = (
                LedgerEventType.SALE
                if self.operation is ShopCommandType.CREDIT_SALE
                else LedgerEventType.PAYMENT
            )
            if self.entry_type is not expected or self.customer_name is None or self.amount is None:
                raise ValueError("credit commands require matching entry_type, customer_name, and amount")
        elif self.entry_type is not None or self.customer_name is not None or self.amount is not None:
            raise ValueError("stock commands must not include ledger fields")

        if self.operation in {ShopCommandType.STOCK_RESTOCK, ShopCommandType.STOCK_SET}:
            if self.item_name is None or self.quantity is None or self.unit is None:
                raise ValueError("stock restock and set commands require item_name, quantity, and unit")
        elif self.operation is ShopCommandType.STOCK_REMOVE:
            if self.item_name is None:
                raise ValueError("stock removal requires item_name")
        elif any(value is not None for value in (self.item_name, self.quantity, self.unit)) and self.item_name is None:
            raise ValueError("item_name is required when item details are supplied")
        return self


class CorrectionReplacement(StrictSchema):
    """The replacement event for an amendment, tied to the original customer."""

    entry_type: LedgerEventType
    amount: Decimal = Field(gt=0, max_digits=12, decimal_places=2)
    description: str | None = Field(max_length=500)
    item_name: str | None = Field(max_length=160)
    quantity: Decimal | None = Field(gt=0, max_digits=10, decimal_places=3)
    unit: str | None = Field(max_length=32)

    @model_validator(mode="after")
    def require_complete_item_details(self) -> "CorrectionReplacement":
        item_fields = (self.item_name, self.quantity, self.unit)
        if any(value is not None for value in item_fields) and self.item_name is None:
            raise ValueError("item_name is required when item details are supplied")
        return self


class CorrectionExtraction(StrictSchema):
    """Strict model output used before an immutable correction is appended."""

    action: CorrectionAction
    replacement: CorrectionReplacement | None
    confidence: float = Field(ge=0, le=1)

    @model_validator(mode="after")
    def require_replacement_for_amendment(self) -> "CorrectionExtraction":
        if self.action is CorrectionAction.AMEND and self.replacement is None:
            raise ValueError("amendments require a replacement event")
        if self.action is CorrectionAction.CANCEL and self.replacement is not None:
            raise ValueError("cancellations must not include a replacement event")
        return self


class QueryAnswer(StrictSchema):
    """Constrained spoken-friendly answer returned by the model."""

    answer: str = Field(min_length=1, max_length=500)
    confidence: float = Field(ge=0, le=1)


class IngestItemResult(StrictSchema):
    client_event_id: UUID
    status: IngestStatus
    route: ProcessingRoute
    ledger_entry_id: UUID | None = None
    inventory_item_id: str | None = None
    reason: ReviewReason | None = None

    @model_validator(mode="after")
    def validate_status_shape(self) -> "IngestItemResult":
        if self.status is IngestStatus.SYNCED and (
            self.ledger_entry_id is None and self.inventory_item_id is None
        ):
            raise ValueError("synced results require a ledger or inventory id")
        if self.status is IngestStatus.NEEDS_REVIEW and (
            self.ledger_entry_id is not None or self.inventory_item_id is not None
        ):
            raise ValueError("needs_review results must not include persisted ids")
        return self


class IngestResponse(StrictSchema):
    items: list[IngestItemResult]


class QueryRequest(StrictSchema):
    question: str = Field(min_length=1, max_length=1_000)
    locale: str = Field(default="en-IN", min_length=2, max_length=16)


class QueryResponse(StrictSchema):
    status: QueryStatus
    route: ProcessingRoute
    answer: str = Field(min_length=1, max_length=500)
    reason: ReviewReason | None = None


class CorrectionRequest(StrictSchema):
    client_correction_id: UUID
    target_entry_id: UUID
    transcript: str = Field(min_length=1, max_length=4_000)
    locale: str = Field(default="en-IN", min_length=2, max_length=16)


class CorrectionResponse(StrictSchema):
    client_correction_id: UUID
    status: CorrectionStatus
    route: ProcessingRoute
    correction_entry_id: UUID | None = None
    replacement_entry_id: UUID | None = None
    reason: ReviewReason | None = None

    @model_validator(mode="after")
    def validate_status_shape(self) -> "CorrectionResponse":
        if self.status is CorrectionStatus.CORRECTED and self.correction_entry_id is None:
            raise ValueError("corrected results require correction_entry_id")
        if self.status is CorrectionStatus.NEEDS_REVIEW and (
            self.correction_entry_id is not None or self.replacement_entry_id is not None
        ):
            raise ValueError("needs_review results must not include correction entry ids")
        return self


def signed_amount(extraction: LedgerExtraction | CorrectionReplacement) -> Decimal:
    """Return the immutable-ledger impact for a validated absolute amount."""

    if extraction.amount is None:
        raise ValueError("credit commands require an amount")
    return extraction.amount if extraction.entry_type is LedgerEventType.SALE else -extraction.amount
