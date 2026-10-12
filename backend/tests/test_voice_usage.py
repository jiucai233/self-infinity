"""What live voice costs (contract #37): the browser's reports and the developer panel's prices."""

from datetime import timedelta

import pytest
from sqlmodel import Session

from app.models import LLMCall, VoiceSession, utcnow
from app.services import llm_usage, voice_usage

GUIDE = {
    "kind": "guide",
    "model": "gpt-realtime-2.1",
    "started_at": "2026-10-08T05:00:00Z",
    "seconds": 120,
    "turns": 6,
    "text_in": 20_000,
    "text_in_cached": 15_000,
    "audio_in": 3_000,
    "audio_in_cached": 1_000,
    "text_out": 500,
    "audio_out": 1_200,
    "transcribed_seconds": 30,
}


def test_a_realtime_guide_is_priced_by_tokens_next_to_gpt_live(client):
    assert client.put("/api/voice/sessions/abc", json=GUIDE).status_code == 204
    data = client.get("/api/dev/voice").json()
    session = data["sessions"][0]
    expected = (
        5_000 * 4 + 15_000 * 0.4 + 2_000 * 32 + 1_000 * 0.4 + 500 * 24 + 1_200 * 64
    ) / 1_000_000 + 0.5 * 0.017
    assert session["cost"] == pytest.approx(expected, abs=1e-4)
    assert session["other_cost"] == pytest.approx(0.1)  # 2 minutes x $0.05
    assert session["backend_cost"] is None
    assert session["minutes"] == 2
    assert session["cached_share"] == pytest.approx(16_000 / 23_000, abs=1e-3)
    totals = data["totals"]
    assert totals["guide_sessions"] == 1
    assert totals["guide_cost"] == pytest.approx(expected, abs=1e-4)
    assert totals["guide_all_live"] == pytest.approx(0.1)
    assert totals["guide_all_realtime"] == pytest.approx(expected, abs=1e-4)
    assert totals["guide_cost_per_minute"] == pytest.approx(expected / 2, abs=1e-4)
    # Two minutes of Realtime: this account's own rate.
    assert (totals["realtime_per_minute"], totals["realtime_rate_measured"]) == (pytest.approx(expected / 2, abs=1e-4), True)


def test_reports_upsert_the_running_totals(client):
    client.put("/api/voice/sessions/abc", json=GUIDE)
    client.put("/api/voice/sessions/abc", json={**GUIDE, "seconds": 300, "turns": 9})
    sessions = client.get("/api/dev/voice").json()["sessions"]
    assert len(sessions) == 1
    assert (sessions[0]["minutes"], sessions[0]["turns"]) == (5, 9)


def test_an_audit_transcription_is_priced_by_the_minute(client):
    client.put("/api/voice/sessions/t1", json={"kind": "transcribe", "seconds": 600, "turns": 4, "transcribed_seconds": 90})
    data = client.get("/api/dev/voice").json()
    assert data["sessions"][0]["cost"] == pytest.approx(10 * 0.017)
    assert data["sessions"][0]["other_cost"] is None
    assert data["totals"]["audit_sessions"] == 1
    assert data["totals"]["audit_minutes"] == 10


def test_an_audit_on_gpt_live_is_priced_by_its_open_seconds(client):
    client.put("/api/voice/sessions/a1", json={"kind": "audit", "model": "gpt-live-1", "seconds": 240, "turns": 5})
    client.put("/api/voice/sessions/t1", json={"kind": "transcribe", "seconds": 600, "turns": 4})
    data = client.get("/api/dev/voice").json()
    live = next(s for s in data["sessions"] if s["kind"] == "audit")
    assert live["cost"] == pytest.approx(4 * 0.05)
    assert live["other_cost"] is None and live["backend_cost"] is None
    # Both voices of the audit are in its totals.
    assert data["totals"]["audit_sessions"] == 2
    assert data["totals"]["audit_minutes"] == 14
    assert data["totals"]["audit_cost"] == pytest.approx(4 * 0.05 + 10 * 0.017)
    assert data["totals"]["guide_sessions"] == 0


def test_a_live_audits_other_call_is_the_auditor(client, client_engine):
    now = utcnow()
    luna = {"provider": "openai", "model": "gpt-6-luna"}
    with Session(client_engine) as session:
        # While the session was open: the Auditor twice (one call failed), the Challenger once,
        # and a call on a model without a price.
        session.add(LLMCall(agent="auditor", **luna, input_tokens=4_000, cached_tokens=3_000, output_tokens=200, audit_id=1, created_at=now - timedelta(minutes=3)))
        session.add(LLMCall(agent="auditor", **luna, ok=False, audit_id=1, created_at=now - timedelta(minutes=2)))
        session.add(LLMCall(agent="challenger", **luna, input_tokens=2_000, output_tokens=100, audit_id=1, created_at=now - timedelta(minutes=1)))
        session.add(LLMCall(agent="auditor", provider="openai", model="my-own-model", input_tokens=9_000, created_at=now - timedelta(minutes=1)))
        # Before it opened and after its last report: not its calls.
        session.add(LLMCall(agent="planner", **luna, input_tokens=50_000, output_tokens=5_000, created_at=now - timedelta(minutes=9)))
        session.add(LLMCall(agent="auditor", **luna, input_tokens=50_000, output_tokens=5_000, created_at=now + timedelta(minutes=5)))
        session.commit()
    started = (now - timedelta(minutes=4)).isoformat()
    client.put("/api/voice/sessions/a1", json={"kind": "audit", "model": "gpt-live-1", "started_at": started, "seconds": 240, "turns": 5})
    client.put("/api/voice/sessions/a2", json={"kind": "audit", "model": "gpt-live-1", "started_at": (now - timedelta(seconds=30)).isoformat(), "seconds": 60})
    client.put("/api/voice/sessions/t1", json={"kind": "transcribe", "seconds": 600, "turns": 4})
    client.put("/api/voice/sessions/t2", json={"kind": "transcribe", "seconds": 300, "turns": 2})

    data = client.get("/api/dev/voice").json()

    auditor = (1_000 * 0.10 + 3_000 * 0.01 + 200 * 0.50 + 2_000 * 0.10 + 100 * 0.50) / 1e6
    first = next(s for s in data["sessions"] if s["minutes"] == 4 and s["kind"] == "audit")
    assert first["backend_cost"] == pytest.approx(auditor, abs=1e-6)
    assert first["cost"] == pytest.approx(4 * 0.05 + auditor, abs=1e-4)
    assert first["other_cost"] is None
    # No call while the second one was open: its voice only.
    second = next(s for s in data["sessions"] if s["minutes"] == 1)
    assert (second["backend_cost"], second["cost"]) == (None, pytest.approx(0.05))

    totals = data["totals"]
    assert (totals["audit_live_sessions"], totals["audit_live_minutes"]) == (2, 5)
    assert totals["audit_live_voice_cost"] == pytest.approx(5 * 0.05)
    assert totals["audit_live_backend_cost"] == pytest.approx(auditor, abs=1e-6)
    assert totals["audit_live_cost_per_session"] == pytest.approx((5 * 0.05 + auditor) / 2, abs=1e-4)
    assert totals["audit_turns_cost_per_session"] == pytest.approx(15 * 0.017 / 2, abs=1e-4)
    # The totals of the audit cover both voices, the Auditor's calls included.
    assert (totals["audit_sessions"], totals["audit_minutes"]) == (4, 20)
    assert totals["audit_cost"] == pytest.approx(5 * 0.05 + auditor + 15 * 0.017, abs=1e-4)


def test_the_voice_and_the_text_models_share_one_price_table():
    assert voice_usage.BACKEND_PRICES is llm_usage.PRICES


def test_bad_reports_are_refused(client):
    assert client.put("/api/voice/sessions/x", json={"kind": "other"}).status_code == 422
    assert client.put("/api/voice/sessions/x", json={"kind": "guide", "turns": -1}).status_code == 422
    assert client.put("/api/voice/sessions/" + "x" * 65, json={"kind": "guide"}).status_code == 400


def test_nothing_reported_yet(client):
    data = client.get("/api/dev/voice").json()
    assert data["sessions"] == []
    assert data["totals"]["guide_cost_per_minute"] is None
    assert data["totals"]["guide_cached_share"] is None
    assert (data["totals"]["realtime_per_minute"], data["totals"]["realtime_rate_measured"]) == (0.072, False)
    # Nothing to divide by: no per-session figure.
    for name in ("guide_cost_per_session", "audit_live_cost_per_session", "audit_turns_cost_per_session"):
        assert data["totals"][name] is None
    for name in ("guide_live_voice_cost", "guide_live_backend_cost", "audit_live_voice_cost", "audit_live_backend_cost"):
        assert data["totals"][name] == 0
    assert (data["totals"]["audit_live_sessions"], data["totals"]["audit_live_minutes"]) == (0, 0)


LIVE = {
    "kind": "guide",
    "model": "gpt-live-1",
    "started_at": "2026-10-08T06:00:00Z",
    "seconds": 90,
    "turns": 3,
    "text_in": 9_000,
    "text_in_cached": 6_000,
    "text_out": 400,
}


def test_a_live_guide_is_its_seconds_plus_the_backend_next_to_realtime(client):
    client.put("/api/voice/sessions/live", json=LIVE)
    session = client.get("/api/dev/voice").json()["sessions"][0]

    backend = (3_000 * 0.10 + 6_000 * 0.01 + 400 * 0.50) / 1_000_000
    assert session["backend_cost"] == pytest.approx(backend, abs=1e-6)
    assert session["cost"] == pytest.approx(1.5 * 0.05 + backend, abs=1e-4)
    # No Realtime history: the default rate.
    assert session["other_cost"] == pytest.approx(1.5 * 0.072, abs=1e-4)



def test_the_live_guides_cost_is_shown_in_its_two_parts(client):
    client.put("/api/voice/sessions/live", json=LIVE)  # 1.5 minutes
    client.put("/api/voice/sessions/live2", json={**LIVE, "seconds": 30, "text_in": 0, "text_in_cached": 0, "text_out": 0})
    client.put("/api/voice/sessions/rt", json=GUIDE)  # Realtime: in neither part
    data = client.get("/api/dev/voice").json()
    totals = data["totals"]

    backend = (3_000 * 0.10 + 6_000 * 0.01 + 400 * 0.50) / 1_000_000
    assert totals["guide_live_voice_cost"] == pytest.approx(2 * 0.05)
    assert totals["guide_live_backend_cost"] == pytest.approx(backend, abs=1e-6)
    assert totals["guide_cost_per_session"] == pytest.approx(totals["guide_cost"] / 3, abs=1e-4)
    live_costs = sum(s["cost"] for s in data["sessions"] if s["model"] == "gpt-live-1")
    assert totals["guide_live_voice_cost"] + totals["guide_live_backend_cost"] == pytest.approx(live_costs, abs=1e-4)


def test_the_realtime_estimate_uses_this_accounts_own_rate(client):
    client.put("/api/voice/sessions/rt", json=GUIDE)  # 2 minutes on Realtime
    client.put("/api/voice/sessions/live", json=LIVE)
    data = client.get("/api/dev/voice").json()

    rate = data["totals"]["realtime_per_minute"]
    live = next(s for s in data["sessions"] if s["model"] == "gpt-live-1")
    assert live["other_cost"] == pytest.approx(1.5 * rate, abs=1e-4)
    realtime_cost = next(s for s in data["sessions"] if s["model"] != "gpt-live-1")["cost"]
    totals = data["totals"]
    assert totals["guide_all_realtime"] == pytest.approx(realtime_cost + 1.5 * rate, abs=1e-3)
    assert totals["guide_all_live"] == pytest.approx(live["cost"] + 2 * 0.05, abs=1e-3)


def test_an_unknown_model_is_priced_like_the_default():
    s = VoiceSession(client_id="a", kind="guide", model="gpt-realtime-9", audio_out=1_000_000)
    assert voice_usage.realtime_cost(s) == pytest.approx(64)
