"""The learner model catches up with audits it never counted (app/services/learner.py
`catch_up`): the ones from before it existed are replayed, oldest first."""

from datetime import datetime, timezone

import pytest
from sqlmodel import Session, SQLModel, create_engine, select
from sqlmodel.pool import StaticPool

from app.models import AuditSession, AuditStatus, LearnerPoint, LearnerStep
from app.services import learner
from tests.helpers import make_course, make_skill


@pytest.fixture(name="session")
def session_fixture():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


def audit(session, skill, status, day, **fields) -> AuditSession:
    row = AuditSession(
        skill_id=skill.id, status=status, created_at=datetime(2026, 10, day, 9, tzinfo=timezone.utc), **fields
    )
    session.add(row)
    session.commit()
    return row


def test_old_audits_are_replayed_oldest_first_and_keep_their_dates(session):
    skill = make_skill(session, make_course(session), "node")
    first = audit(session, skill, AuditStatus.failed, 2)
    second = audit(session, skill, AuditStatus.passed, 5)
    audit(session, skill, AuditStatus.active, 6)

    assert learner.catch_up(session) is True

    steps = [(s.session_id, s.created_at.day) for _, s in sorted((s.id, s) for s in session.exec(select(LearnerStep)).all())]
    assert steps == [(first.id, 2), (second.id, 5)]
    assert learner.learner(session).ability != 0


def test_nothing_happens_when_every_audit_is_counted(session):
    skill = make_skill(session, make_course(session), "node")
    old = audit(session, skill, AuditStatus.passed, 2)
    learner.catch_up(session)
    ability = learner.learner(session).ability

    assert learner.catch_up(session) is False
    assert learner.learner(session).ability == ability
    assert [s.session_id for s in session.exec(select(LearnerStep)).all()] == [old.id]


def test_a_rebuild_matches_recording_the_audits_as_they_came(session):
    skill = make_skill(session, make_course(session), "node")
    other = make_skill(session, make_course(session, "Other"), "other")
    rows = [
        audit(session, skill, AuditStatus.failed, 1),
        audit(session, other, AuditStatus.passed, 2, agreement=2 / 3),
        audit(session, skill, AuditStatus.passed, 3),
    ]
    for row in rows:
        learner.record(session, session.get(type(skill), row.skill_id), row.status == AuditStatus.passed, None, row.agreement, "medium", row.id)
    live = learner.learner(session).ability
    # A new audit arrives that the model never saw: the whole history is replayed.
    late = audit(session, skill, AuditStatus.failed, 4)
    learner.record(session, skill, False, None, None, "medium", late.id)
    session.delete(session.exec(select(LearnerStep).where(LearnerStep.session_id == rows[0].id)).one())
    session.commit()

    assert learner.catch_up(session) is True
    assert len(session.exec(select(LearnerStep)).all()) == 4
    assert learner.learner(session).ability < live  # the late fail counts once, not twice


def test_too_hard_is_replayed_and_a_points_audit_counts_its_points(session):
    skill = make_skill(session, make_course(session), "node")
    points = '[{"title": "a", "ok": true, "note": null}, {"title": "b", "ok": false, "note": null}]'
    audit(session, skill, AuditStatus.failed, 2, points_json=points, too_hard=True)

    learner.catch_up(session)

    rows = {p.title: p for p in session.exec(select(LearnerPoint)).all()}
    assert set(rows) == {"a", "b"}
    assert rows["b"].difficulty > rows["a"].difficulty + learner.TOO_HARD_STEP / 2


def test_the_learner_endpoint_catches_up(client):
    # A fresh account has no audits: nothing to replay, and the endpoint still answers.
    body = client.get("/api/learner").json()
    assert body["history"] == []


def test_each_step_keeps_its_prediction_and_old_steps_without_one_are_replayed(session):
    skill = make_skill(session, make_course(session), "node")
    row = audit(session, skill, AuditStatus.passed, 2)
    learner.record(session, skill, True, None, None, "medium", row.id)
    step = session.exec(select(LearnerStep)).one()
    assert step.predicted == pytest.approx(0.5) and step.observed == 1.0
    step.predicted = None
    session.commit()

    assert learner.catch_up(session) is True
    assert session.exec(select(LearnerStep)).one().predicted == pytest.approx(0.5)


def test_the_evaluation_compares_the_model_with_the_running_pass_rate(session):
    assert learner.evaluation(session) == {"results": 0, "brier": None, "brier_baseline": None}
    skill = make_skill(session, make_course(session), "node")
    for day, status in enumerate([AuditStatus.passed, AuditStatus.passed, AuditStatus.failed], start=1):
        audit(session, skill, status, day)
    learner.catch_up(session)

    result = learner.evaluation(session)

    assert result["results"] == 3
    assert 0 <= result["brier"] <= 1 and 0 <= result["brier_baseline"] <= 1
    # The running rate guesses 0.5, then 0.75, then 0.83 for a fail.
    assert result["brier_baseline"] == pytest.approx(((0.5 - 1) ** 2 + (0.75 - 1) ** 2 + (2.5 / 3) ** 2) / 3, abs=1e-4)
