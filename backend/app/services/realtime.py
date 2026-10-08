"""Live voice over WebRTC (contract #35): the browser's SDP offer goes through here to OpenAI's
Realtime API with a session we configure, and the SDP answer goes back. Audio then flows
browser ↔ OpenAI directly; JSON events travel on the connection's data channel. The key and
the session (instructions, tools) never reach the browser.

Two sessions:
- guide: the home page's Guide as one speech-to-speech model (gpt-realtime). It talks itself
  and acts through tools the browser runs on /api/chat/act (the front desk's intents).
- transcribe: live transcription for the audit (gpt-live-transcribe): words appear while the
  learner speaks; the browser commits each turn when it hears a pause, and the Auditor judges.
"""

import hashlib
import json
import logging
import time

import httpx
from sqlmodel import Session, col, select

from app.config import settings
from app.i18n import current_language, language_instruction
from app.models import ChatMessage, Course, SkillNode
from app.services import checkin as checkin_service
from app.services import game_profile
from app.services.courses import live_nodes
from app.services.voice import VoiceFailed, VoiceRejected, _require_key

logger = logging.getLogger(__name__)

CALLS_URL = "https://api.openai.com/v1/realtime/calls"
MAX_SDP_BYTES = 64_000
RECENT_MESSAGES = 12
MAX_NODES = 80

_client = httpx.Client()

GUIDE_INSTRUCTIONS = """\
You are the Guide in Self-Infinity, a learning game where the player levels up by proving they
understand things: they explain them in their own words and an Auditor judges.

You are talking with the player by voice. Speak like a calm, warm mentor: one or two short
sentences a turn, plain words, no lists, no markdown. Ask one question at a time.

You act only through your tools; never claim you did something you did not call a tool for.
- log_checkin: the player tells you about their day or condition (sleep, exercise, meals,
  focus, stress). Pass their words.
- build_course: they want to learn a new topic. It takes a minute or two: say so first.
- open_node: they want to open or take on one of their nodes (titles below).
- open_map: they want to see their life tree.
- todays_plan: they ask what to study today.
- briefing: they ask how they are doing overall.
Everything else (small talk, questions, encouragement) you answer yourself. Never quiz or
grade them yourself: understanding is proven in an audit, which they start from a node.
When a tool returns, say what happened in one sentence.

The player:
{player}

Their nodes (newest course first):
{nodes}

The last messages between you (oldest first):
{recent}
"""

TOOLS = [
    {
        "type": "function",
        "name": "log_checkin",
        "description": "Record how the player's day went (sleep, exercise, meals, focus, stress).",
        "parameters": {
            "type": "object",
            "properties": {"said": {"type": "string", "description": "What the player said, in their words."}},
            "required": ["said"],
        },
    },
    {
        "type": "function",
        "name": "build_course",
        "description": "Build a new course (a tree of nodes to learn) on a topic. Takes a minute or two.",
        "parameters": {
            "type": "object",
            "properties": {"topic": {"type": "string", "description": "The topic, as the player put it."}},
            "required": ["topic"],
        },
    },
    {
        "type": "function",
        "name": "open_node",
        "description": "Open one of the player's nodes, to study it or start its audit.",
        "parameters": {
            "type": "object",
            "properties": {"node": {"type": "string", "description": "The node's title from the list."}},
            "required": ["node"],
        },
    },
    {"type": "function", "name": "open_map", "description": "Show the player's life tree.", "parameters": {"type": "object", "properties": {}}},
    {"type": "function", "name": "todays_plan", "description": "Plan what to study today.", "parameters": {"type": "object", "properties": {}}},
    {"type": "function", "name": "briefing", "description": "A short report on how the player is doing.", "parameters": {"type": "object", "properties": {}}},
]


def _player(session: Session) -> str:
    profile = game_profile.get_profile(session)
    lines = [
        f"- Identity: {profile.identity or '(not set)'}",
        f"- Winning looks like: {profile.vision or '(not set)'}",
        f"- If nothing changes: {profile.anti_vision or '(not set)'}",
    ]
    if profile.rules:
        lines.append("- Their rules: " + "; ".join(profile.rules))
    today = checkin_service.todays_checkin(session)
    lines.append(f"- Today's check-in: {today.transcript if today else 'none yet'}")
    return "\n".join(lines)


def _nodes(session: Session) -> str:
    nodes = session.exec(
        live_nodes().order_by(col(Course.created_at).desc(), col(Course.id).desc(), SkillNode.id).limit(MAX_NODES)
    ).all()
    if not nodes:
        return "(none yet: offer to build a course)"
    return "\n".join(f"- {n.title} ({n.status.value})" for n in nodes)


def _recent(session: Session) -> str:
    rows = session.exec(select(ChatMessage).order_by(col(ChatMessage.id).desc()).limit(RECENT_MESSAGES)).all()
    if not rows:
        return "(none)"
    return "\n".join(f"{'Player' if m.role == 'user' else 'You'}: {m.content[:300]}" for m in reversed(rows))


def guide_instructions(session: Session) -> str:
    text = GUIDE_INSTRUCTIONS.format(player=_player(session), nodes=_nodes(session), recent=_recent(session))
    instruction = language_instruction()
    if instruction:
        text += "\n" + instruction + " Speak in that language too."
    return text


def _languages() -> list[str]:
    lang = current_language()
    return [lang] if lang == "en" else [lang, "en"]


def guide_session(session: Session) -> dict:
    return {
        "type": "realtime",
        "model": settings.realtime_model,
        "instructions": guide_instructions(session),
        "audio": {
            "input": {
                "transcription": {"model": settings.live_transcribe_model, "languages": _languages()},
                "turn_detection": {"type": "semantic_vad"},
            },
            "output": {"voice": settings.speech_voice},
        },
        "tools": TOOLS,
        "tool_choice": "auto",
    }


def transcription_session() -> dict:
    return {
        "type": "transcription",
        "audio": {
            "input": {
                "transcription": {"model": settings.live_transcribe_model, "languages": _languages(), "delay": "low"},
                "turn_detection": None,
            }
        },
    }


def safety_identifier(user_id: str) -> str:
    return hashlib.sha256(f"self-infinity:{user_id}".encode()).hexdigest()


def connect(offer: str, config: dict, user_id: str) -> str:
    """Hands the browser's SDP offer and our session to OpenAI; returns the SDP answer."""
    key = _require_key()
    if not offer.strip():
        raise VoiceRejected("an SDP offer is required")
    if len(offer.encode()) > MAX_SDP_BYTES:
        raise VoiceRejected("SDP offer too large")
    start = time.perf_counter()
    try:
        response = _client.post(
            CALLS_URL,
            headers={"Authorization": f"Bearer {key}", "OpenAI-Safety-Identifier": safety_identifier(user_id)},
            files={"sdp": (None, offer), "session": (None, json.dumps(config, ensure_ascii=False))},
            timeout=settings.llm_timeout_seconds,
        )
    except httpx.HTTPError as e:
        raise VoiceFailed(f"could not reach OpenAI: {e}") from e
    elapsed_ms = (time.perf_counter() - start) * 1000
    if not 200 <= response.status_code < 300:
        logger.warning("realtime connect got status=%d after %.0fms: %s", response.status_code, elapsed_ms, response.text[:300])
        raise VoiceFailed(f"realtime session failed status={response.status_code} body={response.text[:300]}")
    logger.info("realtime connect type=%s elapsed_ms=%.0f", config.get("type"), elapsed_ms)
    return response.text
