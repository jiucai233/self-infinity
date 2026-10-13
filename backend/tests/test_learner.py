"""The learner model (app/services/learner.py): what a verdict is worth, the ability and the
difficulties, and the judge's error rates."""

import json

import pytest
from sqlmodel import Session, SQLModel, create_engine, select
from sqlmodel.pool import StaticPool

from app.models import AuditStatus, LearnerPoint
from app.services import learner
from tests.helpers import make_audit, make_course, make_skill


@pytest.fixture(name="session")
def session_fixture():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


@pytest.fixture(name="skill")
def skill_fixture(session):
    return make_skill(session, make_course(session), "node")


def with_points(session, skill, *oks):
    skill.points_json = json.dumps([{"title": f"P{i}", "ok": ok, "note": None} for i, ok in enumerate(oks)])
    session.add(skill)
    session.commit()
    session.refresh(skill)
    return skill


def points_of(*oks) -> list[dict]:
    return [{"title": f"P{i}", "ok": ok, "note": None} for i, ok in enumerate(oks)]


def difficulty(session, skill, title: str = "") -> float:
    return session.exec(
        select(LearnerPoint).where(LearnerPoint.skill_id == skill.id, LearnerPoint.title == title)
    ).one().difficulty


PRIOR_RATES = (
    learner.PRIOR_FALSE_PASS[0] / sum(learner.PRIOR_FALSE_PASS),
    learner.PRIOR_FALSE_FAIL[0] / sum(learner.PRIOR_FALSE_FAIL),
)


# ---------------------------------------------------------------- corrected


@pytest.mark.parametrize("expected", [0.01, 0.3, 0.5, 0.75, 0.99])
def test_a_judge_that_never_errs_gives_the_result_itself(expected):
    assert learner.corrected(True, expected, 0.0, 0.0) == pytest.approx(1.0)
    assert learner.corrected(False, expected, 0.0, 0.0) == pytest.approx(0.0)


@pytest.mark.parametrize("expected", [0.1, 0.5, 0.75, 0.9])
def test_a_fail_from_the_default_judge_is_worth_something_but_less_than_was_expected(expected):
    worth = learner.corrected(False, expected, *PRIOR_RATES)

    assert 0 < worth < expected


@pytest.mark.parametrize("expected", [0.1, 0.5, 0.75, 0.9])
def test_a_pass_from_the_default_judge_is_worth_at_least_what_was_expected(expected):
    assert learner.corrected(True, expected, *PRIOR_RATES) >= expected


def test_the_worth_of_a_fail_rises_with_what_was_expected():
    worths = [learner.corrected(False, e, *PRIOR_RATES) for e in (0.1, 0.3, 0.5, 0.7, 0.9)]

    assert worths == sorted(worths) and len(set(worths)) == 5


@pytest.mark.parametrize("result", [True, False])
@pytest.mark.parametrize("expected", [0.0, 0.5, 1.0])
@pytest.mark.parametrize("rates", [(0.0, 0.0), PRIOR_RATES, (0.3, 0.6)])
def test_the_worth_of_a_result_stays_within_zero_and_one(result, expected, rates):
    assert 0.0 <= learner.corrected(result, expected, *rates) <= 1.0


# ---------------------------------------------------------------- chance


def test_the_chance_is_a_half_at_equal_ability_and_difficulty():
    assert learner.chance(0.7, 0.7) == pytest.approx(0.5)


def test_the_chance_rises_with_ability_and_falls_with_difficulty():
    assert learner.chance(1.0, 0.0) > learner.chance(0.0, 0.0) > learner.chance(-1.0, 0.0)
    assert learner.chance(0.0, -1.0) > learner.chance(0.0, 0.0) > learner.chance(0.0, 1.0)


# ---------------------------------------------------------------- judge_rates


def test_with_no_reviewed_audit_the_rates_are_the_prior_ratios(session, skill):
    make_audit(session, skill, AuditStatus.failed)
    make_audit(session, skill, AuditStatus.active, review="too_strict")

    assert learner.judge_rates(session) == pytest.approx(PRIOR_RATES)


@pytest.mark.parametrize("kwargs", [{"review": "too_strict"}, {"disputed": True}])
def test_a_fail_called_too_strict_or_disputed_raises_the_false_fail_rate(session, skill, kwargs):
    before = learner.judge_rates(session)
    make_audit(session, skill, AuditStatus.failed, **kwargs)

    false_pass, false_fail = learner.judge_rates(session)

    assert false_fail > before[1]
    assert false_pass == pytest.approx(before[0])


def test_a_fail_called_right_lowers_the_false_pass_rate(session, skill):
    before = learner.judge_rates(session)
    make_audit(session, skill, AuditStatus.failed, review="right")

    false_pass, false_fail = learner.judge_rates(session)

    assert false_pass < before[0]
    assert false_fail == pytest.approx(before[1])


def test_a_pass_called_too_lenient_raises_the_false_pass_rate(session, skill):
    before = learner.judge_rates(session)
    make_audit(session, skill, AuditStatus.passed, review="too_lenient")

    assert learner.judge_rates(session)[0] > before[0]


def test_active_audits_do_not_move_the_rates(session, skill):
    make_audit(session, skill, AuditStatus.active, review="too_lenient", disputed=True)

    assert learner.judge_rates(session) == pytest.approx(PRIOR_RATES)


# ---------------------------------------------------------------- record


def test_a_result_better_than_expected_raises_the_ability_and_lowers_the_difficulty(session, skill):
    start = learner.TIER_DIFFICULTY["medium"]

    learner.record(session, skill, True, None, None)

    assert learner.learner(session).ability > 0
    assert difficulty(session, skill) < start


def test_a_result_worse_than_expected_does_the_opposite(session, skill):
    learner.record(session, skill, False, None, None)

    assert learner.learner(session).ability < 0
    assert difficulty(session, skill) > learner.TIER_DIFFICULTY["medium"]


def test_attempts_count_every_result_of_a_point(session, skill):
    for passed in (True, False, True):
        learner.record(session, skill, passed, None, None)

    assert session.exec(select(LearnerPoint)).one().attempts == 3


def test_an_audit_with_points_gives_one_result_for_each_settled_point(session, skill):
    progress = learner.record(session, skill, False, points_of(True, False, None), None)

    rows = {r.title: r for r in session.exec(select(LearnerPoint)).all()}
    assert set(rows) == {"P0", "P1"}  # the point not asked (ok None) is skipped
    assert all(r.attempts == 1 for r in rows.values())
    assert rows["P0"].difficulty < rows["P1"].difficulty
    assert progress is not None


def test_an_audit_that_settled_no_point_gives_nothing(session, skill):
    assert learner.record(session, skill, True, points_of(None, None), None) is None
    assert session.exec(select(LearnerPoint)).all() == []
    assert learner.learner(session).ability == 0


def test_a_node_without_points_gives_one_result_under_the_empty_title(session, skill):
    learner.record(session, skill, True, [], None)

    (row,) = session.exec(select(LearnerPoint)).all()
    assert row.title == ""


def test_a_split_vote_moves_the_ability_by_half_of_what_a_unanimous_one_does(session, skill):
    other = make_skill(session, make_course(session, "Other"), "other")

    learner.record(session, skill, True, None, 1.0)
    unanimous = learner.learner(session).ability
    learner.learner(session).ability = 0.0
    learner.record(session, other, True, None, 2 / 3)
    split = learner.learner(session).ability

    assert split == pytest.approx(unanimous * learner.SPLIT_WEIGHT)


def test_getting_a_hard_point_right_makes_more_progress_than_an_easy_one(session, skill):
    easy = make_skill(session, make_course(session, "Easy"), "easy")
    session.add(LearnerPoint(skill_id=easy.id, title="", difficulty=-1.0))
    session.add(LearnerPoint(skill_id=skill.id, title="", difficulty=1.0))
    session.commit()

    hard_progress = learner.record(session, skill, True, None, None)
    learner.learner(session).ability = 0.0
    easy_progress = learner.record(session, easy, True, None, None)

    assert hard_progress > easy_progress


def test_a_clean_fail_makes_no_progress_when_the_judge_never_errs(session, skill, monkeypatch):
    monkeypatch.setattr(learner, "judge_rates", lambda session: (0.0, 0.0))

    assert learner.record(session, skill, False, None, None) == pytest.approx(0.0)
    assert learner.record(session, skill, True, None, None) > 0


def test_a_fail_from_the_default_judge_still_makes_a_little_progress(session, skill):
    progress = learner.record(session, skill, False, None, None)

    assert 0 < progress < 0.5


# ---------------------------------------------------------------- node_chance


def test_the_chance_of_a_node_with_points_averages_over_the_points_not_yet_right(session, skill):
    with_points(session, skill, True, None, None)
    session.add(LearnerPoint(skill_id=skill.id, title="P1", difficulty=1.0))
    session.add(LearnerPoint(skill_id=skill.id, title="P0", difficulty=-5.0))  # right already: not counted
    session.commit()

    expected = (learner.chance(0.0, 1.0) + learner.chance(0.0, 0.0)) / 2  # P2 is new: the tier's difficulty

    assert learner.node_chance(session, skill) == pytest.approx(expected)


def test_a_new_node_starts_from_the_difficulty_of_its_tier(session, skill):
    easy, medium, hard = (learner.node_chance(session, skill, tier) for tier in ("easy", "medium", "hard"))

    assert easy > medium > hard
    assert medium == pytest.approx(0.5)


def test_the_chance_of_a_node_follows_the_ability(session, skill):
    before = learner.node_chance(session, skill)
    learner.learner(session).ability = 1.0

    assert learner.node_chance(session, skill) > before


# ---------------------------------------------------------------- too_hard


def test_too_hard_raises_the_difficulty_of_each_point_of_the_audit(session, skill):
    audit = make_audit(session, skill, AuditStatus.failed, points_json=json.dumps(points_of(False, None)))
    start = learner.TIER_DIFFICULTY["medium"]

    learner.too_hard(session, audit, skill)

    assert difficulty(session, skill, "P0") == pytest.approx(start + learner.TOO_HARD_STEP)
    assert difficulty(session, skill, "P1") == pytest.approx(start + learner.TOO_HARD_STEP)


def test_too_hard_on_an_audit_without_points_raises_the_nodes_own_difficulty(session, skill):
    audit = make_audit(session, skill, AuditStatus.failed)

    learner.too_hard(session, audit, skill)

    assert difficulty(session, skill) == pytest.approx(learner.TIER_DIFFICULTY["medium"] + learner.TOO_HARD_STEP)
