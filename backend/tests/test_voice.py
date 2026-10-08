"""Voice (contract #35): OpenAI speech to text and text to speech, and the fallback without a key."""

import httpx
import pytest

from app.config import settings
from app.services import voice


class _Recorder:
    """Stands in for OpenAI: records each request and answers with [response]."""

    def __init__(self, response: httpx.Response | Exception):
        self.response = response
        self.requests: list[httpx.Request] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        if isinstance(self.response, Exception):
            raise self.response
        return self.response


@pytest.fixture(name="openai")
def openai_fixture(monkeypatch):
    def install(response):
        recorder = _Recorder(response)
        monkeypatch.setattr(settings, "openai_api_key", "sk-test")
        monkeypatch.setattr(voice, "_client", httpx.Client(transport=httpx.MockTransport(recorder)))
        return recorder

    return install


def test_without_a_key_voice_is_unavailable(client):
    assert client.get("/api/voice").json() == {"available": False}
    assert client.post("/api/voice/transcribe", files={"file": ("a.webm", b"x", "audio/webm")}).status_code == 503
    assert client.post("/api/voice/speech", json={"text": "hi"}).status_code == 503


def test_transcribe_sends_the_recording_and_the_languages(client, openai):
    calls = openai(httpx.Response(200, json={"text": " 判别式是 b²−4ac "}))
    assert client.get("/api/voice").json() == {"available": True}

    response = client.post(
        "/api/voice/transcribe",
        files={"file": ("blob", b"opus-bytes", "audio/webm;codecs=opus")},
        headers={"Accept-Language": "zh"},
    )

    assert response.status_code == 200
    assert response.json() == {"text": "判别式是 b²−4ac"}
    request = calls.requests[0]
    assert str(request.url) == voice.TRANSCRIBE_URL
    assert request.headers["Authorization"] == "Bearer sk-test"
    body = request.content
    assert b'name="model"\r\n\r\ngpt-transcribe' in body
    # Chinese, and English for the terms mixed in.
    assert b'name="languages[]"\r\n\r\nzh' in body
    assert b'name="languages[]"\r\n\r\nen' in body
    assert b'filename="speech.webm"' in body
    assert b"opus-bytes" in body


def test_older_transcribe_models_take_one_language(client, openai, monkeypatch):
    calls = openai(httpx.Response(200, json={"text": "hello"}))
    monkeypatch.setattr(settings, "transcribe_model", "gpt-4o-transcribe")
    client.post("/api/voice/transcribe", files={"file": ("a.m4a", b"x", "audio/mp4")}, headers={"Accept-Language": "ko"})
    body = calls.requests[0].content
    assert b'name="language"\r\n\r\nko' in body
    assert b"languages[]" not in body
    assert b'filename="speech.mp4"' in body


def test_transcribe_rejects_what_is_not_a_recording(client, openai):
    calls = openai(httpx.Response(200, json={"text": "x"}))
    assert client.post("/api/voice/transcribe", files={"file": ("a.webm", b"", "audio/webm")}).status_code == 400
    assert client.post("/api/voice/transcribe", files={"file": ("a.txt", b"x", "text/plain")}).status_code == 400
    too_long = b"x" * (voice.MAX_AUDIO_BYTES + 1)
    assert client.post("/api/voice/transcribe", files={"file": ("a.webm", too_long, "audio/webm")}).status_code == 400
    assert calls.requests == []


def test_an_openai_error_is_a_502(client, openai):
    openai(httpx.Response(429, json={"error": {"message": "rate limited"}}))
    assert client.post("/api/voice/transcribe", files={"file": ("a.webm", b"x", "audio/webm")}).status_code == 502
    openai(httpx.ConnectError("down"))
    assert client.post("/api/voice/speech", json={"text": "hi"}).status_code == 502


def test_speech_returns_mp3_in_the_mentor_voice(client, openai):
    calls = openai(httpx.Response(200, content=b"ID3-mp3-bytes"))

    response = client.post("/api/voice/speech", json={"text": "  What does the discriminant tell you?  "})

    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/mpeg"
    assert response.content == b"ID3-mp3-bytes"
    sent = httpx.Response(200, content=calls.requests[0].content).json()
    assert sent["model"] == "gpt-4o-mini-tts"
    assert sent["voice"] == "marin"
    assert sent["input"] == "What does the discriminant tell you?"
    assert sent["response_format"] == "mp3"
    assert "mentor" in sent["instructions"]


def test_tts_1_gets_no_instructions(client, openai, monkeypatch):
    calls = openai(httpx.Response(200, content=b"mp3"))
    monkeypatch.setattr(settings, "speech_model", "tts-1")
    client.post("/api/voice/speech", json={"text": "hi"})
    assert "instructions" not in httpx.Response(200, content=calls.requests[0].content).json()


def test_speech_limits_the_text(client, openai):
    openai(httpx.Response(200, content=b"mp3"))
    assert client.post("/api/voice/speech", json={"text": ""}).status_code == 422
    assert client.post("/api/voice/speech", json={"text": "x" * 4097}).status_code == 422
    assert client.post("/api/voice/speech", json={"text": "   "}).status_code == 400


def test_a_recording_without_an_audio_type_is_read_by_its_extension(client, openai):
    calls = openai(httpx.Response(200, json={"text": "hi"}))
    # What the app's multipart upload sends: no content type, the format in the name.
    response = client.post("/api/voice/transcribe", files={"file": ("speech.mp4", b"x", "application/octet-stream")})
    assert response.status_code == 200
    assert b'filename="speech.mp4"\r\nContent-Type: audio/mp4' in calls.requests[0].content


# ---------------------------------------------------------------- streamed speech, live sessions (#35)

def test_streamed_speech_is_raw_pcm_as_it_arrives(client, openai):
    calls = openai(httpx.Response(200, content=b"\x01\x00\x02\x00"))
    response = client.post("/api/voice/speech/stream", json={"text": "Go on."})
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("audio/pcm")
    assert response.content == b"\x01\x00\x02\x00"
    sent = httpx.Response(200, content=calls.requests[0].content).json()
    assert (sent["response_format"], sent["stream_format"]) == ("pcm", "audio")


def test_a_failing_stream_is_a_502_before_any_audio(client, openai):
    openai(httpx.Response(500, json={"error": "boom"}))
    assert client.post("/api/voice/speech/stream", json={"text": "Go on."}).status_code == 502


@pytest.fixture(name="realtime")
def realtime_fixture(monkeypatch):
    from app.services import realtime

    recorder = _Recorder(httpx.Response(201, text="v=0 answer"))
    monkeypatch.setattr(settings, "openai_api_key", "sk-test")
    monkeypatch.setattr(realtime, "_client", httpx.Client(transport=httpx.MockTransport(recorder)))
    return recorder


def _session_of(request: httpx.Request) -> dict:
    import json
    import re

    body = request.content.decode()
    match = re.search(r'name="session"\r\n\r\n(.*?)\r\n--', body, re.S)
    return json.loads(match.group(1))


def test_the_guide_session_carries_the_player_and_the_tools(client, realtime, monkeypatch):
    monkeypatch.setattr(settings, "openai_api_key", "")  # the course from the mock LLM
    client.post("/api/skills/generate", json={"topic": "math"})
    client.put("/api/profile", json={"identity": "I am the type of person who explains first"})
    monkeypatch.setattr(settings, "openai_api_key", "sk-test")

    response = client.post(
        "/api/voice/realtime/guide",
        content="v=0 offer",
        headers={"Content-Type": "application/sdp", "Accept-Language": "zh"},
    )

    assert response.status_code == 201
    assert response.headers["content-type"].startswith("application/sdp")
    assert response.text == "v=0 answer"
    request = realtime.requests[0]
    assert str(request.url) == "https://api.openai.com/v1/realtime/calls"
    assert request.headers["Authorization"] == "Bearer sk-test"
    assert len(request.headers["OpenAI-Safety-Identifier"]) == 64
    assert b'name="sdp"\r\n\r\nv=0 offer' in request.content
    session = _session_of(request)
    assert session["type"] == "realtime"
    assert session["model"] == "gpt-realtime-2.1"
    assert session["audio"]["output"]["voice"] == "marin"
    assert session["audio"]["input"]["turn_detection"] == {"type": "semantic_vad"}
    assert session["audio"]["input"]["transcription"]["languages"] == ["zh", "en"]
    assert {t["name"] for t in session["tools"]} == {
        "log_checkin", "build_course", "open_node", "open_map", "todays_plan", "briefing"
    }
    assert "explains first" in session["instructions"]
    assert "Discriminant" in session["instructions"]  # a node of the course
    assert "Simplified Chinese" in session["instructions"]


def test_the_transcription_session_waits_for_the_browser_to_commit(client, realtime):
    response = client.post("/api/voice/realtime/transcribe", content="v=0 offer")
    assert response.status_code == 201
    session = _session_of(realtime.requests[0])
    assert session["type"] == "transcription"
    assert session["audio"]["input"]["turn_detection"] is None
    assert session["audio"]["input"]["transcription"]["model"] == "gpt-live-transcribe"


def test_live_sessions_need_a_key_and_an_offer(client, realtime, monkeypatch):
    assert client.post("/api/voice/realtime/transcribe", content="").status_code == 400
    assert client.post("/api/voice/realtime/transcribe", content="x" * 70_000).status_code == 400
    realtime.response = httpx.Response(400, json={"error": "bad sdp"})
    assert client.post("/api/voice/realtime/transcribe", content="v=0").status_code == 502
    monkeypatch.setattr(settings, "openai_api_key", "")
    assert client.post("/api/voice/realtime/guide", content="v=0").status_code == 503
    assert client.post("/api/voice/realtime/transcribe", content="v=0").status_code == 503
