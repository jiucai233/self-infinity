"""Speech in and out through OpenAI (contract #35): the Transcriber of plan 10.4 and the
voice the avatar speaks with. Not an LLM prompt, so it is not behind LLMProvider; it needs
OPENAI_API_KEY whatever LLM_PROVIDER is. Without the key the app falls back to the speech
recognition and synthesis of the browser or the phone.
"""

import logging
import time
from collections.abc import Iterator

import httpx

from app.config import settings
from app.i18n import current_language

logger = logging.getLogger(__name__)

TRANSCRIBE_URL = "https://api.openai.com/v1/audio/transcriptions"
SPEECH_URL = "https://api.openai.com/v1/audio/speech"

# Vercel turns away request bodies over 4.5 MB; a minute of browser Opus is ~0.5 MB.
MAX_AUDIO_BYTES = 4_000_000
# The Speech API's own limit.
MAX_SPEECH_CHARS = 4096

# What the formats MediaRecorder and the phones record are called by the Transcriptions API.
_EXTENSIONS = {
    "audio/webm": "webm",
    "audio/ogg": "webm",  # Opus either way; the API reads it by content
    "audio/mp4": "mp4",
    "audio/aac": "m4a",
    "audio/x-m4a": "m4a",
    "audio/m4a": "m4a",
    "audio/mpeg": "mp3",
    "audio/wav": "wav",
    "audio/x-wav": "wav",
}

_VOICE_STYLE = (
    "Speak like a calm, warm mentor sitting across the table: unhurried, clear, "
    "friendly, never theatrical."
)

_client = httpx.Client()


class VoiceUnavailable(RuntimeError):
    """No OPENAI_API_KEY: the client uses the device's own speech."""


class VoiceRejected(ValueError):
    """The request itself is unusable (empty, too long, not audio)."""


class VoiceFailed(RuntimeError):
    """OpenAI answered with an error."""


def available() -> bool:
    return bool(settings.openai_api_key)


def _require_key() -> str:
    if not available():
        raise VoiceUnavailable("voice is not configured")
    return settings.openai_api_key


def _post(url: str, key: str, **kwargs) -> httpx.Response:
    try:
        return _client.post(
            url, headers={"Authorization": f"Bearer {key}"}, timeout=settings.llm_timeout_seconds, **kwargs
        )
    except httpx.HTTPError as e:
        logger.warning("%s failed: %s", url, e)
        raise VoiceFailed(f"could not reach OpenAI: {e}") from e


def _extension(content_type: str | None, filename: str | None) -> str:
    base = (content_type or "").split(";")[0].strip().lower()
    if base in _EXTENSIONS:
        return _EXTENSIONS[base]
    suffix = (filename or "").rsplit(".", 1)[-1].lower()
    if suffix in {"webm", "mp4", "m4a", "mp3", "mpeg", "mpga", "wav", "ogg"}:
        return "webm" if suffix == "ogg" else suffix
    raise VoiceRejected("not an audio recording")


def _languages() -> list[str]:
    """The app's language, and English for the terms people mix in."""
    lang = current_language()
    return [lang] if lang == "en" else [lang, "en"]


def transcribe(audio: bytes, content_type: str | None, filename: str | None = None) -> str:
    """The words in one recorded utterance ('' for silence)."""
    key = _require_key()
    if not audio:
        raise VoiceRejected("empty recording")
    if len(audio) > MAX_AUDIO_BYTES:
        raise VoiceRejected("recording too long")
    ext = _extension(content_type, filename)
    model = settings.transcribe_model
    data: dict[str, str | list[str]] = {"model": model}
    if model.startswith("gpt-transcribe"):
        data["languages[]"] = _languages()
    elif not model.endswith("diarize"):
        data["language"] = current_language()

    start = time.perf_counter()
    response = _post(
        TRANSCRIBE_URL,
        key,
        data=data,
        files={"file": (f"speech.{ext}", audio, f"audio/{ext}")},
    )
    elapsed_ms = (time.perf_counter() - start) * 1000
    if not 200 <= response.status_code < 300:
        logger.warning("transcribe got status=%d after %.0fms", response.status_code, elapsed_ms)
        raise VoiceFailed(f"transcription failed status={response.status_code} body={response.text[:300]}")
    text = (response.json().get("text") or "").strip()
    logger.info("transcribe model=%s bytes=%d chars=%d elapsed_ms=%.0f", model, len(audio), len(text), elapsed_ms)
    return text


def speak(text: str) -> bytes:
    """[text] read aloud, as MP3."""
    key = _require_key()
    text = text.strip()
    if not text:
        raise VoiceRejected("nothing to say")
    if len(text) > MAX_SPEECH_CHARS:
        raise VoiceRejected("text too long")
    body = {
        "model": settings.speech_model,
        "voice": settings.speech_voice,
        "input": text,
        "response_format": "mp3",
    }
    if not settings.speech_model.startswith("tts-1"):
        body["instructions"] = _VOICE_STYLE  # tts-1 takes no instructions

    start = time.perf_counter()
    response = _post(SPEECH_URL, key, json=body)
    elapsed_ms = (time.perf_counter() - start) * 1000
    if not 200 <= response.status_code < 300:
        logger.warning("speak got status=%d after %.0fms", response.status_code, elapsed_ms)
        raise VoiceFailed(f"speech failed status={response.status_code} body={response.text[:300]}")
    logger.info(
        "speak model=%s chars=%d bytes=%d elapsed_ms=%.0f",
        settings.speech_model, len(text), len(response.content), elapsed_ms,
    )
    return response.content


# Streamed speech: raw 16-bit little-endian mono PCM at this rate, played as it arrives.
PCM_RATE = 24000


def speak_stream(text: str) -> Iterator[bytes]:
    """[text] read aloud as PCM chunks while OpenAI is still making the rest.

    The request is sent (and its status checked) before this returns, so a failure is an
    exception here, not a broken stream.
    """
    key = _require_key()
    text = text.strip()
    if not text:
        raise VoiceRejected("nothing to say")
    if len(text) > MAX_SPEECH_CHARS:
        raise VoiceRejected("text too long")
    body = {
        "model": settings.speech_model,
        "voice": settings.speech_voice,
        "input": text,
        "response_format": "pcm",
        "stream_format": "audio",
    }
    if not settings.speech_model.startswith("tts-1"):
        body["instructions"] = _VOICE_STYLE
    request = _client.build_request(
        "POST", SPEECH_URL, headers={"Authorization": f"Bearer {key}"}, json=body, timeout=settings.llm_timeout_seconds
    )
    start = time.perf_counter()
    try:
        response = _client.send(request, stream=True)
    except httpx.HTTPError as e:
        raise VoiceFailed(f"could not reach OpenAI: {e}") from e
    if not 200 <= response.status_code < 300:
        response.read()
        response.close()
        logger.warning("speak_stream got status=%d", response.status_code)
        raise VoiceFailed(f"speech failed status={response.status_code} body={response.text[:300]}")

    def chunks() -> Iterator[bytes]:
        first = True
        try:
            for chunk in response.iter_bytes():
                if first:
                    logger.info("speak_stream first audio after %.0fms", (time.perf_counter() - start) * 1000)
                    first = False
                yield chunk
        except httpx.HTTPError:
            logger.warning("speak_stream broke off", exc_info=True)
        finally:
            response.close()

    return chunks()
