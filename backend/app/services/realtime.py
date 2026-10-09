"""Live voice over WebRTC (contract #35): the browser's SDP offer goes through here to OpenAI's
Realtime API with a session we configure, and the SDP answer goes back. Audio then flows
browser ↔ OpenAI directly; JSON events travel on the connection's data channel. The key and
the session (instructions, tools) never reach the browser.

Three sessions:
- live guide (the default, settings.guide_voice): the home page's Guide on GPT-Live, a
  full-duplex voice that listens while it speaks. It hands tool use to a text backend
  (settings.live_backend_model) through Responses delegation; the backend's function calls
  arrive on the data channel and the browser runs them on /api/chat/act, as below.
- realtime guide: the Guide as one speech-to-speech model (gpt-realtime). It talks itself and
  acts through tools the browser runs on /api/chat/act (the front desk's intents).
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
LIVE_URL = "https://api.openai.com/v1/live/sessions"
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
- log_checkin: whenever the player mentions how their day or night went (sleep or the times
  they slept, exercise, meals, focus, stress, weight), even in passing, call it before you
  answer. Pass everything they have said about today in this talk, in their words. Never ask
  them to repeat or confirm it first: log what you heard, then say it back in one sentence so
  they can correct you (a correction is logged again and replaces the number).
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
        "description": "Record how the player's day went (sleep, exercise, meals, focus, stress, weight). Call it whenever they mention any of these.",
        "parameters": {
            "type": "object",
            "properties": {"said": {"type": "string", "description": "Everything the player said about today in this talk, in their words."}},
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
    return _with_language(GUIDE_INSTRUCTIONS.format(player=_player(session), nodes=_nodes(session), recent=_recent(session)))


# ---------------------------------------------------------------- GPT-Live

# The voice's prompt follows OpenAI's GPT-Live template (policies for backchannels, interruptions
# and delegation); the backend gets the tools, the rules for using them and the player's nodes.
LIVE_VOICE_INSTRUCTIONS = """\
You are the Guide in Self-Infinity, a learning game where the player levels up by proving they
understand things: they explain them in their own words and an Auditor judges.
Speak like a calm, warm mentor at an unhurried pace: one or two short sentences, plain words.
Ask one question at a time. Never quiz or grade them yourself: understanding is proven in an
audit, which they start from a node.

Backchannel policy: Use few backchannels. Acknowledge briefly without competing with the main
response.

Interruption policy: Stop speaking when the player interrupts. Listen to what they say.

Delegation policy:
Backend tools:
- Check-in: record how their day or night went (sleep or the times they slept, exercise,
  meals, focus, stress, weight).
- Courses: build a new course on a topic; it takes a minute or two.
- Nodes: open one of their nodes to study it or start its audit, or show their life tree.
- Plans and reports: plan what to study today; report how they are doing overall.

Delegate to the backend when:
- They mention how their day or night went, even in passing. Do not ask them to repeat it
  first.
- They want to learn a new topic, open a node or their life tree, or ask for today's plan or
  how they are doing.
- A correction changes something already logged or requested.

Do not delegate to the backend when:
- It is small talk, a question you can answer yourself, or encouragement.
- You cannot tell what they want without a brief clarification.

Delegate before giving an answer that depends on backend work.
Do not guess the result while waiting; once it is done, say what happened in one sentence.

The player:
{player}
"""

LIVE_BACKEND_INSTRUCTIONS = """\
You run the tools for the Guide of Self-Infinity, a learning game, during a live voice
conversation. Transcripts can contain mistakes, unfinished phrases and later corrections: use
the latest context. If a detail you need is still unclear, ask for it instead of guessing.

Tools:
- log_checkin: the player said how their day or night went (sleep or the times they slept,
  exercise, meals, focus, stress, weight). Pass everything they said about today in this
  conversation, in their words. A correction is logged again; the new number replaces the old.
- build_course: they want to learn a new topic.
- open_node: they want to open or take on one of their nodes (titles below).
- open_map: they want to see their life tree.
- todays_plan: they ask what to study today.
- briefing: they ask how they are doing overall.
Call a tool only for what they said or asked. Report an action as done only after the tool
confirms it. Return one short sentence for the Guide to say: what happened, and the next step
if there is one.

The player:
{player}

Their nodes (newest course first):
{nodes}

The last messages between the Guide and the player (oldest first):
{recent}
"""


def _with_language(text: str) -> str:
    instruction = language_instruction()
    return text + ("\n" + instruction + " Speak in that language too." if instruction else "")


def live_guide_session(session: Session) -> dict:
    """The Guide on GPT-Live: the voice's prompt, and Responses delegation with our tools."""
    player = _player(session)
    return {
        "model": settings.live_model,
        "instructions": _with_language(LIVE_VOICE_INSTRUCTIONS.format(player=player)),
        "audio": {"output": {"voice": settings.speech_voice}},
        "delegation": {
            "type": "responses",
            "responses": {
                "model": settings.live_backend_model,
                "instructions": _with_language(
                    LIVE_BACKEND_INSTRUCTIONS.format(player=player, nodes=_nodes(session), recent=_recent(session))
                ),
                "tools": TOOLS,
                "tool_choice": "auto",
            },
        },
    }


def connect_live(offer: str, config: dict, user_id: str) -> str:
    """Creates a GPT-Live session for the browser's SDP offer; returns the SDP answer."""
    key = _require_key()
    if not offer.strip():
        raise VoiceRejected("an SDP offer is required")
    if len(offer.encode()) > MAX_SDP_BYTES:
        raise VoiceRejected("SDP offer too large")
    start = time.perf_counter()
    try:
        response = _client.post(
            LIVE_URL,
            headers={"Authorization": f"Bearer {key}", "OpenAI-Safety-Identifier": safety_identifier(user_id)},
            json={"session": config, "transport": {"type": "webrtc", "sdp": offer}},
            timeout=settings.llm_timeout_seconds,
        )
    except httpx.HTTPError as e:
        raise VoiceFailed(f"could not reach OpenAI: {e}") from e
    elapsed_ms = (time.perf_counter() - start) * 1000
    if not 200 <= response.status_code < 300:
        logger.warning("live connect got status=%d after %.0fms: %s", response.status_code, elapsed_ms, response.text[:300])
        raise VoiceFailed(f"live session failed status={response.status_code} body={response.text[:300]}")
    try:
        data = response.json()
        answer = data["transport"]["sdp"]
    except (ValueError, KeyError, TypeError) as e:
        raise VoiceFailed("live session answered without an SDP answer") from e
    logger.info("live connect session=%s elapsed_ms=%.0f", (data.get("session") or {}).get("id"), elapsed_ms)
    return str(answer)


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
