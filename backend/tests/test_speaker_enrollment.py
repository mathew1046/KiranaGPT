from fastapi.testclient import TestClient
from sqlalchemy import select

from backend.app.models import Customer, SpeakerProfile


def test_enroll_speaker_persists_numeric_embedding_only(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    response = client.post(
        "/v1/enroll-speaker",
        headers=auth_headers,
        json={
            "customer_name": "Asha Stores",
            "embedding": [0.25] * 8,
        },
    )

    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "enrolled"
    assert body["customer_name"] == "Asha Stores"
    assert body["customer_match"] == "created"
    assert body["dimensions"] == 8
    assert "embedding" not in body

    with client.app.state.database.session_factory() as session:
        profile = session.scalar(select(SpeakerProfile))
        customer = session.scalar(select(Customer))
        assert profile is not None
        assert customer is not None
        assert profile.embedding == [0.25] * 8
        assert profile.customer_id == customer.id


def test_enroll_speaker_rejects_invalid_schema_and_raw_audio_fields(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    response = client.post(
        "/v1/enroll-speaker",
        headers=auth_headers,
        json={
            "customer_name": "Asha Stores",
            "embedding": [0.25] * 7,
            "raw_audio": "must-not-be-accepted",
        },
    )

    assert response.status_code == 422
    with client.app.state.database.session_factory() as session:
        assert session.scalar(select(SpeakerProfile)) is None


def test_enroll_speaker_requires_bearer_api_key(client: TestClient) -> None:
    response = client.post(
        "/v1/enroll-speaker",
        json={"customer_name": "Asha Stores", "embedding": [0.25] * 8},
    )

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"
