from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal
import json
from types import SimpleNamespace
from uuid import uuid4

import pytest
from pydantic import ValidationError

from backend.app.llm.adapter import (
    AdapterFailure,
    ModelRole,
    OpenAIAdapter,
    OpenAISettings,
    StructuredOutcome,
)
from backend.app.llm.routing import ConfidenceAction, ConfidenceRouter
from backend.app.llm.schemas import (
    CorrectionAction,
    CorrectionExtraction,
    CorrectionRequest,
    IngestRequest,
    IngestStatus,
    LedgerEventType,
    LedgerExtraction,
    ProcessingRoute,
    ReviewReason,
)
from backend.app.llm.service import (
    CorrectionAppendResult,
    LedgerAppendResult,
    ProcessingService,
)


def extraction(*, confidence: float = 0.96) -> LedgerExtraction:
    return LedgerExtraction(
        entry_type=LedgerEventType.SALE,
        customer_name="Ravi",
        amount=Decimal("125.50"),
        description="Rice",
        item_name="Rice",
        quantity=Decimal("1"),
        unit="kg",
        confidence=confidence,
    )


def extraction_json(*, confidence: float = 0.96) -> str:
    return json.dumps(
        {
            "entry_type": "sale",
            "customer_name": "Ravi",
            "amount": "125.50",
            "description": "Rice",
            "item_name": "Rice",
            "quantity": "1",
            "unit": "kg",
            "confidence": confidence,
        }
    )


class FakeResponses:
    def __init__(self, outputs: list[object]) -> None:
        self.outputs = list(outputs)
        self.calls: list[dict[str, object]] = []

    def create(self, **kwargs: object) -> object:
        self.calls.append(kwargs)
        output = self.outputs.pop(0)
        if isinstance(output, Exception):
            raise output
        return SimpleNamespace(output_text=output)


class FakeClient:
    def __init__(self, outputs: list[object]) -> None:
        self.responses = FakeResponses(outputs)


class FakeGenerator:
    def __init__(self, outcomes: list[StructuredOutcome[object]]) -> None:
        self.outcomes = list(outcomes)
        self.roles: list[ModelRole] = []

    def generate(self, **kwargs: object) -> StructuredOutcome[object]:
        self.roles.append(kwargs["role"])  # type: ignore[arg-type]
        return self.outcomes.pop(0)


@dataclass
class FakeGateway:
    entry_id: object

    def __post_init__(self) -> None:
        self.appended: list[object] = []
        self.corrections: list[object] = []

    def append_entry(self, *, item: object, extraction: object) -> LedgerAppendResult:
        self.appended.append((item, extraction))
        return LedgerAppendResult(entry_id=self.entry_id)  # type: ignore[arg-type]

    def append_offsetting_correction(
        self,
        *,
        request: object,
        correction: object,
    ) -> CorrectionAppendResult:
        self.corrections.append((request, correction))
        return CorrectionAppendResult(correction_entry_id=self.entry_id)  # type: ignore[arg-type]

    def correction_context(self, *, target_entry_id: object) -> dict[str, str]:
        return {"entry_id": str(target_entry_id), "entry_type": "sale", "signed_amount": "125.50"}


def test_confidence_router_has_one_bounded_escalation_path() -> None:
    router = ConfidenceRouter(accept_threshold=0.90, escalation_floor=0.55)

    assert router.decide(0.90).action is ConfidenceAction.ACCEPT
    assert router.decide(0.70).action is ConfidenceAction.ESCALATE
    assert router.decide(0.54).action is ConfidenceAction.NEEDS_REVIEW
    assert router.decide(0.70, allow_escalation=False).action is ConfidenceAction.NEEDS_REVIEW
    assert router.decide(None).action is ConfidenceAction.NEEDS_REVIEW

    with pytest.raises(ValueError):
        ConfidenceRouter(accept_threshold=0.55, escalation_floor=0.55)


def test_request_rejects_audio_and_extraction_rejects_zero_value() -> None:
    item = {
        "client_event_id": str(uuid4()),
        "transcript": "Ravi took rice for 125 rupees",
        "audio_base64": "must-not-be-accepted",
    }
    with pytest.raises(ValidationError):
        IngestRequest.model_validate({"items": [item]})

    with pytest.raises(ValidationError):
        LedgerExtraction(
            entry_type=LedgerEventType.SALE,
            customer_name="Ravi",
            amount=Decimal("0"),
            description=None,
            item_name=None,
            quantity=None,
            unit=None,
            confidence=0.99,
        )


def test_openai_adapter_uses_strict_schema_store_false_and_env_model() -> None:
    client = FakeClient([extraction_json()])
    settings = OpenAISettings.from_env(
        {
            "OPENAI_API_KEY": "not-for-output",
            "OPENAI_EXTRACTION_MODEL": "configured-extractor",
            "OPENAI_ESCALATION_MODEL": "configured-escalator",
            "OPENAI_QUERY_MODEL": "configured-query",
        }
    )
    adapter = OpenAIAdapter(settings, client=client)

    outcome = adapter.generate(
        role=ModelRole.EXTRACTION,
        output_model=LedgerExtraction,
        instructions="Extract a transaction.",
        payload={"transcript": "Ravi took rice for 125 rupees"},
    )

    assert outcome.is_success
    assert outcome.model == "configured-extractor"
    assert outcome.value == extraction()
    assert "not-for-output" not in repr(settings)
    call = client.responses.calls[0]
    assert call["store"] is False
    assert call["model"] == "configured-extractor"
    assert call["text"]["format"]["type"] == "json_schema"  # type: ignore[index]
    assert call["text"]["format"]["strict"] is True  # type: ignore[index]


def test_openai_adapter_retries_invalid_json_then_returns_validated_output() -> None:
    client = FakeClient(["not json", extraction_json(confidence=0.98)])
    adapter = OpenAIAdapter(OpenAISettings(api_key="test-key"), client=client)

    outcome = adapter.generate(
        role=ModelRole.EXTRACTION,
        output_model=LedgerExtraction,
        instructions="Extract a transaction.",
        payload={"transcript": "Ravi took rice for 125 rupees"},
    )

    assert outcome.is_success
    assert outcome.attempts == 2
    assert len(client.responses.calls) == 2
    assert "Return only a JSON object" in client.responses.calls[1]["instructions"]  # type: ignore[operator]


def test_openai_adapter_missing_key_uses_empty_offline_fallback() -> None:
    outcome = OpenAIAdapter(OpenAISettings()).generate(
        role=ModelRole.EXTRACTION,
        output_model=LedgerExtraction,
        instructions="Extract a transaction.",
        payload={"transcript": "Ravi took rice for 125 rupees"},
    )

    assert outcome.value is None
    assert outcome.failure is AdapterFailure.MODEL_UNAVAILABLE
    assert outcome.fallback_used is True
    assert outcome.attempts == 0


def test_low_confidence_escalates_once_before_append() -> None:
    entry_id = uuid4()
    generator = FakeGenerator(
        [
            StructuredOutcome(value=extraction(confidence=0.70), model="small", attempts=1),
            StructuredOutcome(value=extraction(confidence=0.97), model="large", attempts=1),
        ]
    )
    gateway = FakeGateway(entry_id)
    service = ProcessingService(generator, ledger_gateway=gateway)  # type: ignore[arg-type]
    request = IngestRequest.model_validate(
        {"items": [{"client_event_id": str(uuid4()), "transcript": "Ravi took rice for 125 rupees"}]}
    )

    result = service.ingest(request)

    assert result.items[0].status is IngestStatus.SYNCED
    assert result.items[0].route is ProcessingRoute.ESCALATED
    assert generator.roles == [ModelRole.EXTRACTION, ModelRole.ESCALATION]
    assert len(gateway.appended) == 1


def test_invalid_extraction_never_calls_ledger_gateway() -> None:
    gateway = FakeGateway(uuid4())
    generator = FakeGenerator(
        [
            StructuredOutcome(
                value=None,
                model="small",
                attempts=2,
                failure=AdapterFailure.INVALID_MODEL_OUTPUT,
                fallback_used=True,
            )
        ]
    )
    service = ProcessingService(generator, ledger_gateway=gateway)  # type: ignore[arg-type]
    request = IngestRequest.model_validate(
        {"items": [{"client_event_id": str(uuid4()), "transcript": "unclear"}]}
    )

    result = service.ingest(request)

    assert result.items[0].status is IngestStatus.NEEDS_REVIEW
    assert result.items[0].reason is ReviewReason.INVALID_MODEL_OUTPUT
    assert gateway.appended == []


def test_correction_uses_append_only_gateway_operation() -> None:
    correction = CorrectionExtraction(
        action=CorrectionAction.CANCEL,
        replacement=None,
        confidence=0.99,
    )
    entry_id = uuid4()
    generator = FakeGenerator([StructuredOutcome(value=correction, model="small", attempts=1)])
    gateway = FakeGateway(entry_id)
    service = ProcessingService(
        generator,  # type: ignore[arg-type]
        ledger_gateway=gateway,
        correction_context_provider=gateway,
    )
    request = CorrectionRequest(
        client_correction_id=uuid4(),
        target_entry_id=uuid4(),
        transcript="Cancel the last sale",
    )

    result = service.correction(request)

    assert result.status.value == "corrected"
    assert result.correction_entry_id == entry_id
    assert len(gateway.corrections) == 1
    assert not hasattr(gateway, "update_entry")
