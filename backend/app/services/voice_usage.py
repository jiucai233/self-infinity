"""What live voice costs (contract #37): the browser reports each session's usage, this prices it.

Prices are OpenAI's list prices of 2026-10-08, in dollars per million tokens or per minute
(developers.openai.com/api/docs/models). Next to each Guide session is what the same minutes
would cost on GPT-Live (gpt-live-1, billed per second of an open session, its backend apart),
the comparison the panel is for.
"""

from sqlmodel import Session, col, select

from app.models import VoiceSession, utcnow

# Per million tokens: text in, cached text in, audio in, cached audio in, text out, audio out.
REALTIME_PRICES = {
    "gpt-realtime-2.1": (4.0, 0.4, 32.0, 0.4, 24.0, 64.0),
    "gpt-realtime-2": (4.0, 0.4, 32.0, 0.4, 24.0, 64.0),
}
DEFAULT_REALTIME = "gpt-realtime-2.1"
# Per minute.
LIVE_TRANSCRIBE_PER_MINUTE = 0.017
GPT_LIVE_PER_MINUTE = 0.05

KINDS = ("guide", "transcribe")


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


def cost(s: VoiceSession) -> float:
    if s.kind == "guide":
        return realtime_cost(s)
    # Live transcription is billed by audio duration. The browser keeps the session open (muted)
    # between turns; whether that counts is not documented, so this is the upper bound.
    return s.seconds / 60 * LIVE_TRANSCRIBE_PER_MINUTE


def live_equivalent(s: VoiceSession) -> float | None:
    """What the Guide session's minutes would cost on GPT-Live (voice only); None for audits."""
    return s.seconds / 60 * GPT_LIVE_PER_MINUTE if s.kind == "guide" else None


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


def session_out(s: VoiceSession) -> dict:
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
        "live_equivalent": _round(live_equivalent(s)),
    }


def overview(session: Session, limit: int) -> dict:
    rows = list(session.exec(select(VoiceSession).order_by(col(VoiceSession.started_at).desc())).all())
    guide = [r for r in rows if r.kind == "guide"]
    audits = [r for r in rows if r.kind == "transcribe"]
    guide_minutes = sum(r.seconds for r in guide) / 60
    guide_cost = sum(realtime_cost(r) for r in guide)
    cached = sum(r.text_in_cached + r.audio_in_cached for r in guide)
    inputs = sum(r.text_in + r.audio_in for r in guide)
    totals = {
        "guide_sessions": len(guide),
        "guide_minutes": round(guide_minutes, 2),
        "guide_cost": round(guide_cost, 4),
        "guide_live_equivalent": round(guide_minutes * GPT_LIVE_PER_MINUTE, 4),
        "guide_cost_per_minute": _round(guide_cost / guide_minutes) if guide_minutes else None,
        "guide_cached_share": _round(cached / inputs, 3) if inputs else None,
        "audit_sessions": len(audits),
        "audit_minutes": round(sum(r.seconds for r in audits) / 60, 2),
        "audit_cost": round(sum(cost(r) for r in audits), 4),
    }
    return {"totals": totals, "sessions": [session_out(r) for r in rows[:limit]]}
