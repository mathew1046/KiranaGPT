"""Transient Whisper transcription for one user-controlled recording."""

from __future__ import annotations

from io import BytesIO
import logging
from typing import Any

from .adapter import OpenAISettings


logger = logging.getLogger(__name__)


class OpenAIAudioTranscriptionService:
    """Send one in-memory WAV recording to Whisper without persisting it."""

    def __init__(self, settings: OpenAISettings, *, client: Any | None = None) -> None:
        self._settings = settings
        self._client = client

    def transcribe(self, *, audio: bytes, filename: str, content_type: str) -> str | None:
        if not audio:
            return None
        client = self._get_client()
        if client is None:
            return None
        try:
            # The Audio Transcriptions API is purpose-built for Whisper.  Keep
            # the recording in memory and give the SDK a filename for multipart
            # upload; neither audio nor the transcript is written to disk here.
            upload = BytesIO(audio)
            upload.name = filename
            response = client.audio.transcriptions.create(
                model=self._settings.audio_model,
                file=upload,
                response_format="json",
            )
            text = response.get("text") if isinstance(response, dict) else getattr(response, "text", None)
            return text.strip() if isinstance(text, str) and text.strip() else None
        except Exception as exc:
            # Do not log provider messages: they can include request metadata.
            logger.warning("OpenAI audio transcription failed (%s)", type(exc).__name__)
            return None

    def _get_client(self) -> Any | None:
        if self._client is not None:
            return self._client
        if self._settings.api_key is None:
            return None
        try:
            from openai import OpenAI

            self._client = OpenAI(api_key=self._settings.api_key)
            return self._client
        except Exception:
            return None
