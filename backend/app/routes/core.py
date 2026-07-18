"""Health, speaker-profile, and ledger-read HTTP endpoints."""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..dependencies import get_db
from ..models import Customer, LedgerEntry, SpeakerProfile
from ..schemas import (
    CustomerLedgerResponse,
    CreditSummaryResponse,
    HealthResponse,
    LedgerEntryResponse,
    SpeakerEnrollmentRequest,
    SpeakerEnrollmentResponse,
)
from ..services.customers import resolve_customer
from ..services.ledger import get_customer_ledger


public_router = APIRouter(tags=["system"])
core_router = APIRouter(prefix="/v1", tags=["core"])


@public_router.get("/health", response_model=HealthResponse)
def health(request: Request) -> HealthResponse:
    """Liveness endpoint intentionally available without credentials."""

    return HealthResponse(status="ok", environment=request.app.state.settings.app_env)


@core_router.post(
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


@core_router.get("/ledger/{customer_id}", response_model=CustomerLedgerResponse)
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


@core_router.get("/credits", response_model=list[CreditSummaryResponse])
def list_outstanding_credits(session: Session = Depends(get_db)) -> list[CreditSummaryResponse]:
    """Return customers with a positive amount still owed to the shop."""

    outstanding = func.coalesce(func.sum(LedgerEntry.amount), 0).label("outstanding")
    rows = session.execute(
        select(Customer.id, Customer.display_name, outstanding)
        .outerjoin(LedgerEntry, LedgerEntry.customer_id == Customer.id)
        .group_by(Customer.id, Customer.display_name)
        .having(outstanding > 0)
        .order_by(outstanding.desc(), Customer.display_name.asc())
    ).all()
    return [
        CreditSummaryResponse(
            customer_id=customer_id,
            customer_name=name,
            outstanding_inr=amount,
        )
        for customer_id, name, amount in rows
    ]
