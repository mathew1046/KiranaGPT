"""HTTP routes for transcript processing, query, and correction.

The generic factory accepts injected dependencies so the module has no import
dependency on backend-core.  ``create_core_processing_router`` is the narrow
integration hook used after backend-core is available.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, Request

from ..llm.adapter import OpenAIAdapter, OpenAISettings
from ..llm.gateway import SqlAlchemyLedgerGateway
from ..llm.schemas import (
    CorrectionRequest,
    CorrectionResponse,
    CorrectionStatus,
    AnalysisPreviewRequest,
    AnalysisPreviewResponse,
    IngestItemResult,
    IngestRequest,
    IngestResponse,
    IngestStatus,
    ProcessingRoute,
    QueryRequest,
    QueryResponse,
    ReviewReason,
    TranscriptItem,
)
from ..llm.service import ProcessingService


@dataclass(frozen=True, slots=True)
class _PendingAnalysis:
    item: TranscriptItem
    extraction: Any
    route: ProcessingRoute
    expires_at: datetime


def create_processing_router(
    *,
    processor_provider: Callable[..., ProcessingService],
) -> APIRouter:
    """Build all three contract routes around the processing service."""

    router = APIRouter(
        prefix="/v1",
        tags=["processing"],
    )
    pending_analyses: dict[UUID, _PendingAnalysis] = {}

    def discard_expired_previews() -> None:
        now = datetime.now(timezone.utc)
        for proposal_id, proposal in list(pending_analyses.items()):
            if proposal.expires_at <= now:
                del pending_analyses[proposal_id]

    @router.post("/analyze-preview", response_model=AnalysisPreviewResponse)
    def analyze_preview(
        payload: AnalysisPreviewRequest,
        processor: ProcessingService = Depends(processor_provider),
    ) -> AnalysisPreviewResponse:
        """Return a GPT proposal without writing stock, credits, or customers."""

        discard_expired_previews()
        item = TranscriptItem(
            client_event_id=uuid4(),
            transcript=payload.transcript,
            locale=payload.locale,
        )
        resolution = processor.preview(item)
        if not resolution.accepted:
            return AnalysisPreviewResponse(
                status="needs_review",
                route=resolution.route,
                reason=resolution.reason or ReviewReason.MODEL_UNAVAILABLE,
            )
        proposal_id = uuid4()
        pending_analyses[proposal_id] = _PendingAnalysis(
            item=item,
            extraction=resolution.value,
            route=resolution.route,
            expires_at=datetime.now(timezone.utc) + timedelta(minutes=20),
        )
        return AnalysisPreviewResponse(
            status="ready",
            route=resolution.route,
            proposal_id=proposal_id,
            proposal=resolution.value,
        )

    @router.post("/analyze-preview/{proposal_id}/approve", response_model=IngestItemResult)
    def approve_analysis_preview(
        proposal_id: UUID,
        processor: ProcessingService = Depends(processor_provider),
    ) -> IngestItemResult:
        """Persist exactly the proposal the owner just reviewed and approved."""

        discard_expired_previews()
        pending = pending_analyses.get(proposal_id)
        if pending is None:
            return IngestItemResult(
                client_event_id=proposal_id,
                status=IngestStatus.NEEDS_REVIEW,
                route=ProcessingRoute.OFFLINE,
                reason=ReviewReason.TARGET_NOT_FOUND,
            )
        result = processor.approve_preview(
            item=pending.item,
            extraction=pending.extraction,
            route=pending.route,
        )
        if result.status is IngestStatus.SYNCED:
            try:
                processor.commit()
            except Exception:
                processor.rollback()
                return _ingest_commit_failure(result)
            del pending_analyses[proposal_id]
        return result

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
        gateway = SqlAlchemyLedgerGateway(
            session,
            inventory_service=request.app.state.inventory_service,
            google_sheets_mirror=request.app.state.google_sheets_mirror,
        )
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
