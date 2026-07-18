"""Transient GPT-audio transcription for one user-controlled recording."""

from __future__ import annotations

import base64
import logging
from typing import Any

from .adapter import OpenAISettings


logger = logging.getLogger(__name__)


class OpenAIAudioTranscriptionService:
    """Send one in-memory WAV recording to GPT-audio without persisting it."""

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
            response = client.chat.completions.create(
                model=self._settings.audio_model,
                modalities=["text", "audio"],
                audio={"voice": "alloy", "format": "wav"},
                store=False,
                messages=[
                    {
                        "role": "developer",
                        "content": (
                            "Transcribe the spoken shop update exactly in its original language. "
                            "Return only the transcript: no explanation, labels, or inferred details."
                        ),
                    },
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "input_audio",
                                "input_audio": {
                                    "data": base64.b64encode(audio).decode("ascii"),
                                    "format": "wav",
                                },
                            }
                        ],
                    },
                ],
            )
            choices = response.get("choices") if isinstance(response, dict) else getattr(response, "choices", None)
            message = (
                choices[0].get("message")
                if isinstance(choices, list) and isinstance(choices[0], dict)
                else getattr(choices[0], "message", None)
                if choices
                else None
            )
            text = message.get("content") if isinstance(message, dict) else getattr(message, "content", None)
            if not text:
                audio_output = message.get("audio") if isinstance(message, dict) else getattr(message, "audio", None)
                text = (
                    audio_output.get("transcript")
                    if isinstance(audio_output, dict)
                    else getattr(audio_output, "transcript", None)
                )
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
