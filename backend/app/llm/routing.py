"""The single confidence policy for all LLM-derived results."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import math


class ConfidenceAction(str, Enum):
    """What the caller must do with a validated model result."""

    ACCEPT = "accept"
    ESCALATE = "escalate"
    NEEDS_REVIEW = "needs_review"


@dataclass(frozen=True, slots=True)
class ConfidenceDecision:
    """An explainable decision that does not expose model input or output."""

    action: ConfidenceAction
    reason: str


@dataclass(frozen=True, slots=True)
class ConfidenceRouter:
    """One deterministic policy for accepting or escalating model output.

    A result at or above ``accept_threshold`` may drive a mutation.  A valid
    result in the middle band receives exactly one pass through the escalation
    model.  Anything below ``escalation_floor``, missing, or non-finite goes
    straight to human review.  Callers must pass ``allow_escalation=False``
    for the second pass, so this policy cannot create retry loops.
    """

    accept_threshold: float = 0.90
    escalation_floor: float = 0.55

    def __post_init__(self) -> None:
        thresholds = (self.accept_threshold, self.escalation_floor)
        if any(not math.isfinite(value) for value in thresholds):
            raise ValueError("confidence thresholds must be finite")
        if not 0 <= self.escalation_floor < self.accept_threshold <= 1:
            raise ValueError("thresholds must satisfy 0 <= floor < accept <= 1")

    def decide(self, confidence: float | None, *, allow_escalation: bool = True) -> ConfidenceDecision:
        """Route a confidence score without making a persistence decision."""

        if confidence is None or not math.isfinite(confidence):
            return ConfidenceDecision(ConfidenceAction.NEEDS_REVIEW, "missing_confidence")
        if confidence >= self.accept_threshold:
            return ConfidenceDecision(ConfidenceAction.ACCEPT, "confidence_accepted")
        if allow_escalation and confidence >= self.escalation_floor:
            return ConfidenceDecision(ConfidenceAction.ESCALATE, "confidence_escalation_required")
        return ConfidenceDecision(ConfidenceAction.NEEDS_REVIEW, "confidence_below_threshold")
