"""Privacy-conscious OpenAI Responses API adapter.

This module is intentionally the only place that knows how to call OpenAI.
It sends text transcripts only, opts out of response storage, validates every
structured response, and returns safe failure codes rather than provider
errors that might accidentally include sensitive input.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass, field
from enum import Enum
import json
import os
import re
from typing import Any, Generic, TypeVar

from pydantic import BaseModel, ValidationError


TStructured = TypeVar("TStructured", bound=BaseModel)


class ModelRole(str, Enum):
    EXTRACTION = "extraction"
    ESCALATION = "escalation"
    QUERY = "query"


class AdapterFailure(str, Enum):
    MODEL_UNAVAILABLE = "model_unavailable"
    INVALID_MODEL_OUTPUT = "invalid_model_output"
    PROVIDER_FAILURE = "provider_failure"


@dataclass(frozen=True, slots=True)
class OpenAISettings:
    """Environment-configured model selection without exposing API secrets."""

    api_key: str | None = field(default=None, repr=False)
    audio_model: str = "gpt-audio-1.5"
    extraction_model: str = "gpt-5.5"
    escalation_model: str = "gpt-5.5"
    query_model: str = "gpt-5.5"
    max_attempts: int = 2

    def __post_init__(self) -> None:
        if self.max_attempts < 1 or self.max_attempts > 3:
            raise ValueError("max_attempts must be between 1 and 3")
        if not self.audio_model or not all(self.model_for(role) for role in ModelRole):
            raise ValueError("OpenAI model names must not be empty")

    @classmethod
    def from_env(cls, environ: Mapping[str, str] | None = None) -> "OpenAISettings":
        """Load public configuration without ever logging the API key."""

        source = os.environ if environ is None else environ
        attempts_text = source.get("OPENAI_MAX_ATTEMPTS", "2").strip()
        try:
            attempts = int(attempts_text)
        except ValueError:
            attempts = 2
        return cls(
            api_key=(source.get("OPENAI_API_KEY") or "").strip() or None,
            audio_model=(source.get("OPENAI_AUDIO_MODEL") or "gpt-audio-1.5").strip(),
            extraction_model=(source.get("OPENAI_EXTRACTION_MODEL") or "gpt-5.5").strip(),
            escalation_model=(source.get("OPENAI_ESCALATION_MODEL") or "gpt-5.5").strip(),
            query_model=(source.get("OPENAI_QUERY_MODEL") or "gpt-5.5").strip(),
            max_attempts=attempts,
        )

    @classmethod
    def from_runtime_settings(cls, settings: object) -> "OpenAISettings":
        """Adapt backend-core settings without importing backend-core itself."""

        return cls(
            api_key=getattr(settings, "openai_api_key", None),
            audio_model=getattr(settings, "openai_audio_model", "gpt-audio-1.5"),
            extraction_model=getattr(settings, "openai_extraction_model", "gpt-5.5"),
            escalation_model=getattr(settings, "openai_escalation_model", "gpt-5.5"),
            query_model=getattr(settings, "openai_query_model", "gpt-5.5"),
        )

    def model_for(self, role: ModelRole) -> str:
        if role is ModelRole.EXTRACTION:
            return self.extraction_model
        if role is ModelRole.ESCALATION:
            return self.escalation_model
        return self.query_model


@dataclass(frozen=True, slots=True)
class StructuredOutcome(Generic[TStructured]):
    """A parsed response or a privacy-safe deterministic fallback outcome."""

    value: TStructured | None
    model: str | None
    attempts: int
    failure: AdapterFailure | None = None
    fallback_used: bool = False

    @property
    def is_success(self) -> bool:
        return self.value is not None and self.failure is None


class OpenAIAdapter:
    """Call the Responses API with strict JSON schema output and bounded retry.

    The adapter has no logger by design: it must never log credentials, raw
    audio (which it never accepts), or transcript text.  When no key, SDK, or
    provider response is available, its deterministic fallback contains no
    extraction and therefore cannot create a transaction.
    """

    def __init__(self, settings: OpenAISettings | None = None, *, client: Any | None = None) -> None:
        self.settings = settings or OpenAISettings.from_env()
        self._client = client

    def generate(
        self,
        *,
        role: ModelRole,
        output_model: type[TStructured],
        instructions: str,
        payload: Mapping[str, Any],
    ) -> StructuredOutcome[TStructured]:
        """Return a validated schema object or a safe, deterministic failure."""

        model = self.settings.model_for(role)
        client = self._get_client()
        if client is None:
            return self._offline_fallback(model=model, attempts=0, failure=AdapterFailure.MODEL_UNAVAILABLE)

        last_failure = AdapterFailure.PROVIDER_FAILURE
        for attempt in range(1, self.settings.max_attempts + 1):
            try:
                response = client.responses.create(
                    model=model,
                    input=json.dumps(payload, ensure_ascii=False, default=str),
                    instructions=self._instructions_for_attempt(instructions, attempt),
                    text={
                        "format": {
                            "type": "json_schema",
                            "name": _schema_name(output_model),
                            "strict": True,
                            "schema": output_model.model_json_schema(),
                        }
                    },
                    # Transcript-bearing requests must not be stored by OpenAI.
                    store=False,
                    max_output_tokens=700,
                )
                parsed = output_model.model_validate_json(_response_text(response))
                return StructuredOutcome(value=parsed, model=model, attempts=attempt)
            except (ValidationError, ValueError, TypeError, KeyError, AttributeError):
                # Deliberately do not expose or log malformed response content.
                last_failure = AdapterFailure.INVALID_MODEL_OUTPUT
            except Exception:
                # Transport/API exceptions can include request details; retain only
                # this stable category and retry a fixed number of times.
                last_failure = AdapterFailure.PROVIDER_FAILURE

        return self._offline_fallback(
            model=model,
            attempts=self.settings.max_attempts,
            failure=last_failure,
        )

    def _get_client(self) -> Any | None:
        if self._client is not None:
            return self._client
        if self.settings.api_key is None:
            return None
        try:
            # Keep the SDK optional for schema-only / offline deployments.
            from openai import OpenAI

            self._client = OpenAI(api_key=self.settings.api_key)
            return self._client
        except Exception:
            return None

    @staticmethod
    def _instructions_for_attempt(instructions: str, attempt: int) -> str:
        if attempt == 1:
            return instructions
        return (
            f"{instructions}\n\n"
            "Return only a JSON object that exactly satisfies the supplied JSON Schema. "
            "Do not include prose, Markdown, or fields outside that schema."
        )

    @staticmethod
    def _offline_fallback(
        *, model: str | None,
        attempts: int,
        failure: AdapterFailure,
    ) -> StructuredOutcome[Any]:
        """A deterministic empty outcome; callers must map it to needs_review."""

        return StructuredOutcome(
            value=None,
            model=model,
            attempts=attempts,
            failure=failure,
            fallback_used=True,
        )


def _schema_name(output_model: type[BaseModel]) -> str:
    """Create a stable Responses API schema identifier from a model class."""

    words = re.sub(r"(?<!^)(?=[A-Z])", "_", output_model.__name__).lower()
    return re.sub(r"[^a-z0-9_]+", "_", words).strip("_") or "structured_output"


def _response_text(response: Any) -> str:
    """Get text from the SDK response without serializing it into logs/errors."""

    if isinstance(response, Mapping):
        output_text = response.get("output_text")
    else:
        output_text = getattr(response, "output_text", None)
    if isinstance(output_text, str) and output_text.strip():
        return output_text

    # Fakes and some SDK response representations expose output content only.
    output = response.get("output") if isinstance(response, Mapping) else getattr(response, "output", None)
    if isinstance(output, list):
        for item in output:
            content = item.get("content") if isinstance(item, Mapping) else getattr(item, "content", None)
            if not isinstance(content, list):
                continue
            for part in content:
                part_type = part.get("type") if isinstance(part, Mapping) else getattr(part, "type", None)
                text = part.get("text") if isinstance(part, Mapping) else getattr(part, "text", None)
                if part_type == "output_text" and isinstance(text, str) and text.strip():
                    return text
    raise ValueError("response did not contain structured output text")
