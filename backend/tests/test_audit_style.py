"""Who the user explains to and how deep she asks, chosen by the style bandit
(app/services/audit_style.py), and what the style changes in the audit."""

import json
import random

import pytest
from sqlmodel import Session, SQLModel, create_engine, select
from sqlmodel.pool import StaticPool

from app.agents.auditor import Auditor
from app.config import settings
from app.models import AuditSession, DailyCheckIn, StyleArm
from app.services import audit_style, learner
from app.services.audit_style import Style
from tests.helpers import (
    FIRST,
    SHORT,
    ScriptedProvider,
    answer_turns,
    freeze_clock,
    generate,
    ids_by_slug,
    make_course,
    make_skill,
    probe_json,
    start,
)

NEUTRAL = [1.0, 0.0, 0.0, 0.0, 0.0, 0.0]
GOOD_SHAPE = [1.0, 0.5, 0.0, 1.0, -1.0, 0.6]
BAD_SHAPE = [1.0, -0.5, 0.0, -1.5, 1.5, -0.6]


@pytest.fixture(name="session")
def session_fixture():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


def mean_level(session, x, draws=300) -> float:
    rng = random.Random(7)
    return sum(audit_style.choose(session, x, rng).level for _ in range(draws)) / draws


# ---------------------------------------------------------------- the styles and the offset


def test_nine_styles_from_the_easiest_to_the_hardest():
    levels = {(s.audience, s.depth): s.level for s in audit_style.styles()}

    assert len(levels) == 9
    assert levels[("expert", 0)] == -1 and levels[("student", 1)] == 0 and levels[("child", 2)] == 1


@pytest.mark.parametrize(
    "audience, depth, offset",
    [("student", 1, 0.0), (None, None, 0.0), ("child", 2, 1.0), ("expert", 0, -1.0), ("child", 0, 0.0)],
)
def test_the_offset_is_half_a_step_per_level_on_each_axis(audience, depth, offset):
    assert audit_style.difficulty_offset(audience, depth) == pytest.approx(offset)


def test_a_harder_style_makes_the_same_pass_count_as_more_progress(session):
    easy_skill = make_skill(session, make_course(session), "easy")
    hard_skill = make_skill(session, make_course(session, "Other"), "hard")

    easy = learner.record(session, easy_skill, True, None, None, offset=-1.0)
    hard = learner.record(session, hard_skill, True, None, None, offset=1.0)

    assert hard > easy


# ---------------------------------------------------------------- the prior


def test_a_new_arm_starts_at_the_prior(session):
    for style in audit_style.styles():
        mean = audit_style.posterior_mean(audit_style.arm(session, style))
        assert mean == pytest.approx(audit_style.prior_mean(style))


def test_before_any_data_good_shape_leans_hard_and_bad_shape_leans_easy(session):
    assert mean_level(session, GOOD_SHAPE) > 0.2
    assert mean_level(session, BAD_SHAPE) < -0.2


def test_as_usual_no_style_is_preferred_before_data(session):
    assert abs(mean_level(session, NEUTRAL)) < 0.2


# ---------------------------------------------------------------- learning


def test_rewards_move_the_choice_to_the_style_that_earns_them(session):
    for _ in range(40):
        for style in audit_style.styles():
            reward = 0.9 if (style.audience, style.depth) == ("expert", 2) else 0.1
            audit_style.update(session, style.audience, style.depth, NEUTRAL, reward)
    rng = random.Random(3)

    picks = [audit_style.choose(session, NEUTRAL, rng) for _ in range(50)]

    assert sum(1 for p in picks if (p.audience, p.depth) == ("expert", 2)) >= 45


def test_an_update_counts_the_audit_and_its_reward(session):
    audit_style.update(session, "child", 1, NEUTRAL, 0.6)
    audit_style.update(session, "child", 1, NEUTRAL, 0.2, weight=0.5)

    row = audit_style.arm(session, Style("child", 1))
    summary = {(r["audience"], r["depth"]): r for r in audit_style.summary(session)}
    assert row.pulls == 2
    assert summary[("child", 1)]["mean_reward"] == pytest.approx(0.4)
    assert summary[("expert", 0)] == {"audience": "expert", "depth": 0, "audits": 0, "mean_reward": None}


def test_a_reward_outside_zero_to_one_is_clipped_and_an_unknown_style_is_ignored(session):
    audit_style.update(session, "child", 1, NEUTRAL, 5.0)
    audit_style.update(session, "wizard", 1, NEUTRAL, 1.0)
    audit_style.update(session, "child", 7, NEUTRAL, 1.0)

    assert [(r.audience, r.depth, r.reward_sum) for r in session.exec(select(StyleArm)).all()] == [("child", 1, 1.0)]


# ---------------------------------------------------------------- the context


def test_without_a_check_in_or_history_the_shape_is_as_usual(session):
    skill = make_skill(session, make_course(session), "node")

    assert audit_style.context(session, skill) == [1.0, 0.0, 0.0, 0.0, 0.0, 0.0]


def test_a_check_in_from_today_or_last_night_shapes_the_context(session, monkeypatch):
    freeze_clock(monkeypatch, "2026-10-05 09:00")
    skill = make_skill(session, make_course(session), "node")
    session.add(DailyCheckIn(date=__import__("datetime").date(2026, 10, 4), sleep_hours=9, stress=1))
    session.commit()

    x = audit_style.context(session, skill)

    assert x[3] == pytest.approx(1.0)  # two hours more than seven
    assert x[4] == pytest.approx(-1.0)  # stress 1 of 5


# ---------------------------------------------------------------- the Auditor's prompt


def system_prompt(**style) -> str:
    provider = ScriptedProvider(auditor=probe_json())
    Auditor(provider).next_turn(
        "Quadratic Equations",
        "Judge the roots",
        [{"role": "assistant", "content": "Teach me."}, {"role": "user", "content": "An answer"}],
        **style,
    )
    return provider.system_prompts("auditor")[-1]


def test_the_default_style_is_the_prompt_as_it_was():
    assert system_prompt() == system_prompt(audience="student", depth=1)
    assert "bright, keen and have\nnever learned it." in system_prompt()
    assert "Never go a level below that" in system_prompt()


def test_a_child_listener_wants_everyday_words_and_holds_unexplained_terms_against_them():
    prompt = system_prompt(audience="child")

    assert "ten-year-old" in prompt and "bright, keen and have" not in prompt
    assert "short sentences, simple words" in prompt
    assert "Your listener is ten" in prompt


def test_a_colleague_needs_no_vocabulary_explained():
    prompt = system_prompt(audience="expert")

    assert "colleague from a neighbouring area" in prompt
    assert "Your listener is ten" not in prompt


def test_depth_zero_stops_at_what_and_what_for_and_depth_two_goes_one_level_down():
    shallow = system_prompt(depth=0)
    deep = system_prompt(depth=2)

    assert "how a part works inside is not asked this time" in shallow
    assert "Never go a level below that" not in shallow
    assert "Go one level below the idea of each part" in deep
    assert "One level only" in deep


# ---------------------------------------------------------------- in an audit


@pytest.fixture(name="math")
def math_fixture(client):
    return ids_by_slug(generate(client, "Math"))


@pytest.fixture(name="styles_on")
def styles_on_fixture(monkeypatch):
    monkeypatch.setattr(settings, "audit_styles", True)


def stored(client_engine, audit_id) -> AuditSession:
    with Session(client_engine) as session:
        return session.get(AuditSession, audit_id)


def test_an_audit_is_held_in_the_chosen_style_and_says_so(client, client_engine, monkeypatch, math, styles_on):
    monkeypatch.setattr(audit_style, "choose", lambda session, x, rng=None: Style("child", 2))
    spy = ScriptedProvider(auditor=probe_json())
    monkeypatch.setattr("app.routers.audits.get_provider", lambda agent=None: spy)

    body = client.post(f"/api/skills/{math['discriminant']}/audits", json={}).json()
    answer_turns(client, body["session"]["id"], FIRST)

    assert (body["session"]["audience"], body["session"]["depth"]) == ("child", 2)
    assert body["opening_question"].startswith("I'm ten,")
    prompt = spy.system_prompts("auditor")[-1]
    assert "ten-year-old" in prompt and "Go one level below the idea of each part" in prompt
    assert len(json.loads(stored(client_engine, body["session"]["id"]).style_context_json)) == 6


def test_the_verdict_rewards_the_style_it_was_held_in(client, client_engine, monkeypatch, math, styles_on):
    monkeypatch.setattr(audit_style, "choose", lambda session, x, rng=None: Style("expert", 0))
    audit_id = start(client, math["discriminant"])

    answer_turns(client, audit_id, FIRST, SHORT)

    with Session(client_engine) as session:
        arms = session.exec(select(StyleArm).where(StyleArm.pulls > 0)).all()
    assert [(a.audience, a.depth, a.pulls) for a in arms] == [("expert", 0, 1)]
    styles = {(s["audience"], s["depth"]): s for s in client.get("/api/learner").json()["styles"]}
    assert styles[("expert", 0)]["audits"] == 1 and len(styles) == 9


def test_a_challenge_and_an_audit_with_styles_off_keep_the_default(client, client_engine, monkeypatch, math):
    off = start(client, math["discriminant"])
    monkeypatch.setattr(settings, "audit_styles", True)
    challenge = client.post(f"/api/skills/{math['algebra']}/audits", json={"test_out": True})

    assert (stored(client_engine, off).audience, stored(client_engine, off).depth) == (None, None)
    assert challenge.status_code == 200, challenge.text
    assert challenge.json()["session"]["audience"] is None
