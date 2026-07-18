"""Pydantic boundary schemas for backend-core routes."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal
import math
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from .models import LedgerEntryType


class StrictSchema(BaseModel):
    """Reject accidental/unsafe input fields instead of silently dropping them."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class HealthResponse(StrictSchema):
    status: Literal["ok"]
    environment: str


class SpeakerEnrollmentRequest(StrictSchema):
    """Numeric embedding enrollment; audio payloads are intentionally invalid."""

    customer_id: UUID | None = None
    customer_name: str | None = Field(default=None, min_length=1, max_length=160)
    phone_number: str | None = Field(default=None, min_length=3, max_length=32)
    embedding: list[float] = Field(min_length=8, max_length=4096)

    @model_validator(mode="after")
    def require_one_customer_reference(self) -> "SpeakerEnrollmentRequest":
        if (self.customer_id is None) == (self.customer_name is None):
            raise ValueError("provide exactly one of customer_id or customer_name")
        if self.customer_id is not None and self.phone_number is not None:
            raise ValueError("phone_number can only be supplied with customer_name")
        return self

    @field_validator("embedding")
    @classmethod
    def embedding_is_finite(cls, value: list[float]) -> list[float]:
        if any(not math.isfinite(component) for component in value):
            raise ValueError("embedding values must be finite numbers")
        return value


class SpeakerEnrollmentResponse(StrictSchema):
    profile_id: UUID
    customer_id: UUID
    customer_name: str
    customer_match: Literal["phone", "exact", "fuzzy", "created", "id"]
    dimensions: int
    status: Literal["enrolled"]


class LedgerEntryResponse(StrictSchema):
    id: UUID
    customer_id: UUID
    entry_type: LedgerEntryType
    amount: Decimal
    currency: str
    description: str | None
    reversal_of_id: UUID | None
    created_at: datetime


class CustomerLedgerResponse(StrictSchema):
    customer_id: UUID
    customer_name: str
    balance: Decimal
    entries: list[LedgerEntryResponse]
