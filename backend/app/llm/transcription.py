"""Transient OpenAI Whisper transcription for VAD-delimited audio."""

from __future__ import annotations

from typing import Any

from .adapter import OpenAISettings


class OpenAITranscriptionService:
    """Send one in-memory audio segment to Whisper without persisting it."""

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
            response = client.audio.transcriptions.create(
                model=self._settings.transcription_model,
                file=(filename, audio, content_type),
            )
            text = response.get("text") if isinstance(response, dict) else getattr(response, "text", None)
            return text.strip() if isinstance(text, str) and text.strip() else None
        except Exception:
            # Provider failures may contain audio/request metadata; never surface it.
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
