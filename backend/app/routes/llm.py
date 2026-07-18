"""Backend-core compatibility hook for the LLM processing routes.

Keep this adapter tiny: the feature implementation remains in
``backend.app.routers.processing`` as its standalone, injectable factory.
"""

from __future__ import annotations

from fastapi import APIRouter

from ..routers.processing import create_core_processing_router


def create_llm_router() -> APIRouter:
    """Build the protected processing router once backend-core is available."""

    return create_core_processing_router()
