"""LLM processing orchestration with safe persistence boundaries.

The service owns the rule that no model result can reach a ledger gateway until
it has both passed Pydantic validation and passed the single confidence router.
It intentionally depends on small protocols rather than backend-core imports,
which keeps this branch independently testable while core is developed.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any, Generic, Protocol, TypeVar
from uuid import UUID

from pydantic import BaseModel

from .adapter import AdapterFailure, ModelRole, StructuredOutcome
from .routing import ConfidenceAction, ConfidenceRouter
from .schemas import (
    CorrectionExtraction,
    CorrectionRequest,
    CorrectionResponse,
    CorrectionStatus,
    IngestItemResult,
    IngestRequest,
    IngestResponse,
    IngestStatus,
    LedgerExtraction,
    ProcessingRoute,
    QueryAnswer,
    QueryRequest,
    QueryResponse,
    QueryStatus,
    ReviewReason,
    ShopCommandType,
    TranscriptItem,
)


TStructured = TypeVar("TStructured", bound=BaseModel)


LEDGER_EXTRACTION_INSTRUCTIONS = """You are the careful voice operations agent for a Kirana shop in India.
Your job is to turn ONE freshly transcribed shop-floor utterance into exactly
one safe shop operation. The shopkeeper will review the result in the app.

Interpretation rules:
- CREDIT_SALE means a named customer took goods now and will owe the shop. CREDIT_PAYMENT
  means the named customer paid down an existing balance. Never treat a cash
  sale as a customer-credit SALE unless the utterance clearly says credit/udhaar
  or an existing customer balance is being changed.
- STOCK_RESTOCK adds the stated quantity to stock; STOCK_SET replaces a stock
  quantity; STOCK_REMOVE removes the named stock item. Use stock operations
  only when they are explicitly requested. Never guess the item or quantity.
- For a credit command amount is an absolute positive INR amount. Never use a prior transaction to
  invent a missing name, item, quantity, or amount.
- The supplied recent transactions are context only: use them to disambiguate
  an explicitly named customer or familiar item. The supplied current_stock is
  read-only context for matching stock names, and customer_balances are
  read-only facts. Never create or duplicate an event from context, and never
  return a historical event instead of the new utterance.
- Preserve ambiguity: if the speech transcript is incomplete, has conflicting
  amounts, names, or intent, use a low confidence rather than guessing.
- Customer credit history is append-only. Do not suggest edits, reversals,
  balances, or more than one operation. Respect the locale and treat all names
  as user-provided text.
- Your JSON ``operation`` MUST be exactly one of: ``credit_sale``,
  ``credit_payment``, ``stock_restock``, ``stock_set``, or ``stock_remove``.
  Credit operations require ``entry_type``, ``customer_name``, and positive
  ``amount``. Stock restock/set operations require ``item_name``, positive
  ``quantity``, and ``unit``. Stock removal requires ``item_name``.
- Include every schema field. Use JSON null for fields that do not apply; for
  stock operations ledger fields must be null. Do not put JSON inside a string.

Return only one object matching the JSON Schema: no prose, markdown, or fields
outside that schema. This JSON is the exact proposed CRUD operation that will
be shown to the owner and, only after approval, used by the backend to update
SQLite."""

CORRECTION_EXTRACTION_INSTRUCTIONS = """Interpret a shopkeeper's correction for the referenced ledger event.
Return cancel only when the event should be fully reversed. Return amend only
when a complete replacement sale or payment is stated; the replacement amount
must be positive and absolute INR. Never invent a replacement. Only return
data covered by the supplied JSON Schema."""

QUERY_INSTRUCTIONS = """Answer the ledger question using only the supplied ledger context.
Give a concise, spoken-friendly answer. If the context does not establish an
answer, use a low confidence. Do not invent balances, customers, dates, or
transactions. Only return data covered by the supplied JSON Schema."""

REVIEW_ANSWER = "Please review the ledger manually."


class StructuredGenerator(Protocol):
    """The small surface used by the coordinator; OpenAIAdapter implements it."""

    def generate(
        self,
        *,
        role: ModelRole,
        output_model: type[TStructured],
        instructions: str,
        payload: Mapping[str, Any],
    ) -> StructuredOutcome[TStructured]: ...


@dataclass(frozen=True, slots=True)
class LedgerAppendResult:
    entry_id: UUID
    duplicate: bool = False


@dataclass(frozen=True, slots=True)
class StockCommandResult:
    item_id: str


@dataclass(frozen=True, slots=True)
class CorrectionAppendResult:
    correction_entry_id: UUID
    replacement_entry_id: UUID | None = None


class ReviewRequiredError(RuntimeError):
    """A persistence adapter can safely request a human decision."""

    def __init__(self, reason: ReviewReason) -> None:
        self.reason = reason
        super().__init__(reason.value)


class LedgerGateway(Protocol):
    """Append-only persistence capability needed by ingest and correction."""

    def append_entry(self, *, item: TranscriptItem, extraction: LedgerExtraction) -> LedgerAppendResult: ...

    def append_offsetting_correction(
        self,
        *,
        request: CorrectionRequest,
        correction: CorrectionExtraction,
    ) -> CorrectionAppendResult: ...

    def apply_stock_command(self, *, extraction: LedgerExtraction) -> StockCommandResult: ...


class QueryContextProvider(Protocol):
    """Provides deterministic local ledger facts; it must not call an LLM."""

    def query_context(self, *, question: str) -> Mapping[str, Any] | None: ...


class CorrectionContextProvider(Protocol):
    """Provides the target event facts needed to interpret a correction."""

    def correction_context(self, *, target_entry_id: UUID) -> Mapping[str, Any] | None: ...


@dataclass(frozen=True, slots=True)
class ModelResolution(Generic[TStructured]):
    """A validated, router-approved model value or a safe review reason."""

    value: TStructured | None
    route: ProcessingRoute
    reason: ReviewReason | None = None

    @property
    def accepted(self) -> bool:
        return self.value is not None and self.reason is None


class ProcessingService:
    """Coordinates validated extraction, confidence routing, and append-only IO."""

    def __init__(
        self,
        generator: StructuredGenerator,
        *,
        confidence_router: ConfidenceRouter | None = None,
        ledger_gateway: LedgerGateway | None = None,
        query_context_provider: QueryContextProvider | None = None,
        correction_context_provider: CorrectionContextProvider | None = None,
    ) -> None:
        self.generator = generator
        self.confidence_router = confidence_router or ConfidenceRouter()
        self.ledger_gateway = ledger_gateway
        self.query_context_provider = query_context_provider
        self.correction_context_provider = correction_context_provider

    def ingest(self, request: IngestRequest) -> IngestResponse:
        """Process each queued text transcript independently and safely."""

        results = [self._ingest_item(item) for item in request.items]
        return IngestResponse(items=results)

    def preview(self, item: TranscriptItem) -> ModelResolution[LedgerExtraction]:
        """Run GPT-5.5 without persisting a proposed shop operation."""

        return self._resolve(
            primary_role=ModelRole.EXTRACTION,
            output_model=LedgerExtraction,
            instructions=LEDGER_EXTRACTION_INSTRUCTIONS,
            payload={
                "role": "Kirana shop voice operations agent",
                "transcript": item.transcript,
                "captured_at": item.captured_at,
                "speaker_id": item.speaker_id,
                "locale": item.locale,
                "recent_transactions": self._recent_transactions(),
            },
        )

    def approve_preview(
        self,
        *,
        item: TranscriptItem,
        extraction: LedgerExtraction,
        route: ProcessingRoute,
    ) -> IngestItemResult:
        """Persist a previously reviewed, validated GPT proposal."""

        if self.ledger_gateway is None:
            return self._ingest_needs_review(
                item,
                route,
                ReviewReason.PERSISTENCE_UNAVAILABLE,
            )
        try:
            if extraction.operation in {
                ShopCommandType.STOCK_RESTOCK,
                ShopCommandType.STOCK_SET,
                ShopCommandType.STOCK_REMOVE,
            }:
                stock_result = self.ledger_gateway.apply_stock_command(extraction=extraction)
                return IngestItemResult(
                    client_event_id=item.client_event_id,
                    status=IngestStatus.SYNCED,
                    route=route,
                    inventory_item_id=stock_result.item_id,
                )
            persisted = self.ledger_gateway.append_entry(item=item, extraction=extraction)
        except ReviewRequiredError as exc:
            return self._ingest_needs_review(item, route, exc.reason)
        except Exception:
            return self._ingest_needs_review(item, route, ReviewReason.PERSISTENCE_UNAVAILABLE)

        if persisted.duplicate:
            return IngestItemResult(
                client_event_id=item.client_event_id,
                status=IngestStatus.DUPLICATE,
                route=route,
                ledger_entry_id=persisted.entry_id,
            )
        return IngestItemResult(
            client_event_id=item.client_event_id,
            status=IngestStatus.SYNCED,
            route=route,
            ledger_entry_id=persisted.entry_id,
        )

    def query(self, request: QueryRequest) -> QueryResponse:
        """Answer only when deterministic ledger facts and confidence are present."""

        if self.query_context_provider is None:
            return self._query_needs_review(ProcessingRoute.OFFLINE, ReviewReason.QUERY_CONTEXT_UNAVAILABLE)
        try:
            context = self.query_context_provider.query_context(question=request.question)
        except Exception:
            return self._query_needs_review(ProcessingRoute.OFFLINE, ReviewReason.QUERY_CONTEXT_UNAVAILABLE)
        if context is None:
            return self._query_needs_review(ProcessingRoute.OFFLINE, ReviewReason.QUERY_CONTEXT_UNAVAILABLE)

        resolution = self._resolve(
            primary_role=ModelRole.QUERY,
            output_model=QueryAnswer,
            instructions=QUERY_INSTRUCTIONS,
            payload={"question": request.question, "locale": request.locale, "ledger_context": context},
        )
        if not resolution.accepted:
            return self._query_needs_review(resolution.route, resolution.reason)
        return QueryResponse(
            status=QueryStatus.ANSWERED,
            route=resolution.route,
            answer=resolution.value.answer,
        )

    def correction(self, request: CorrectionRequest) -> CorrectionResponse:
        """Append a reversal (and optional replacement), never alter history."""

        if self.ledger_gateway is None or self.correction_context_provider is None:
            return self._correction_needs_review(
                request,
                ProcessingRoute.OFFLINE,
                ReviewReason.PERSISTENCE_UNAVAILABLE,
            )
        try:
            target_context = self.correction_context_provider.correction_context(
                target_entry_id=request.target_entry_id
            )
        except ReviewRequiredError as exc:
            return self._correction_needs_review(request, ProcessingRoute.OFFLINE, exc.reason)
        except Exception:
            return self._correction_needs_review(request, ProcessingRoute.OFFLINE, ReviewReason.TARGET_NOT_FOUND)
        if target_context is None:
            return self._correction_needs_review(request, ProcessingRoute.OFFLINE, ReviewReason.TARGET_NOT_FOUND)

        resolution = self._resolve(
            primary_role=ModelRole.EXTRACTION,
            output_model=CorrectionExtraction,
            instructions=CORRECTION_EXTRACTION_INSTRUCTIONS,
            payload={
                "correction_transcript": request.transcript,
                "locale": request.locale,
                "target_ledger_event": target_context,
            },
        )
        if not resolution.accepted:
            return self._correction_needs_review(request, resolution.route, resolution.reason)

        try:
            persisted = self.ledger_gateway.append_offsetting_correction(
                request=request,
                correction=resolution.value,
            )
        except ReviewRequiredError as exc:
            return self._correction_needs_review(request, resolution.route, exc.reason)
        except Exception:
            return self._correction_needs_review(
                request,
                resolution.route,
                ReviewReason.PERSISTENCE_UNAVAILABLE,
            )
        return CorrectionResponse(
            client_correction_id=request.client_correction_id,
            status=CorrectionStatus.CORRECTED,
            route=resolution.route,
            correction_entry_id=persisted.correction_entry_id,
            replacement_entry_id=persisted.replacement_entry_id,
        )

    def commit(self) -> None:
        """Commit through an optional unit-of-work gateway after successful routes."""

        commit = getattr(self.ledger_gateway, "commit", None)
        if callable(commit):
            commit()

    def rollback(self) -> None:
        """Roll back an optional unit-of-work gateway after a route failure."""

        rollback = getattr(self.ledger_gateway, "rollback", None)
        if callable(rollback):
            rollback()

    def _ingest_item(self, item: TranscriptItem) -> IngestItemResult:
        resolution = self.preview(item)
        if not resolution.accepted:
            return self._ingest_needs_review(item, resolution.route, resolution.reason)
        return self.approve_preview(
            item=item,
            extraction=resolution.value,
            route=resolution.route,
        )

    def _resolve(
        self,
        *,
        primary_role: ModelRole,
        output_model: type[TStructured],
        instructions: str,
        payload: Mapping[str, Any],
    ) -> ModelResolution[TStructured]:
        """Validate a primary output and apply the one central escalation policy."""

        primary = self.generator.generate(
            role=primary_role,
            output_model=output_model,
            instructions=instructions,
            payload=payload,
        )
        if not primary.is_success or primary.value is None:
            return ModelResolution(
                value=None,
                route=ProcessingRoute.OFFLINE,
                reason=self._adapter_reason(primary.failure),
            )

        primary_decision = self.confidence_router.decide(
            getattr(primary.value, "confidence", None),
            allow_escalation=True,
        )
        if primary_decision.action is ConfidenceAction.ACCEPT:
            return ModelResolution(value=primary.value, route=ProcessingRoute.PRIMARY)
        if primary_decision.action is ConfidenceAction.NEEDS_REVIEW:
            return ModelResolution(
                value=None,
                route=ProcessingRoute.PRIMARY,
                reason=ReviewReason.CONFIDENCE_BELOW_THRESHOLD,
            )

        escalated = self.generator.generate(
            role=ModelRole.ESCALATION,
            output_model=output_model,
            instructions=instructions,
            payload=payload,
        )
        if not escalated.is_success or escalated.value is None:
            return ModelResolution(
                value=None,
                route=ProcessingRoute.ESCALATED,
                reason=ReviewReason.ESCALATION_FAILED,
            )
        escalation_decision = self.confidence_router.decide(
            getattr(escalated.value, "confidence", None),
            allow_escalation=False,
        )
        if escalation_decision.action is ConfidenceAction.ACCEPT:
            return ModelResolution(value=escalated.value, route=ProcessingRoute.ESCALATED)
        return ModelResolution(
            value=None,
            route=ProcessingRoute.ESCALATED,
            reason=ReviewReason.CONFIDENCE_BELOW_THRESHOLD,
        )

    def _recent_transactions(self) -> Mapping[str, Any]:
        """Bounded evidence for the extraction prompt; failures expose nothing."""

        provider = getattr(self.ledger_gateway, "recent_transactions", None)
        if not callable(provider):
            return {"entries": []}
        try:
            context = provider()
        except Exception:
            return {"entries": []}
        return context if isinstance(context, Mapping) else {"entries": []}

    @staticmethod
    def _adapter_reason(failure: AdapterFailure | None) -> ReviewReason:
        if failure is AdapterFailure.INVALID_MODEL_OUTPUT:
            return ReviewReason.INVALID_MODEL_OUTPUT
        return ReviewReason.MODEL_UNAVAILABLE

    @staticmethod
    def _ingest_needs_review(
        item: TranscriptItem,
        route: ProcessingRoute,
        reason: ReviewReason | None,
    ) -> IngestItemResult:
        return IngestItemResult(
            client_event_id=item.client_event_id,
            status=IngestStatus.NEEDS_REVIEW,
            route=route,
            reason=reason or ReviewReason.MODEL_UNAVAILABLE,
        )

    @staticmethod
    def _query_needs_review(route: ProcessingRoute, reason: ReviewReason | None) -> QueryResponse:
        return QueryResponse(
            status=QueryStatus.NEEDS_REVIEW,
            route=route,
            answer=REVIEW_ANSWER,
            reason=reason or ReviewReason.MODEL_UNAVAILABLE,
        )

    @staticmethod
    def _correction_needs_review(
        request: CorrectionRequest,
        route: ProcessingRoute,
        reason: ReviewReason | None,
    ) -> CorrectionResponse:
        return CorrectionResponse(
            client_correction_id=request.client_correction_id,
            status=CorrectionStatus.NEEDS_REVIEW,
            route=route,
            reason=reason or ReviewReason.MODEL_UNAVAILABLE,
        )
