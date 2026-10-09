"""What live voice costs (contract #37): the browser's reports and the developer panel's prices."""

import pytest

from app.models import VoiceSession
from app.services import voice_usage

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
