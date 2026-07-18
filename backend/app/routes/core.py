"""Health, speaker-profile, and ledger-read HTTP endpoints."""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy.orm import Session

from ..dependencies import get_db, require_api_key
from ..models import Customer, SpeakerProfile
from ..schemas import (
    CustomerLedgerResponse,
    HealthResponse,
    LedgerEntryResponse,
    SpeakerEnrollmentRequest,
    SpeakerEnrollmentResponse,
)
from ..services.customers import resolve_customer
from ..services.ledger import get_customer_ledger


public_router = APIRouter(tags=["system"])
protected_router = APIRouter(prefix="/v1", tags=["core"], dependencies=[Depends(require_api_key)])


@public_router.get("/health", response_model=HealthResponse)
def health(request: Request) -> HealthResponse:
    """Liveness endpoint intentionally available without credentials."""

    return HealthResponse(status="ok", environment=request.app.state.settings.app_env)


@protected_router.post(
    "/enroll-speaker",
    response_model=SpeakerEnrollmentResponse,
    status_code=status.HTTP_201_CREATED,
)
def enroll_speaker(
    payload: SpeakerEnrollmentRequest,
    session: Session = Depends(get_db),
) -> SpeakerEnrollmentResponse:
    """Persist a numeric speaker embedding after resolving the customer safely."""

    if payload.customer_id is not None:
        customer = session.get(Customer, payload.customer_id)
        if customer is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Customer not found")
        customer_match = "id"
    else:
        match = resolve_customer(
            session,
            payload.customer_name or "",
            phone_number=payload.phone_number,
        )
        customer = match.customer
        customer_match = match.method

    profile = SpeakerProfile(
        customer_id=customer.id,
        embedding=payload.embedding,
        dimensions=len(payload.embedding),
    )
    session.add(profile)
    session.commit()
    session.refresh(profile)

    return SpeakerEnrollmentResponse(
        profile_id=profile.id,
        customer_id=customer.id,
        customer_name=customer.display_name,
        customer_match=customer_match,
        dimensions=profile.dimensions,
        status="enrolled",
    )


@protected_router.get("/ledger/{customer_id}", response_model=CustomerLedgerResponse)
def read_customer_ledger(
    customer_id: UUID,
    limit: int = Query(default=50, ge=1, le=200),
    session: Session = Depends(get_db),
) -> CustomerLedgerResponse:
    """Return recent immutable events and the customer's all-time balance."""

    ledger = get_customer_ledger(session, customer_id, limit=limit)
    if ledger is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Customer not found")

    return CustomerLedgerResponse(
        customer_id=ledger.customer.id,
        customer_name=ledger.customer.display_name,
        balance=ledger.balance,
        entries=[
            LedgerEntryResponse(
                id=entry.id,
                customer_id=entry.customer_id,
                entry_type=entry.entry_type,
                amount=entry.amount,
                currency=entry.currency,
                description=entry.description,
                reversal_of_id=entry.reversal_of_id,
                created_at=entry.created_at,
            )
            for entry in ledger.entries
        ],
    )
