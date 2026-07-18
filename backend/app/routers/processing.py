"""HTTP routes for transcript processing, query, and correction.

The generic factory accepts injected dependencies so the module has no import
dependency on backend-core.  ``create_core_processing_router`` is the narrow
integration hook used after backend-core is available.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

from fastapi import APIRouter, Depends, Request

from ..llm.adapter import OpenAIAdapter, OpenAISettings
from ..llm.gateway import SqlAlchemyLedgerGateway
from ..llm.schemas import (
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
    ReviewReason,
)
from ..llm.service import ProcessingService


def create_processing_router(
    *,
    processor_provider: Callable[..., ProcessingService],
) -> APIRouter:
    """Build all three contract routes around the processing service."""

    router = APIRouter(
        prefix="/v1",
        tags=["processing"],
    )

    @router.post("/ingest", response_model=IngestResponse)
    def ingest(
        payload: IngestRequest,
        processor: ProcessingService = Depends(processor_provider),
    ) -> IngestResponse:
        result = processor.ingest(payload)
        if any(item.status is IngestStatus.SYNCED for item in result.items):
            try:
                processor.commit()
            except Exception:
                processor.rollback()
                return IngestResponse(
                    items=[
                        _ingest_commit_failure(item) if item.status is IngestStatus.SYNCED else item
                        for item in result.items
                    ]
                )
        return result

    @router.post("/query", response_model=QueryResponse)
    def query(
        payload: QueryRequest,
        processor: ProcessingService = Depends(processor_provider),
    ) -> QueryResponse:
        return processor.query(payload)

    @router.post("/correction", response_model=CorrectionResponse)
    def correction(
        payload: CorrectionRequest,
        processor: ProcessingService = Depends(processor_provider),
    ) -> CorrectionResponse:
        result = processor.correction(payload)
        if result.status is CorrectionStatus.CORRECTED:
            try:
                processor.commit()
            except Exception:
                processor.rollback()
                return CorrectionResponse(
                    client_correction_id=result.client_correction_id,
                    status=CorrectionStatus.NEEDS_REVIEW,
                    route=result.route,
                    reason=ReviewReason.PERSISTENCE_UNAVAILABLE,
                )
        return result

    return router


def create_core_processing_router() -> APIRouter:
    """Wire this feature to backend-core lazily, once its modules are present.

    Backend-core's application factory should call this once and include the
    returned router.
    """

    from ..dependencies import get_db

    def get_processor(
        request: Request,
        session: Any = Depends(get_db),
    ) -> ProcessingService:
        gateway = SqlAlchemyLedgerGateway(session)
        settings = OpenAISettings.from_runtime_settings(request.app.state.settings)
        return ProcessingService(
            OpenAIAdapter(settings),
            ledger_gateway=gateway,
            query_context_provider=gateway,
            correction_context_provider=gateway,
        )

    return create_processing_router(
        processor_provider=get_processor,
    )


def _ingest_commit_failure(item: IngestItemResult) -> IngestItemResult:
    """Do not report a sync when its transaction could not be committed."""

    return IngestItemResult(
        client_event_id=item.client_event_id,
        status=IngestStatus.NEEDS_REVIEW,
        route=item.route if item.route is not ProcessingRoute.PRIMARY else ProcessingRoute.OFFLINE,
        reason=ReviewReason.PERSISTENCE_UNAVAILABLE,
    )
