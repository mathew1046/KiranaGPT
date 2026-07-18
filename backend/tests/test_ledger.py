from decimal import Decimal

from fastapi.testclient import TestClient
import pytest
from sqlalchemy import select

from backend.app.models import Customer, ImmutableLedgerError, LedgerEntry, LedgerEntryType
from backend.app.services.customers import resolve_customer
from backend.app.services.ledger import LedgerMutation, append_ledger_entry


def _seed_customer_ledger(client: TestClient) -> Customer:
    with client.app.state.database.session_factory() as session:
        customer = resolve_customer(session, "Maya Mart")
        append_ledger_entry(
            session,
            LedgerMutation(
                customer_id=customer.customer.id,
                entry_type=LedgerEntryType.SALE,
                amount=Decimal("125.50"),
                description="Rice and dal",
                idempotency_key="event-sale-1",
            ),
        )
        append_ledger_entry(
            session,
            LedgerMutation(
                customer_id=customer.customer.id,
                entry_type=LedgerEntryType.PAYMENT,
                amount=Decimal("-25.50"),
                description="UPI payment",
                idempotency_key="event-payment-1",
            ),
        )
        session.commit()
        return customer.customer


def test_get_ledger_returns_ordered_events_and_signed_balance(client: TestClient) -> None:
    customer = _seed_customer_ledger(client)

    response = client.get(f"/v1/ledger/{customer.id}")

    assert response.status_code == 200
    body = response.json()
    assert body["customer_id"] == str(customer.id)
    assert body["customer_name"] == "Maya Mart"
    assert body["balance"] == "100.00"
    assert [entry["entry_type"] for entry in body["entries"]] == ["payment", "sale"]
    assert body["entries"][0]["amount"] == "-25.50"
    assert "source_transcript" not in body["entries"][0]


def test_get_ledger_rejects_malformed_customer_id(client: TestClient) -> None:
    response = client.get("/v1/ledger/not-a-uuid")

    assert response.status_code == 422


def test_get_ledger_is_available_without_an_app_key(client: TestClient) -> None:
    response = client.get("/v1/ledger/00000000-0000-0000-0000-000000000000")

    assert response.status_code == 404


def test_ledger_rows_cannot_be_updated_or_deleted(client: TestClient) -> None:
    customer = _seed_customer_ledger(client)
    with client.app.state.database.session_factory() as session:
        entry = session.scalar(select(LedgerEntry).where(LedgerEntry.customer_id == customer.id))
        assert entry is not None
        entry.description = "This must not persist"
        with pytest.raises(ImmutableLedgerError, match="append-only"):
            session.commit()
