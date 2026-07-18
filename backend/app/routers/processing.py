"""Protected HTTP routes for transcript processing, query, and correction.

The generic factory accepts injected dependencies so the module has no import
dependency on backend-core.  ``create_core_processing_router`` is the narrow
integration hook used after backend-core is available.
"""

from __future__ import annotations

from collections.abc import Callable
import secrets
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, status

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


class AuthenticationError(ValueError):
    """Raised by the pure bearer-token checker without leaking token details."""


def verify_bearer_token(authorization: str | None, expected_api_key: str) -> None:
    """Validate exactly ``Authorization: Bearer <APP_API_KEY>`` safely."""

    scheme, separator, supplied_key = (authorization or "").partition(" ")
    if (
        not expected_api_key
        or not separator
        or scheme.lower() != "bearer"
        or not supplied_key
        or not secrets.compare_digest(supplied_key, expected_api_key)
    ):
        raise AuthenticationError("invalid or missing API key")


def create_bearer_auth_dependency(expected_api_key: str) -> Callable[..., None]:
    """Adapt the pure checker to FastAPI without exposing the configured key."""

    def require_api_key(request: Request) -> None:
        try:
            verify_bearer_token(request.headers.get("authorization"), expected_api_key)
        except AuthenticationError as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or missing API key",
                headers={"WWW-Authenticate": "Bearer"},
            ) from exc

    return require_api_key


def create_processing_router(
    *,
    processor_provider: Callable[..., ProcessingService],
    auth_dependency: Callable[..., Any],
) -> APIRouter:
    """Build all three contract routes around injected auth and processing."""

    router = APIRouter(
        prefix="/v1",
        tags=["processing"],
        dependencies=[Depends(auth_dependency)],
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
    returned router.  The core's existing ``require_api_key`` dependency is
    reused, so every `/v1` processing endpoint has identical bearer auth.
    """

    from ..dependencies import get_db, require_api_key

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
        auth_dependency=require_api_key,
    )


def _ingest_commit_failure(item: IngestItemResult) -> IngestItemResult:
    """Do not report a sync when its transaction could not be committed."""

    return IngestItemResult(
        client_event_id=item.client_event_id,
        status=IngestStatus.NEEDS_REVIEW,
        route=item.route if item.route is not ProcessingRoute.PRIMARY else ProcessingRoute.OFFLINE,
        reason=ReviewReason.PERSISTENCE_UNAVAILABLE,
    )
