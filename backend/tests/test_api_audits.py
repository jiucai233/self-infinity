"""审计接口：开场问题、追问 / 裁决、解锁、复核、错误处理（IT-05 ~ IT-18）。

Mock 的审计脚本是确定的（契约 4.3），所以大多数测试只靠回答的长短来驱动：
第一个回答一律追问；之后按总字数裁决，< 80 不通过；Challenger 在 < 160 时推翻一次。
"""

import json

import pytest
from sqlmodel import Session, select

from app.config import settings
from app.models import (
    AuditSession,
    AuditStatus,
    AuditTurn,
    DailyCheckIn,
    NodePosition,
    RewardEvent,
    SkillNode,
    SkillStatus,
)
from tests.helpers import (
    FIRST,
    LONG,
    MEDIUM,
    SHORT,
    BrokenProvider,
    CountingProvider,
    ScriptedProvider,
    answer_turns,
    fail_node,
    generate,
    ids_by_slug,
    make_principle,
    pass_node,
    probe_json,
    set_status,
    verdict_json,
    start,
)

CHALLENGER_QUESTION = "Before I pass this: give one case where this idea does not hold, and explain why."


def use_provider(monkeypatch, provider):
    monkeypatch.setattr("app.routers.audits.get_provider", lambda agent=None: provider)


@pytest.fixture(name="math")
def math_fixture(client):
    return ids_by_slug(generate(client, "Math"))


def stored_turns(client_engine, audit_id: int) -> list[tuple[str, str]]:
    with Session(client_engine) as session:
        rows = session.exec(select(AuditTurn).where(AuditTurn.session_id == audit_id).order_by(AuditTurn.id)).all()
        return [(t.role.value, t.content) for t in rows]


def stored_audit(client_engine, audit_id: int) -> AuditSession:
    with Session(client_engine) as session:
        return session.get(AuditSession, audit_id)


def node_status(client, skill_id: int) -> str:
    return next(n["status"] for n in client.get("/api/skills").json() if n["id"] == skill_id)


# ---------------------------------------------------------------- 开始审计


def test_it05_a_locked_node_cannot_be_audited(client, math):
    response = client.post(f"/api/skills/{math['quadratic-equation']}/audits")

    assert response.status_code == 400
    assert response.json() == {"detail": "skill is locked"}


def test_it06_a_missing_node_is_a_404(client):
    response = client.post("/api/skills/999/audits")

    assert response.status_code == 404
    assert response.json() == {"detail": "skill not found"}


def test_it07_root_opening_question_and_position(client, client_engine, math):
    response = client.post(f"/api/skills/{math['high-school-math']}/audits")

    assert response.status_code == 200
    body = response.json()
    expected = "Which problems call for “High School Math”, and which don't? How do you decide?"
    assert body["opening_question"] == expected
    assert body["session"]["node_position"] == "root"
    assert body["session"]["turns"] == [{"role": "auditor", "content": expected}]
    assert stored_audit(client_engine, body["session"]["id"]).node_position == NodePosition.root


def test_it07_branch_opening_question_lists_the_children(client, client_engine, math):
    set_status_by_api(client_engine, math["algebra"])

    body = client.post(f"/api/skills/{math['algebra']}/audits").json()

    assert body["opening_question"] == (
        "“Algebra” covers Quadratic Equations, Sequences. Why do these belong together, and when do you use which?"
    )
    assert body["session"]["node_position"] == "branch"
    assert stored_audit(client_engine, body["session"]["id"]).node_position == NodePosition.branch


def test_it07_leaf_opening_question(client, client_engine, math):
    set_status_by_api(client_engine, math["discriminant"])

    body = client.post(f"/api/skills/{math['discriminant']}/audits").json()

    assert body["opening_question"] == "Explain “Discriminant” from scratch to someone who has never heard of it."
    assert body["session"]["node_position"] == "leaf"
    assert stored_audit(client_engine, body["session"]["id"]).node_position == NodePosition.leaf


def test_it07_a_node_with_two_parents_is_a_leaf_when_it_has_no_children(client, client_engine, math):
    set_status_by_api(client_engine, math["sequence-limit"])

    body = client.post(f"/api/skills/{math['sequence-limit']}/audits").json()

    assert body["session"]["node_position"] == "leaf"


def set_status_by_api(client_engine, skill_id: int) -> None:
    with Session(client_engine) as session:
        set_status(session, skill_id, SkillStatus.available)


TASK_COURSE = json.dumps(
    {
        "nodes": [
            {"slug": "plan", "title": "Prepare the move", "description": "Prepare for the move", "parents": [], "node_type": "task"},
            {"slug": "boxes", "title": "Pack boxes", "description": "Pack the things", "parents": ["plan"], "node_type": "task"},
            {"slug": "labels", "title": "Label boxes", "description": "Put labels on the boxes", "parents": ["boxes"], "node_type": "task"},
        ],
        "requires": [],
    },
    ensure_ascii=False,
)


def test_it07_task_nodes_get_the_task_question_at_any_position(client, client_engine, monkeypatch):
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: ScriptedProvider(planner=TASK_COURSE))
    ids = ids_by_slug(generate(client, "Moving", search_syllabus=False))
    for skill_id in ids.values():
        set_status_by_api(client_engine, skill_id)

    for slug, title, position in (("plan", "Prepare the move", "root"), ("boxes", "Pack boxes", "branch"), ("labels", "Label boxes", "leaf")):
        body = client.post(f"/api/skills/{ids[slug]}/audits").json()
        assert body["opening_question"] == f"How exactly will you do “{title}”?"
        assert body["session"]["node_position"] == position


def test_the_session_response_matches_the_contract_shape(client, math):
    body = client.post(f"/api/skills/{math['high-school-math']}/audits", json={"mode": "day"}).json()

    assert set(body) == {"session", "opening_question"}
    assert set(body["session"]) == {"id", "skill_id", "node_position", "status", "score", "gaps", "comment", "turns"}
    assert body["session"]["skill_id"] == math["high-school-math"]
    assert (body["session"]["status"], body["session"]["score"], body["session"]["gaps"], body["session"]["comment"]) == (
        "active", None, [], None,
    )


def test_the_mode_defaults_to_day_and_other_values_are_rejected(client, client_engine, math):
    no_body = client.post(f"/api/skills/{math['high-school-math']}/audits")
    bad = client.post(f"/api/skills/{math['high-school-math']}/audits", json={"mode": "midnight"})

    assert no_body.status_code == 200
    assert bad.status_code == 422
    assert stored_audit(client_engine, no_body.json()["session"]["id"]).max_turns == settings.audit_max_turns


@pytest.mark.parametrize(
    ("mode", "concept", "task"),
    [("day", 8, 4), ("night", 16, 8)],
)
def test_turn_limits_are_eight_for_concepts_and_four_for_tasks_and_night_doubles(
    client, client_engine, monkeypatch, math, mode, concept, task
):
    concept_audit = start(client, math["high-school-math"], mode)
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: ScriptedProvider(planner=TASK_COURSE))
    task_ids = ids_by_slug(generate(client, "Moving", search_syllabus=False))
    task_audit = start(client, task_ids["plan"], mode)

    assert stored_audit(client_engine, concept_audit).max_turns == concept
    assert stored_audit(client_engine, task_audit).max_turns == task


def test_it12_an_available_node_with_unmet_requires_can_be_audited(client, client_engine, math):
    # quadratic-function requires quadratic-equation and linear-function, neither mastered.
    set_status_by_api(client_engine, math["quadratic-function"])

    response = client.post(f"/api/skills/{math['quadratic-function']}/audits")

    assert response.status_code == 200
    assert node_status(client, math["quadratic-equation"]) == "locked"


def test_a_mastered_node_can_be_audited_again_and_stays_mastered_after_a_fail(client, math):
    pass_node(client, math["high-school-math"])
    assert node_status(client, math["high-school-math"]) == "mastered"

    fail_node(client, math["high-school-math"])

    assert node_status(client, math["high-school-math"]) == "mastered"
    pass_node(client, math["high-school-math"])  # and it can be passed again
    assert node_status(client, math["high-school-math"]) == "mastered"


# ---------------------------------------------------------------- 提交回答


def test_it08_a_turn_can_return_a_probe_and_the_session_stays_active(client, client_engine, math):
    audit_id = start(client, math["high-school-math"])

    response = client.post(f"/api/audits/{audit_id}/turns", json={"content": FIRST})

    assert response.status_code == 200
    probe = response.json()
    assert probe == {
        "type": "probe",
        "question": "Pick the most important term in your explanation and tell me what it means and why it matters.",
    }
    assert [role for role, _ in stored_turns(client_engine, audit_id)] == ["auditor", "user", "auditor"]
    assert stored_turns(client_engine, audit_id)[1] == ("user", FIRST)
    assert stored_turns(client_engine, audit_id)[2] == ("auditor", probe["question"])
    assert stored_audit(client_engine, audit_id).status == AuditStatus.active


def test_it09_pass_upheld_unlocks_children_masters_the_node_and_records_the_reward(client, client_engine, math):
    audit_id = start(client, math["high-school-math"])

    probe, verdict = answer_turns(client, audit_id, FIRST, LONG)

    assert probe["type"] == "probe"
    assert verdict == {
        "type": "verdict",
        "passed": True,
        "score": 91,  # min(95, 70 + 210 // 10)
        "gaps": [],
        "comment": "You explained the core idea and why it holds.",
        "unlocked_skill_ids": [math["algebra"], math["functions"], math["calculus"]],
        "reward_amount": 22,
        "reward_multiplier": 1.1,
    }
    assert node_status(client, math["high-school-math"]) == "mastered"
    assert [node_status(client, math[s]) for s in ("algebra", "functions", "calculus")] == ["available"] * 3
    assert node_status(client, math["quadratic-equation"]) == "locked"  # only direct children open

    with Session(client_engine) as session:
        root = session.get(SkillNode, math["high-school-math"])
        assert root.mastery_score == 91
        audit = session.get(AuditSession, audit_id)
        assert (audit.status, audit.score, audit.comment, audit.gaps_json) == (
            AuditStatus.passed, 91, "You explained the core idea and why it holds.", "[]",
        )
        (reward,) = session.exec(select(RewardEvent)).all()
        assert (reward.session_id, reward.amount, reward.multiplier) == (audit_id, 22, 1.1)


def test_the_probe_and_verdict_shapes_are_exactly_the_contract_keys(client, math):
    audit_id = start(client, math["high-school-math"])

    probe, verdict = answer_turns(client, audit_id, FIRST, LONG)

    assert set(probe) == {"type", "question"}
    assert set(verdict) == {
        "type", "passed", "score", "gaps", "comment", "unlocked_skill_ids", "reward_amount", "reward_multiplier",
    }


def test_it10_a_node_with_two_parents_opens_when_either_parent_is_mastered(client, math):
    pass_node(client, math["high-school-math"])
    assert node_status(client, math["sequence-limit"]) == "locked"

    verdict = pass_node(client, math["calculus"])  # its main parent

    assert math["sequence-limit"] in verdict["unlocked_skill_ids"]
    assert node_status(client, math["sequence-limit"]) == "available"
    assert node_status(client, math["sequences"]) == "locked"  # the other parent is untouched


def test_it10_the_second_parent_opens_it_too(client, math):
    pass_node(client, math["high-school-math"])
    pass_node(client, math["algebra"])  # opens sequences (and quadratic-equation)

    verdict = pass_node(client, math["sequences"])  # its other, non-primary parent

    assert verdict["unlocked_skill_ids"] == [math["sequence-limit"]]
    assert node_status(client, math["calculus"]) == "available"  # the main parent was never mastered
    assert node_status(client, math["sequence-limit"]) == "available"


def test_it10_an_already_open_node_is_not_reported_as_unlocked_twice(client, math):
    pass_node(client, math["high-school-math"])
    pass_node(client, math["algebra"])
    pass_node(client, math["calculus"])  # opens sequence-limit through the main parent

    verdict = pass_node(client, math["sequences"])

    assert verdict["unlocked_skill_ids"] == []


def test_it11_a_node_with_two_parents_stays_locked_while_neither_is_mastered(client, math):
    pass_node(client, math["high-school-math"])
    pass_node(client, math["functions"])  # unrelated branch

    assert node_status(client, math["sequence-limit"]) == "locked"
    assert node_status(client, math["calculus"]) == "available"
    assert node_status(client, math["sequences"]) == "locked"


def test_it13_a_pass_the_challenger_overturns_becomes_one_more_probe(client, client_engine, math):
    audit_id = start(client, math["high-school-math"])

    first, challenge = answer_turns(client, audit_id, FIRST, MEDIUM)

    assert first["type"] == "probe"
    assert challenge == {"type": "probe", "question": CHALLENGER_QUESTION}
    audit = stored_audit(client_engine, audit_id)
    assert audit.challenged is True
    assert audit.status == AuditStatus.active
    assert stored_turns(client_engine, audit_id)[-1] == ("auditor", CHALLENGER_QUESTION)
    assert node_status(client, math["high-school-math"]) == "available"  # not mastered yet


def test_it14_after_an_overturn_the_next_pass_is_final_and_the_challenger_is_not_called_again(
    client, client_engine, monkeypatch, math
):
    provider = CountingProvider()
    use_provider(monkeypatch, provider)
    audit_id = start(client, math["high-school-math"])

    _probe, challenge, verdict = answer_turns(client, audit_id, FIRST, MEDIUM, MEDIUM)

    assert challenge["type"] == "probe"
    assert verdict["type"] == "verdict" and verdict["passed"] is True
    assert provider.counts == {"auditor": 3, "challenger": 1}
    assert node_status(client, math["high-school-math"]) == "mastered"
    assert stored_audit(client_engine, audit_id).status == AuditStatus.passed


def test_it14_a_fail_after_an_overturn_is_final_too(client, math):
    audit_id = start(client, math["high-school-math"])
    answer_turns(client, audit_id, FIRST, MEDIUM)  # overturned

    verdict = answer_turns(client, audit_id, "I don't know")[0]  # the latest answer admits it

    assert verdict["type"] == "verdict" and verdict["passed"] is False


def test_it15_with_the_challenger_disabled_a_pass_is_final_at_once(client, monkeypatch, math):
    monkeypatch.setattr(settings, "challenger_enabled", False)
    provider = CountingProvider()
    use_provider(monkeypatch, provider)
    audit_id = start(client, math["high-school-math"])

    _probe, verdict = answer_turns(client, audit_id, FIRST, MEDIUM)

    assert verdict["type"] == "verdict" and verdict["passed"] is True
    assert provider.counts == {"auditor": 2}


def test_a_fail_is_never_sent_to_the_challenger(client, monkeypatch, math):
    provider = CountingProvider()
    use_provider(monkeypatch, provider)
    audit_id = start(client, math["high-school-math"])

    answer_turns(client, audit_id, FIRST, SHORT)

    assert provider.counts == {"auditor": 2}


def test_a_challenger_that_errors_upholds_the_pass(client, monkeypatch, math):
    class ChallengerDown(CountingProvider):
        def complete(self, messages):
            if "[agent: challenger]" in messages[0]["content"]:
                raise RuntimeError("challenger is down")
            return super().complete(messages)

    use_provider(monkeypatch, ChallengerDown())
    audit_id = start(client, math["high-school-math"])

    _probe, verdict = answer_turns(client, audit_id, FIRST, MEDIUM)

    assert verdict["type"] == "verdict" and verdict["passed"] is True


def test_it16_a_fail_closes_the_session_and_leaves_the_node_status_alone(client, client_engine, math):
    audit_id = start(client, math["high-school-math"])

    _probe, verdict = answer_turns(client, audit_id, FIRST, SHORT)

    assert verdict == {
        "type": "verdict",
        "passed": False,
        "score": 45,
        "gaps": [
            "You stated the definition but not why it works.",
            "You didn't cover the exceptions.",
        ],
        "comment": "The answer stops at the conclusion and lacks reasons.",
        "unlocked_skill_ids": [],
        "reward_amount": None,
        "reward_multiplier": None,
    }
    assert node_status(client, math["high-school-math"]) == "available"
    assert node_status(client, math["algebra"]) == "locked"
    audit = stored_audit(client_engine, audit_id)
    assert (audit.status, audit.score) == (AuditStatus.failed, 45)
    assert json.loads(audit.gaps_json) == verdict["gaps"]
    assert audit.comment == verdict["comment"]
    with Session(client_engine) as session:
        assert session.exec(select(RewardEvent)).all() == []
        assert session.get(SkillNode, math["high-school-math"]).mastery_score is None


def test_a_failed_audit_can_be_followed_by_a_new_one(client, math):
    fail_node(client, math["high-school-math"])

    verdict = pass_node(client, math["high-school-math"])

    assert verdict["passed"] is True


@pytest.mark.parametrize("closing", ["pass", "fail"])
def test_it17_a_turn_on_a_closed_session_is_a_400(client, client_engine, math, closing):
    audit_id = start(client, math["high-school-math"])
    answer_turns(client, audit_id, FIRST, LONG if closing == "pass" else SHORT)
    turns_before = stored_turns(client_engine, audit_id)

    response = client.post(f"/api/audits/{audit_id}/turns", json={"content": "One more"})

    assert response.status_code == 400
    assert response.json() == {"detail": "audit session is already closed"}
    assert stored_turns(client_engine, audit_id) == turns_before  # nothing was saved


def test_it17_a_turn_on_a_missing_session_is_a_404(client):
    response = client.post("/api/audits/999/turns", json={"content": "Hello"})

    assert response.status_code == 404
    assert response.json() == {"detail": "audit session not found"}


@pytest.mark.parametrize("content", ["", "   ", "\n"])
def test_a_blank_answer_is_rejected(client, math, content):
    audit_id = start(client, math["high-school-math"])

    assert client.post(f"/api/audits/{audit_id}/turns", json={"content": content}).status_code == 422


def test_it18_an_auditor_failure_is_a_502_and_the_answer_is_kept(client, client_engine, monkeypatch, math):
    audit_id = start(client, math["high-school-math"])
    use_provider(monkeypatch, BrokenProvider())

    response = client.post(f"/api/audits/{audit_id}/turns", json={"content": FIRST})

    assert response.status_code == 502
    assert response.json() == {"detail": "The auditor is temporarily unavailable. Please try again."}
    assert stored_turns(client_engine, audit_id)[-1] == ("user", FIRST)
    assert stored_audit(client_engine, audit_id).status == AuditStatus.active


def test_it18_after_the_outage_the_resent_answer_replaces_the_unanswered_one(client, client_engine, monkeypatch, math):
    audit_id = start(client, math["high-school-math"])
    use_provider(monkeypatch, BrokenProvider())
    client.post(f"/api/audits/{audit_id}/turns", json={"content": FIRST})
    spy = ScriptedProvider(auditor=probe_json("Shall we go on?"))
    use_provider(monkeypatch, spy)

    # The client puts the text back in the input; the user sends it again (maybe edited).
    response = client.post(f"/api/audits/{audit_id}/turns", json={"content": "Sending again"})

    assert response.json() == {"type": "probe", "question": "Shall we go on?"}
    (messages,) = spy.calls_for("auditor")
    assert [m["content"] for m in messages[1:] if m["role"] == "user"] == ["Sending again"]
    assert [role for role, _ in stored_turns(client_engine, audit_id)] == ["auditor", "user", "auditor"]


def test_a_resend_does_not_use_up_the_turn_limit(client, client_engine, monkeypatch, math):
    audit_id = start(client, math["high-school-math"])
    for _ in range(3):
        use_provider(monkeypatch, BrokenProvider())
        client.post(f"/api/audits/{audit_id}/turns", json={"content": FIRST})
    use_provider(monkeypatch, ScriptedProvider(auditor=probe_json("Go on")))

    assert client.post(f"/api/audits/{audit_id}/turns", json={"content": FIRST}).json()["type"] == "probe"
    assert sum(role == "user" for role, _ in stored_turns(client_engine, audit_id)) == 1


class RacingProvider:
    """While this request waits for its verdict, another request finalizes the same audit."""

    name = "racing"

    def __init__(self, engine, audit_id: int):
        self._engine, self._audit_id = engine, audit_id

    def complete(self, messages):
        with Session(self._engine) as other:
            audit = other.get(AuditSession, self._audit_id)
            if audit.status == AuditStatus.active:
                audit.status = AuditStatus.passed
                other.add(audit)
                other.commit()
        return verdict_json(True, 90)


def test_an_audit_finalized_by_a_concurrent_request_is_not_finalized_twice(client, client_engine, monkeypatch, math):
    audit_id = start(client, math["high-school-math"])
    use_provider(monkeypatch, RacingProvider(client_engine, audit_id))

    response = client.post(f"/api/audits/{audit_id}/turns", json={"content": FIRST})

    assert response.status_code == 400
    assert response.json()["detail"] == "audit session is already closed"
    with Session(client_engine) as session:
        assert session.exec(select(RewardEvent)).all() == []


def test_a_malformed_auditor_answer_becomes_the_generic_probe(client, monkeypatch, math):
    use_provider(monkeypatch, ScriptedProvider(auditor="I am not sure what to say"))
    audit_id = start(client, math["high-school-math"])

    result = answer_turns(client, audit_id, FIRST)[0]

    assert result == {"type": "probe", "question": "Could you explain that part a bit more specifically?"}


# ---------------------------------------------------------------- 轮数上限


def test_the_turn_limit_forces_a_failing_verdict_with_score_zero(client, client_engine, monkeypatch, math):
    use_provider(monkeypatch, ScriptedProvider(auditor=probe_json("Keep going")))
    audit_id = start(client, math["high-school-math"])

    results = answer_turns(client, audit_id, *["answer"] * 8)

    assert [r["type"] for r in results] == ["probe"] * 7 + ["verdict"]
    assert results[-1]["passed"] is False
    assert results[-1]["score"] == 0
    assert results[-1]["unlocked_skill_ids"] == []
    assert stored_audit(client_engine, audit_id).status == AuditStatus.failed
    assert node_status(client, math["high-school-math"]) == "available"


def test_night_mode_doubles_the_turn_limit(client, monkeypatch, math):
    use_provider(monkeypatch, ScriptedProvider(auditor=probe_json()))
    audit_id = start(client, math["high-school-math"], "night")

    results = answer_turns(client, audit_id, *["answer"] * 16)

    assert [r["type"] for r in results] == ["probe"] * 15 + ["verdict"]
    assert results[-1]["score"] == 0


def test_a_task_node_is_forced_after_four_answers_and_eight_at_night(client, monkeypatch):
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: ScriptedProvider(planner=TASK_COURSE))
    ids = ids_by_slug(generate(client, "Moving", search_syllabus=False))
    use_provider(monkeypatch, ScriptedProvider(auditor=probe_json()))

    day = answer_turns(client, start(client, ids["plan"]), *["answer"] * 4)
    night = answer_turns(client, start(client, ids["plan"], "night"), *["answer"] * 8)

    assert [r["type"] for r in day] == ["probe"] * 3 + ["verdict"]
    assert [r["type"] for r in night] == ["probe"] * 7 + ["verdict"]


# ---------------------------------------------------------------- 教训、pacing 进入 Auditor 的 prompt


def test_lessons_from_a_neighbour_node_are_given_to_the_auditor(client, client_engine, monkeypatch, math):
    with Session(client_engine) as session:
        origin = session.get(SkillNode, math["quadratic-equation"])
        make_principle(session, origin, title="State the domain", misconception="No real roots means no solutions")
    set_status_by_api(client_engine, math["quadratic-function"])  # requires quadratic-equation
    spy = ScriptedProvider(auditor=probe_json())
    use_provider(monkeypatch, spy)
    audit_id = start(client, math["quadratic-function"])

    answer_turns(client, audit_id, FIRST)

    (prompt,) = spy.system_prompts("auditor")
    assert "- State the domain: When …, I …. (misconception: No real roots means no solutions)" in prompt


def test_lessons_from_unrelated_nodes_are_not(client, client_engine, monkeypatch, math):
    with Session(client_engine) as session:
        make_principle(session, session.get(SkillNode, math["derivative"]), title="Unrelated lesson")
    set_status_by_api(client_engine, math["quadratic-function"])
    spy = ScriptedProvider(auditor=probe_json())
    use_provider(monkeypatch, spy)

    answer_turns(client, start(client, math["quadratic-function"]), FIRST)

    assert "<lessons>\nnone\n</lessons>" in spy.system_prompts("auditor")[0]


def test_the_position_and_parts_reach_the_auditor_prompt(client, monkeypatch, math):
    spy = ScriptedProvider(auditor=probe_json())
    use_provider(monkeypatch, spy)

    answer_turns(client, start(client, math["high-school-math"]), FIRST)

    (prompt,) = spy.system_prompts("auditor")
    assert "Node: High School Math" in prompt
    assert "Position: root" in prompt
    assert "Parts: Algebra, Functions, Calculus\n" in prompt
    assert "This is the whole field." in prompt


def add_checkins(client_engine, sleeps: list[int | None], stresses: list[int | None] | None = None):
    from datetime import date, timedelta

    with Session(client_engine) as session:
        for i, sleep in enumerate(sleeps):
            session.add(
                DailyCheckIn(
                    date=date(2026, 10, 1) + timedelta(days=i),
                    sleep_hours=sleep,
                    stress=(stresses or [None] * len(sleeps))[i],
                )
            )
        session.commit()


def test_a_low_condition_makes_the_auditor_pace_light_without_touching_the_limit(client, client_engine, monkeypatch, math):
    add_checkins(client_engine, [5, 5, 5])
    spy = ScriptedProvider(auditor=probe_json())
    use_provider(monkeypatch, spy)
    audit_id = start(client, math["high-school-math"])

    answer_turns(client, audit_id, FIRST)

    assert "Pacing: light" in spy.system_prompts("auditor")[0]
    assert stored_audit(client_engine, audit_id).max_turns == settings.audit_max_turns


def test_a_normal_or_unknown_condition_paces_normally(client, client_engine, monkeypatch, math):
    spy = ScriptedProvider(auditor=probe_json())
    use_provider(monkeypatch, spy)
    answer_turns(client, start(client, math["high-school-math"]), FIRST)  # no check-ins: unknown
    add_checkins(client_engine, [8, 8, 8])
    answer_turns(client, start(client, math["high-school-math"]), FIRST)  # rested: normal

    assert ["Pacing: normal" in p for p in spy.system_prompts("auditor")] == [True, True]


def test_the_pass_standard_does_not_change_under_light_pacing(client, client_engine, math):
    add_checkins(client_engine, [4, 4, 4], [5, 5, 5])

    audit_id = start(client, math["high-school-math"])
    _probe, short = answer_turns(client, audit_id, FIRST, SHORT)
    _probe, long = answer_turns(client, start(client, math["high-school-math"]), FIRST, LONG)

    assert short["passed"] is False
    assert long["passed"] is True
