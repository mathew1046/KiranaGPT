from fastapi.testclient import TestClient


def test_health_is_public_and_reports_runtime_environment(client: TestClient) -> None:
    response = client.get("/health", headers={"Authorization": "Bearer deliberately-wrong"})

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "environment": "test"}
