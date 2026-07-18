"""Safe local customer-name normalization and fuzzy matching."""

from __future__ import annotations

from dataclasses import dataclass
from difflib import SequenceMatcher
import re
import unicodedata

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import Customer


FUZZY_MATCH_THRESHOLD = 0.92


def normalize_customer_name(value: str) -> str:
    """Normalize a name deterministically without calling a remote service."""

    decomposed = unicodedata.normalize("NFKD", value).casefold()
    ascii_folded = "".join(char for char in decomposed if not unicodedata.combining(char))
    return re.sub(r"\s+", " ", re.sub(r"[^\w\s]", " ", ascii_folded)).strip()


@dataclass(frozen=True, slots=True)
class CustomerMatch:
    customer: Customer
    score: float
    method: str


def find_customer_match(session: Session, name: str) -> CustomerMatch | None:
    """Return an exact or conservative fuzzy match for a customer name.

    The threshold intentionally favors avoiding a false identity merge.  The
    caller can create a new customer or request human confirmation when this
    function returns ``None``.
    """

    normalized_name = normalize_customer_name(name)
    if not normalized_name:
        return None

    customers = list(session.scalars(select(Customer).order_by(Customer.created_at.asc())))
    for customer in customers:
        if customer.normalized_name == normalized_name:
            return CustomerMatch(customer=customer, score=1.0, method="exact")

    best: CustomerMatch | None = None
    for customer in customers:
        score = SequenceMatcher(a=normalized_name, b=customer.normalized_name).ratio()
        if score >= FUZZY_MATCH_THRESHOLD and (best is None or score > best.score):
            best = CustomerMatch(customer=customer, score=score, method="fuzzy")
    return best


def resolve_customer(session: Session, name: str, *, phone_number: str | None = None) -> CustomerMatch:
    """Find a safe match or create a new customer identity.

    Phone numbers are treated as a stronger exact identifier when supplied.
    The returned ``method`` is one of ``phone``, ``exact``, ``fuzzy``, or
    ``created`` so callers can surface review UI for fuzzy assignments.
    """

    normalized_name = normalize_customer_name(name)
    if not normalized_name:
        raise ValueError("customer name must contain at least one letter or number")

    if phone_number:
        by_phone = session.scalar(select(Customer).where(Customer.phone_number == phone_number))
        if by_phone is not None:
            return CustomerMatch(customer=by_phone, score=1.0, method="phone")

    match = find_customer_match(session, name)
    if match is not None:
        return match

    customer = Customer(
        display_name=name.strip(),
        normalized_name=normalized_name,
        phone_number=phone_number,
    )
    session.add(customer)
    session.flush()
    return CustomerMatch(customer=customer, score=1.0, method="created")
