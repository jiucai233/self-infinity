"""Profile Builder (plan 7.4, no LLM): ProfileFacts of contract section 2. UT-44, UT-45."""

from datetime import date, timedelta

import pytest
from sqlmodel import Session, SQLModel, create_engine
from sqlmodel.pool import StaticPool

from app.models import AuditStatus, DailyCheckIn, SkillStatus, utcnow
from app.services.profile import build_profile
from tests.helpers import make_audit, make_course, make_principle, make_skill

A = "No real roots means no solutions"
B = "Thought no real roots meant no solutions at all"
C = "Cramming equals learning"


@pytest.fixture(name="session")
def session_fixture():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


def test_ut44_two_similar_misconceptions_on_different_nodes_make_one_cross_skill_cluster(session):
    course = make_course(session)
    s1 = make_skill(session, course, "eq", "Quadratic Equations")
    s2 = make_skill(session, course, "fn", "Quadratic Functions")
    p1 = make_principle(session, s1, misconception=A)
    p2 = make_principle(session, s2, misconception=B)

    clusters = build_profile(session).misconception_clusters

    assert len(clusters) == 1
    cluster = clusters[0]
    assert cluster.label == A  # the earliest record names the cluster
    assert cluster.occurrences == 2
    assert cluster.skills == ["Quadratic Equations", "Quadratic Functions"]
    assert cluster.cross_skill is True
    assert cluster.principle_ids == [p1.id, p2.id]


def test_two_similar_misconceptions_on_one_node_are_not_cross_skill(session):
    skill = make_skill(session, make_course(session), "eq", "Quadratic Equations")
    make_principle(session, skill, misconception=A)
    make_principle(session, skill, misconception=B)

    (cluster,) = build_profile(session).misconception_clusters

    assert (cluster.occurrences, cluster.skills, cluster.cross_skill) == (2, ["Quadratic Equations"], False)


def test_unrelated_misconceptions_stay_apart_and_cross_skill_clusters_come_first(session):
    course = make_course(session)
    s1 = make_skill(session, course, "eq", "Quadratic Equations")
    s2 = make_skill(session, course, "fn", "Quadratic Functions")
    make_principle(session, s1, misconception=C)
    make_principle(session, s1, misconception=A)
    make_principle(session, s2, misconception=B)

    clusters = build_profile(session).misconception_clusters

    assert [c.label for c in clusters] == [A, C]


def test_a_principle_without_a_misconception_is_not_clustered(session):
    make_principle(session, make_skill(session, make_course(session), "eq"), misconception=None)

    assert build_profile(session).misconception_clusters == []


def test_node_and_audit_counts(session):
    course = make_course(session)
    make_skill(session, course, "a", status=SkillStatus.mastered)
    make_skill(session, course, "b", status=SkillStatus.available)
    skill = make_skill(session, course, "c", status=SkillStatus.locked)
    make_skill(session, course, "d", status=SkillStatus.locked)
    make_audit(session, skill, AuditStatus.passed)
    make_audit(session, skill, AuditStatus.failed)
    make_audit(session, skill, AuditStatus.active)

    facts = build_profile(session)

    assert facts.nodes.model_dump() == {"total": 4, "mastered": 1, "available": 1, "locked": 2}
    assert facts.audits.model_dump() == {"total": 3, "passed": 1, "failed": 1}


def _check_in(session: Session, day: int, sleep=None, stress=None):
    session.add(DailyCheckIn(date=date(2026, 10, 1) + timedelta(days=day), sleep_hours=sleep, stress=stress))
    session.commit()


def test_ut45_average_sleep_five_hours_over_three_check_ins_is_low(session):
    for day in range(3):
        _check_in(session, day, sleep=5)

    condition = build_profile(session).condition

    assert (condition.days, condition.avg_sleep_hours, condition.avg_stress, condition.flag) == (3, 5.0, None, "low")


def test_condition_averages_are_rounded_to_one_decimal(session):
    for day, sleep in enumerate((5, 5, 6)):
        _check_in(session, day, sleep=sleep, stress=3 if day else 2)

    condition = build_profile(session).condition

    assert condition.avg_sleep_hours == 5.3
    assert condition.avg_stress == 2.7


def test_no_check_ins_is_unknown(session):
    condition = build_profile(session).condition

    assert condition.model_dump() == {"days": 0, "avg_sleep_hours": None, "avg_stress": None, "flag": "unknown"}


def test_the_facts_serialize_to_the_contract_shape(session):
    assert set(build_profile(session).model_dump()) == {"nodes", "audits", "misconception_clusters", "condition", "xp"}
