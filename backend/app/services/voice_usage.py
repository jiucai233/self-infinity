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

An audit's voice is one of two as well: GPT-Live (`audit`, every second the session is open, plus
its other call, the Auditor: the text calls logged while the session was open, see
audit_backend_cost) or live transcription (`transcribe`, by the minute, its replies read aloud
by text to speech, which is not counted here).
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


def audit_backend_cost(s: VoiceSession, calls: list[LLMCall]) -> float | None:
    """A Live audit's other call: the account's text calls (the Auditor, the Challenger) logged
    from the session's start to its last report. None when none of them has a price.
    `started_at` is the browser's clock, the rest the server's."""
    return llm_usage.calls_cost(c for c in calls if s.started_at <= c.created_at <= s.updated_at)


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


def other_cost(s: VoiceSession, realtime_rate: float) -> float | None:
    """What a Guide session would have cost on the other voice; None for audits."""
    if s.kind != "guide":
        return None
    minutes = s.seconds / 60
    return minutes * realtime_rate if is_live(s) else minutes * GPT_LIVE_PER_MINUTE


def cost(s: VoiceSession, audit_backend: float | None = None) -> float:
    """[audit_backend]: a Live audit's audit_backend_cost."""
    if s.kind == "guide":
        return guide_cost(s)
    if s.kind == "audit":
        return live_voice_cost(s) + (audit_backend or 0)
    # Live transcription is billed by audio duration. The browser keeps the session open (muted)
    # between turns; whether that counts is not documented, so this is the upper bound.
    return s.seconds / 60 * LIVE_TRANSCRIBE_PER_MINUTE


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
    s: VoiceSession, realtime_rate: float = DEFAULT_REALTIME_PER_MINUTE, audit_backend: float | None = None
) -> dict:
    if s.kind == "guide":
        backend = backend_cost(s) if is_live(s) else None
    else:
        backend = audit_backend if s.kind == "audit" else None
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
        "cost": _round(cost(s, audit_backend)),
        "backend_cost": _round(backend, 6),
        "other_cost": _round(other_cost(s, realtime_rate)),
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
    calls = _calls_since(session, min((r.started_at for r in live_audits), default=None))
    audit_backend = {r.id: audit_backend_cost(r, calls) for r in live_audits}
    audit_live_voice = sum(live_voice_cost(r) for r in live_audits)
    audit_live_backend = sum(c for c in audit_backend.values() if c is not None)
    audit_cost_total = sum(cost(r, audit_backend.get(r.id)) for r in audits)
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
        "audit_turns_cost_per_session": _round(sum(cost(r) for r in turns) / len(turns)) if turns else None,
    }
    sessions = [session_out(r, rate, audit_backend.get(r.id)) for r in rows[:limit]]
    return {"totals": totals, "sessions": sessions}


def _calls_since(session: Session, start) -> list[LLMCall]:
    """The account's logged text calls from [start] on; none without a start."""
    if start is None:
        return []
    return list(session.exec(select(LLMCall).where(col(LLMCall.created_at) >= start)).all())
