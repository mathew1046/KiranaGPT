from __future__ import annotations

from uuid import UUID

from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.app.llm.schemas import (
    CorrectionRequest,
    CorrectionResponse,
    CorrectionStatus,
    IngestItemResult,
    IngestRequest,
    IngestResponse,
    IngestStatus,
    ProcessingRoute,
    QueryRequest,
    QueryResponse,
    QueryStatus,
    ReviewReason,
)
from backend.app.routers.processing import create_processing_router


class StubProcessor:
    def __init__(self) -> None:
        self.commits = 0

    def ingest(self, payload: IngestRequest) -> IngestResponse:
        return IngestResponse(
            items=[
                IngestItemResult(
                    client_event_id=item.client_event_id,
                    status=IngestStatus.NEEDS_REVIEW,
                    route=ProcessingRoute.OFFLINE,
                    reason=ReviewReason.MODEL_UNAVAILABLE,
                )
                for item in payload.items
            ]
        )

    def query(self, payload: QueryRequest) -> QueryResponse:
        return QueryResponse(
            status=QueryStatus.ANSWERED,
            route=ProcessingRoute.PRIMARY,
            answer=f"Answer for: {payload.question}",
        )

    def correction(self, payload: CorrectionRequest) -> CorrectionResponse:
        return CorrectionResponse(
            client_correction_id=payload.client_correction_id,
            status=CorrectionStatus.NEEDS_REVIEW,
            route=ProcessingRoute.OFFLINE,
            reason=ReviewReason.MODEL_UNAVAILABLE,
        )

    def commit(self) -> None:
        self.commits += 1

    def rollback(self) -> None:
        return None


def build_client() -> TestClient:
    app = FastAPI()
    processor = StubProcessor()
    app.include_router(
        create_processing_router(
            processor_provider=lambda: processor,  # type: ignore[arg-type]
        )
    )
    return TestClient(app)


def test_processing_router_validates_request_schema_without_an_app_key() -> None:
    client = build_client()

    success = client.post("/v1/query", json={"question": "What does Ravi owe?"})
    invalid = client.post(
        "/v1/ingest",
        json={
            "items": [
                {
                    "client_event_id": "64f0641c-cbe4-4bf7-995b-c1189a6f497e",
                    "transcript": "Ravi took rice",
                    "raw_audio": "not allowed",
                }
            ]
        },
    )

    assert success.status_code == 200
    assert success.json() == {
        "status": "answered",
        "route": "primary",
        "answer": "Answer for: What does Ravi owe?",
        "reason": None,
    }
    assert invalid.status_code == 422


def test_ingest_response_preserves_client_event_id_for_queue_reconciliation() -> None:
    client = build_client()
    event_id = "3b21f60f-70f5-4cb9-b625-bafae24201ce"
    response = client.post(
        "/v1/ingest",
        json={"items": [{"client_event_id": event_id, "transcript": "Ravi took rice"}]},
    )

    assert response.status_code == 200
    item = response.json()["items"][0]
    assert item["client_event_id"] == str(UUID(event_id))
    assert item["status"] == "needs_review"
