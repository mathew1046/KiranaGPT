from fastapi.testclient import TestClient

from backend.app.services.customers import resolve_customer


def test_customer_resolution_uses_conservative_local_fuzzy_match(client: TestClient) -> None:
    with client.app.state.database.session_factory() as session:
        original = resolve_customer(session, "Asha General Stores")
        session.commit()

    with client.app.state.database.session_factory() as session:
        matched = resolve_customer(session, "asha general store")

        assert matched.customer.id == original.customer.id
        assert matched.method == "fuzzy"
        assert matched.score >= 0.92
