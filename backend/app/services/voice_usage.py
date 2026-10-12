"""What live voice costs (contract #37): the browser reports each session's usage, this prices it.

Prices are OpenAI's list prices of 2026-10-08, in dollars per million tokens or per minute
(developers.openai.com/api/docs/models).

The home Guide runs on one of two voices, and each session also shows what it would have cost
on the other, the comparison the panel is for:
- GPT-Live (gpt-live-1): every second the session is open, plus its text backend's tokens.
  On Realtime it would have cost its minutes at this account's own Realtime rate per minute,
  measured over its Realtime sessions (DEFAULT_REALTIME_PER_MINUTE until there is a minute).
- Realtime (gpt-realtime-*): by tokens (silence is free) plus the input transcription. On
  GPT-Live it would have cost its minutes at the voice rate; the backend is left out (a few
  hundredths of a cent per tool call).

An audit's voice is one of two as well, and each session shows the other one too:
- GPT-Live (`audit`): every second the session is open.
- Taking turns (`transcribe`): live transcription by the seconds its transcriptions report
  (the open time of a session that reported none: an upper bound), plus the speech that
  reads the replies aloud (logged as calls of the agent "speech", app/services/voice.py).
Both also count their other calls, the same on either voice: the text calls logged while the
session was open (the Auditor, the Challenger). On the other voice a session would have cost
its minutes at that voice's rate plus those same calls; the turn-taking rate is this account's
own (transcription and speech a minute of open session, DEFAULT_TURNS_PER_MINUTE until it has
a minute with speech logged).
"""

from sqlmodel import Session, col, select

from app.config import settings
from app.models import LLMCall, VoiceSession, utcnow
from app.services import llm_usage

# Per million tokens: text in, cached text in, audio in, cached audio in, text out, audio out.
REALTIME_PRICES = {
    "gpt-realtime-2.1": (4.0, 0.4, 32.0, 0.4, 24.0, 64.0),
    "gpt-realtime-2": (4.0, 0.4, 32.0, 0.4, 24.0, 64.0),
}
DEFAULT_REALTIME = "gpt-realtime-2.1"
# Per million tokens: input, cached input, output. The text models' one price table.
BACKEND_PRICES = llm_usage.PRICES
DEFAULT_BACKEND = "gpt-6-luna"
# Per minute.
LIVE_TRANSCRIBE_PER_MINUTE = 0.017
GPT_LIVE_PER_MINUTE = 0.05
# Until an account has a minute on Realtime: one 117.7 s Guide session on gpt-realtime-2.1
# (2026-10-08) cost $0.1415 with its transcription, $0.072 a minute.
DEFAULT_REALTIME_PER_MINUTE = 0.072

# Until an account has a minute of turn-taking audits with their speech logged: production's
# 13 sessions of 2026-10 had 69% of their open time transcribed ($0.0117 a minute), and
# replies of about a fifth of it read aloud ($0.0029 at 20 audio tokens a second).
DEFAULT_TURNS_PER_MINUTE = 0.015

KINDS = ("guide", "transcribe", "audit")
AUDIT_KINDS = ("transcribe", "audit")


def is_live(s: VoiceSession) -> bool:
    return s.model.startswith("gpt-live")


def realtime_cost(s: VoiceSession) -> float:
    """Dollars: the Guide's tokens, plus the transcription of what the user said."""
    t_in, t_cached, a_in, a_cached, t_out, a_out = REALTIME_PRICES.get(s.model, REALTIME_PRICES[DEFAULT_REALTIME])
    tokens = (
        max(s.text_in - s.text_in_cached, 0) * t_in
        + s.text_in_cached * t_cached
        + max(s.audio_in - s.audio_in_cached, 0) * a_in
        + s.audio_in_cached * a_cached
        + s.text_out * t_out
        + s.audio_out * a_out
    ) / 1_000_000
    return tokens + s.transcribed_seconds / 60 * LIVE_TRANSCRIBE_PER_MINUTE


def backend_cost(s: VoiceSession) -> float:
    """A GPT-Live session's text backend: its tokens (text_in, text_in_cached, text_out)."""
    prices = BACKEND_PRICES.get(settings.live_backend_model, BACKEND_PRICES[DEFAULT_BACKEND])
    return llm_usage.tokens_cost(prices, s.text_in, s.text_in_cached, s.text_out)


def live_voice_cost(s: VoiceSession) -> float:
    """A GPT-Live session's voice alone: every billed second."""
    return s.seconds / 60 * GPT_LIVE_PER_MINUTE


def live_cost(s: VoiceSession) -> float:
    """Dollars: every billed second of the voice, plus the backend."""
    return live_voice_cost(s) + backend_cost(s)


def calls_in(s: VoiceSession, calls: list[LLMCall]) -> list[LLMCall]:
    """The account's logged calls from the session's start to its last report.
    `started_at` is the browser's clock, the rest the server's."""
    return [c for c in calls if s.started_at <= c.created_at <= s.updated_at]


def audit_backend_cost(s: VoiceSession, calls: list[LLMCall]) -> float | None:
    """An audit session's other call, the same on either voice: the text calls (the Auditor,
    the Challenger) logged while it was open. None when none of them has a price."""
    return llm_usage.calls_cost(c for c in calls_in(s, calls) if c.agent != llm_usage.SPEECH_AGENT)


def speech_cost(s: VoiceSession, calls: list[LLMCall]) -> float | None:
    """The replies read aloud while a turn-taking session was open; None when none was logged."""
    return llm_usage.calls_cost(c for c in calls_in(s, calls) if c.agent == llm_usage.SPEECH_AGENT)


def transcription_cost(s: VoiceSession) -> float:
    """Live transcription is billed by audio duration: the seconds its transcriptions report.
    A session that reported none is priced by its open time, the upper bound."""
    return (s.transcribed_seconds or s.seconds) / 60 * LIVE_TRANSCRIBE_PER_MINUTE


def audit_voice_cost(s: VoiceSession, calls: list[LLMCall]) -> float:
    """An audit session's voice alone: GPT-Live's seconds, or transcription and speech."""
    if s.kind == "audit":
        return live_voice_cost(s)
    return transcription_cost(s) + (speech_cost(s, calls) or 0)


def turns_per_minute(turns: list[VoiceSession], calls: list[LLMCall]) -> tuple[float, bool]:
    """This account's turn-taking voice a minute of open session, and whether it was measured
    (a minute or more of sessions with their speech logged) rather than
    DEFAULT_TURNS_PER_MINUTE."""
    logged = [r for r in turns if speech_cost(r, calls) is not None]
    minutes = sum(r.seconds for r in logged) / 60
    if minutes < 1:
        return DEFAULT_TURNS_PER_MINUTE, False
    return sum(audit_voice_cost(r, calls) for r in logged) / minutes, True


def guide_cost(s: VoiceSession) -> float:
    return live_cost(s) if is_live(s) else realtime_cost(s)


def realtime_per_minute(rows: list[VoiceSession]) -> tuple[float, bool]:
    """This account's Realtime Guide cost per minute, and whether it was measured (a minute or
    more of Realtime sessions) rather than DEFAULT_REALTIME_PER_MINUTE."""
    realtime = [r for r in rows if r.kind == "guide" and not is_live(r)]
    minutes = sum(r.seconds for r in realtime) / 60
    if minutes < 1:
        return DEFAULT_REALTIME_PER_MINUTE, False
    return sum(realtime_cost(r) for r in realtime) / minutes, True


def other_cost(
    s: VoiceSession, realtime_rate: float, turns_rate: float = DEFAULT_TURNS_PER_MINUTE, backend: float | None = None
) -> float:
    """What the session would have cost on the other voice. A Guide session: its minutes at the
    other voice's rate. An audit session: the same, plus [backend], its own text calls."""
    minutes = s.seconds / 60
    if s.kind == "guide":
        return minutes * realtime_rate if is_live(s) else minutes * GPT_LIVE_PER_MINUTE
    rate = turns_rate if s.kind == "audit" else GPT_LIVE_PER_MINUTE
    return minutes * rate + (backend or 0)


def cost(s: VoiceSession, calls: list[LLMCall] | None = None) -> float:
    """Dollars. An audit session: its voice plus its text calls among [calls]."""
    if s.kind == "guide":
        return guide_cost(s)
    return audit_voice_cost(s, calls or []) + (audit_backend_cost(s, calls or []) or 0)


def cached_share(s: VoiceSession) -> float | None:
    total = s.text_in + s.audio_in
    return (s.text_in_cached + s.audio_in_cached) / total if total else None


def report(session: Session, client_id: str, values: dict) -> VoiceSession:
    """Upserts one session's running totals (the browser sends the whole totals each time)."""
    row = session.exec(select(VoiceSession).where(VoiceSession.client_id == client_id)).first()
    if row is None:
        row = VoiceSession(client_id=client_id, kind=values["kind"])
    for name, value in values.items():
        setattr(row, name, value)
    row.updated_at = utcnow()
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


def _round(value: float | None, digits: int = 4) -> float | None:
    return None if value is None else round(value, digits)


def session_out(
    s: VoiceSession,
    realtime_rate: float = DEFAULT_REALTIME_PER_MINUTE,
    turns_rate: float = DEFAULT_TURNS_PER_MINUTE,
    calls: list[LLMCall] | None = None,
) -> dict:
    calls = calls or []
    if s.kind == "guide":
        backend = backend_cost(s) if is_live(s) else None
    else:
        backend = audit_backend_cost(s, calls)
    return {
        "id": s.id,
        "kind": s.kind,
        "model": s.model,
        "started_at": s.started_at,
        "minutes": round(s.seconds / 60, 2),
        "turns": s.turns,
        "audio_in": s.audio_in,
        "audio_out": s.audio_out,
        "cached_share": _round(cached_share(s), 3),
        "cost": _round(cost(s, calls)),
        "backend_cost": _round(backend, 6),
        "other_cost": _round(other_cost(s, realtime_rate, turns_rate, backend)),
    }


def overview(session: Session, limit: int) -> dict:
    rows = list(session.exec(select(VoiceSession).order_by(col(VoiceSession.started_at).desc())).all())
    guide = [r for r in rows if r.kind == "guide"]
    audits = [r for r in rows if r.kind in AUDIT_KINDS]
    rate, measured = realtime_per_minute(rows)
    live = [r for r in guide if is_live(r)]
    realtime = [r for r in guide if not is_live(r)]
    guide_minutes = sum(r.seconds for r in guide) / 60
    guide_cost_total = sum(guide_cost(r) for r in guide)
    live_minutes = sum(r.seconds for r in live) / 60
    realtime_minutes = sum(r.seconds for r in realtime) / 60
    cached = sum(r.text_in_cached + r.audio_in_cached for r in realtime)
    inputs = sum(r.text_in + r.audio_in for r in realtime)
    live_audits = [r for r in audits if r.kind == "audit"]
    turns = [r for r in audits if r.kind == "transcribe"]
    calls = _calls_since(session, min((r.started_at for r in audits), default=None))
    turns_rate, turns_measured = turns_per_minute(turns, calls)
    backend = {r.id: audit_backend_cost(r, calls) or 0 for r in audits}
    audit_live_voice = sum(live_voice_cost(r) for r in live_audits)
    audit_live_backend = sum(backend[r.id] for r in live_audits)
    audit_cost_total = sum(cost(r, calls) for r in audits)
    turns_cost = sum(cost(r, calls) for r in turns)
    totals = {
        "guide_sessions": len(guide),
        "guide_minutes": round(guide_minutes, 2),
        "guide_cost": round(guide_cost_total, 4),
        "guide_cost_per_minute": _round(guide_cost_total / guide_minutes) if guide_minutes else None,
        "guide_cost_per_session": _round(guide_cost_total / len(guide)) if guide else None,
        # The two parts of the GPT-Live Guide sessions' cost: the voice, and its text backend.
        "guide_live_voice_cost": round(sum(live_voice_cost(r) for r in live), 4),
        "guide_live_backend_cost": round(sum(backend_cost(r) for r in live), 6),
        # Every Guide minute on one voice: what ran there as billed, the rest estimated.
        "guide_all_live": round(sum(live_cost(r) for r in live) + realtime_minutes * GPT_LIVE_PER_MINUTE, 4),
        "guide_all_realtime": round(sum(realtime_cost(r) for r in realtime) + live_minutes * rate, 4),
        "realtime_per_minute": round(rate, 4),
        "realtime_rate_measured": measured,
        "guide_cached_share": _round(cached / inputs, 3) if inputs else None,
        "audit_sessions": len(audits),
        "audit_minutes": round(sum(r.seconds for r in audits) / 60, 2),
        "audit_cost": round(audit_cost_total, 4),
        # The GPT-Live audits: the voice, and the Auditor's calls made meanwhile.
        "audit_live_sessions": len(live_audits),
        "audit_live_minutes": round(sum(r.seconds for r in live_audits) / 60, 2),
        "audit_live_voice_cost": round(audit_live_voice, 4),
        "audit_live_backend_cost": round(audit_live_backend, 6),
        "audit_live_cost_per_session": (
            _round((audit_live_voice + audit_live_backend) / len(live_audits)) if live_audits else None
        ),
        "audit_turns_cost_per_session": _round(turns_cost / len(turns)) if turns else None,
        # Every audit minute on one voice: what ran there as billed, the rest at that voice's
        # rate with the session's own text calls.
        "audit_all_live": round(
            audit_live_voice + audit_live_backend
            + sum(other_cost(r, rate, turns_rate, backend[r.id]) for r in turns),
            4,
        ),
        "audit_all_turns": round(
            turns_cost + sum(other_cost(r, rate, turns_rate, backend[r.id]) for r in live_audits), 4
        ),
        "turns_per_minute": round(turns_rate, 4),
        "turns_rate_measured": turns_measured,
    }
    sessions = [session_out(r, rate, turns_rate, calls) for r in rows[:limit]]
    return {"totals": totals, "sessions": sessions}


def _calls_since(session: Session, start) -> list[LLMCall]:
    """The account's logged calls (text and speech) from [start] on; none without a start."""
    if start is None:
        return []
    return list(session.exec(select(LLMCall).where(col(LLMCall.created_at) >= start)).all())
