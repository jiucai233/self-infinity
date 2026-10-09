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
"""

from sqlmodel import Session, col, select

from app.config import settings
from app.models import VoiceSession, utcnow

# Per million tokens: text in, cached text in, audio in, cached audio in, text out, audio out.
REALTIME_PRICES = {
    "gpt-realtime-2.1": (4.0, 0.4, 32.0, 0.4, 24.0, 64.0),
    "gpt-realtime-2": (4.0, 0.4, 32.0, 0.4, 24.0, 64.0),
}
DEFAULT_REALTIME = "gpt-realtime-2.1"
# Per million tokens: input, cached input, output.
BACKEND_PRICES = {"gpt-6-luna": (0.10, 0.01, 0.50), "gpt-6-sol": (1.25, 0.125, 10.0)}
DEFAULT_BACKEND = "gpt-6-luna"
# Per minute.
LIVE_TRANSCRIBE_PER_MINUTE = 0.017
GPT_LIVE_PER_MINUTE = 0.05
# Until an account has a minute on Realtime: one 117.7 s Guide session on gpt-realtime-2.1
# (2026-10-08) cost $0.1415 with its transcription, $0.072 a minute.
DEFAULT_REALTIME_PER_MINUTE = 0.072

KINDS = ("guide", "transcribe")


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
    t_in, t_cached, t_out = BACKEND_PRICES.get(settings.live_backend_model, BACKEND_PRICES[DEFAULT_BACKEND])
    return (max(s.text_in - s.text_in_cached, 0) * t_in + s.text_in_cached * t_cached + s.text_out * t_out) / 1_000_000


def live_cost(s: VoiceSession) -> float:
    """Dollars: every billed second of the voice, plus the backend."""
    return s.seconds / 60 * GPT_LIVE_PER_MINUTE + backend_cost(s)


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


def cost(s: VoiceSession) -> float:
    if s.kind == "guide":
        return guide_cost(s)
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


def session_out(s: VoiceSession, realtime_rate: float = DEFAULT_REALTIME_PER_MINUTE) -> dict:
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
        "cost": _round(cost(s)),
        "backend_cost": _round(backend_cost(s), 6) if s.kind == "guide" and is_live(s) else None,
        "other_cost": _round(other_cost(s, realtime_rate)),
    }


def overview(session: Session, limit: int) -> dict:
    rows = list(session.exec(select(VoiceSession).order_by(col(VoiceSession.started_at).desc())).all())
    guide = [r for r in rows if r.kind == "guide"]
    audits = [r for r in rows if r.kind == "transcribe"]
    rate, measured = realtime_per_minute(rows)
    live = [r for r in guide if is_live(r)]
    realtime = [r for r in guide if not is_live(r)]
    guide_minutes = sum(r.seconds for r in guide) / 60
    guide_cost_total = sum(guide_cost(r) for r in guide)
    live_minutes = sum(r.seconds for r in live) / 60
    realtime_minutes = sum(r.seconds for r in realtime) / 60
    cached = sum(r.text_in_cached + r.audio_in_cached for r in realtime)
    inputs = sum(r.text_in + r.audio_in for r in realtime)
    totals = {
        "guide_sessions": len(guide),
        "guide_minutes": round(guide_minutes, 2),
        "guide_cost": round(guide_cost_total, 4),
        "guide_cost_per_minute": _round(guide_cost_total / guide_minutes) if guide_minutes else None,
        # Every Guide minute on one voice: what ran there as billed, the rest estimated.
        "guide_all_live": round(sum(live_cost(r) for r in live) + realtime_minutes * GPT_LIVE_PER_MINUTE, 4),
        "guide_all_realtime": round(sum(realtime_cost(r) for r in realtime) + live_minutes * rate, 4),
        "realtime_per_minute": round(rate, 4),
        "realtime_rate_measured": measured,
        "guide_cached_share": _round(cached / inputs, 3) if inputs else None,
        "audit_sessions": len(audits),
        "audit_minutes": round(sum(r.seconds for r in audits) / 60, 2),
        "audit_cost": round(sum(cost(r) for r in audits), 4),
    }
    return {"totals": totals, "sessions": [session_out(r, rate) for r in rows[:limit]]}
