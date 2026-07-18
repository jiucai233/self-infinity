from sqlmodel import Session, SQLModel, create_engine
from sqlmodel.pool import StaticPool

from app.services.vitality import apply_audit_result, get_or_create_vitality_state


def test_get_vitality_before_any_checkin_returns_default(client):
    resp = client.get("/api/vitality")
    assert resp.status_code == 200
    body = resp.json()
    assert 0 <= body["health"] <= 100
    assert 0 <= body["sanity"] <= body["sanity_cap"]
    assert body["sanity_cap"] > 0


def test_checkin_creates_check_in_and_returns_vitality_state(client):
    resp = client.post(
        "/api/checkins",
        json={"spending_rating": 3, "activity_rating": 3, "eating_rating": 3},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert 0 <= body["health"] <= 100
    assert body["health"] > 50  # all top ratings should push health up
    assert 0 <= body["sanity"] <= body["sanity_cap"]


def test_duplicate_same_day_checkin_rejected(client):
    payload = {"spending_rating": 2, "activity_rating": 2, "eating_rating": 2}
    first = client.post("/api/checkins", json=payload)
    assert first.status_code == 200

    second = client.post("/api/checkins", json=payload)
    assert second.status_code == 400
    assert "已签到" in second.json()["detail"]


def test_checkin_rating_out_of_range_rejected(client):
    resp = client.post(
        "/api/checkins",
        json={"spending_rating": 5, "activity_rating": 2, "eating_rating": 2},
    )
    assert resp.status_code == 422


def _engine():
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    SQLModel.metadata.create_all(engine)
    return engine


def test_apply_audit_result_pass_increases_sanity():
    engine = _engine()
    with Session(engine) as session:
        state = get_or_create_vitality_state(session)
        start_sanity = state.sanity

        updated = apply_audit_result(session, passed=True)
        assert updated.sanity > start_sanity
        assert updated.sanity <= updated.sanity_cap


def test_apply_audit_result_fail_decreases_sanity():
    engine = _engine()
    with Session(engine) as session:
        state = get_or_create_vitality_state(session)
        start_sanity = state.sanity

        updated = apply_audit_result(session, passed=False)
        assert updated.sanity < start_sanity
        assert updated.sanity >= 0

