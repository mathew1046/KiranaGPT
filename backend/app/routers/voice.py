"""Protected, memory-only audio transcription endpoint."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, UploadFile, status
from pydantic import BaseModel, ConfigDict, Field

from ..dependencies import require_api_key
from ..llm.adapter import OpenAISettings
from ..llm.transcription import OpenAITranscriptionService


MAX_AUDIO_BYTES = 10 * 1024 * 1024
ALLOWED_CONTENT_TYPES = {"audio/wav", "audio/x-wav", "audio/wave"}


class TranscriptionResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    transcript: str = Field(min_length=1, max_length=4_000)


voice_router = APIRouter(
    prefix="/v1",
    tags=["voice"],
    dependencies=[Depends(require_api_key)],
)


@voice_router.post("/transcribe", response_model=TranscriptionResponse)
async def transcribe_audio(
    request: Request,
    audio: UploadFile,
) -> TranscriptionResponse:
    """Transcribe a short VAD-delimited WAV segment without writing it to disk."""

    content_type = (audio.content_type or "").lower()
    if content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, detail="WAV audio required")

    try:
        payload = await audio.read(MAX_AUDIO_BYTES + 1)
    finally:
        await audio.close()
    if not payload or len(payload) > MAX_AUDIO_BYTES:
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail="Audio segment is too large")

    service = OpenAITranscriptionService(
        OpenAISettings.from_runtime_settings(request.app.state.settings)
    )
    transcript = service.transcribe(
        audio=payload,
        filename=audio.filename or "utterance.wav",
        content_type="audio/wav",
    )
    if transcript is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Transcription is temporarily unavailable",
        )
    return TranscriptionResponse(transcript=transcript)
