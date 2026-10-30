"""审计接口：开场问题、追问 / 裁决、解锁、复核、错误处理（IT-05 ~ IT-18）。

Mock 的审计脚本是确定的（契约 4.3），所以大多数测试只靠回答的长短来驱动：
第一个回答一律追问；之后按总字数裁决，< 80 不通过；Challenger 在 < 160 时推翻一次。
"""

import json
import threading

import pytest
from sqlmodel import Session, select

from app.config import settings
from app.models import (
    AuditSession,
    AuditStatus,
    AuditTurn,
    DailyCheckIn,
    LearnerPoint,
    NodePosition,
    PrincipleCheck,
    RewardEvent,
    SkillNode,
    SkillStatus,
)
from app.services import learner
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
PROBE_FEEDBACK = "That gives the outline. One part of it is still only named, not explained."
PASS_FEEDBACK = "That is right, and you gave the reason for it."
FAIL_FEEDBACK = "The conclusion is there, but the reason behind it is missing."
# The script's knowledge points of the leaf “Discriminant” (the Point Lister, before its first audit).
POINTS = ["What Discriminant is", "Why Discriminant holds", "Where Discriminant fails"]


def held(*oks: bool | None, note: str | None = None) -> list[dict]:
    """The points of “Discriminant” with these results; `note` goes on the first one missed."""
    out = [{"title": title, "ok": ok, "note": None} for title, ok in zip(POINTS, oks)]
    for point in out:
        if point["ok"] is False:
            point["note"] = note
            break
    return out


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
    set_status_by_api(client_engine, math["high-school-math"])  # it opens last

    response = client.post(f"/api/skills/{math['high-school-math']}/audits")

    assert response.status_code == 200
    body = response.json()
    expected = "Which problems call for “High School Math”, and which don't? How do you decide?"
    assert body["opening_question"] == expected
    assert body["session"]["node_position"] == "root"
    assert body["session"]["turns"] == [{"role": "auditor", "content": expected, "feedback": None}]
    assert body["session"]["points"] == []  # only a leaf has knowledge points
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

    # A leaf opens with the student asking to be taught, with its knowledge points or without:
    # the points are what she listens for, not questions to walk through.
    assert body["opening_question"] == "I have never learned “Discriminant”. Teach it to me from the start."
    assert body["session"]["points"] == held(None, None, None)
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
    body = client.post(f"/api/skills/{math['discriminant']}/audits", json={"mode": "day"}).json()

    assert set(body) == {"session", "opening_question", "resumed"}
    assert body["resumed"] is False
    assert set(body["session"]) == {
        "id", "skill_id", "node_position", "status", "score", "gaps", "comment", "turns", "test_out", "points",
        "evidence", "lessons", "principle", "skill_title", "created_at", "agreement", "too_hard", "disputed",
        "audience", "depth",
    }
    assert body["session"]["test_out"] is False
    assert body["session"]["skill_id"] == math["discriminant"]
    assert (body["session"]["status"], body["session"]["score"], body["session"]["gaps"], body["session"]["comment"]) == (
        "active", None, [], None,
    )


def test_the_mode_defaults_to_day_and_other_values_are_rejected(client, client_engine, math):
    no_body = client.post(f"/api/skills/{math['discriminant']}/audits")
    bad = client.post(f"/api/skills/{math['discriminant']}/audits", json={"mode": "midnight"})

    assert no_body.status_code == 200
    assert bad.status_code == 422
    assert stored_audit(client_engine, no_body.json()["session"]["id"]).max_turns == 6  # two a point


@pytest.mark.parametrize(
    ("mode", "points", "concept", "task"),
    [("day", 6, 8, 4), ("night", 12, 16, 8)],
)
def test_turn_limits_are_two_a_point_eight_for_concepts_and_four_for_tasks_and_night_doubles(
    client, client_engine, monkeypatch, math, mode, points, concept, task
):
    leaf_audit = start(client, math["discriminant"], mode)  # three knowledge points
    set_status_by_api(client_engine, math["algebra"])
    concept_audit = start(client, math["algebra"], mode)  # a branch: no points
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: ScriptedProvider(planner=TASK_COURSE))
    task_ids = ids_by_slug(generate(client, "Moving", search_syllabus=False))
    task_audit = start(client, task_ids["labels"], mode)  # the leaf opens first

    assert stored_audit(client_engine, leaf_audit).max_turns == points
    assert stored_audit(client_engine, concept_audit).max_turns == concept
    assert stored_audit(client_engine, task_audit).max_turns == task


def test_it12_an_available_node_with_unmet_requires_can_be_audited(client, client_engine, math):
    # quadratic-function requires quadratic-equation and linear-function, neither mastered.
    set_status_by_api(client_engine, math["quadratic-function"])

    response = client.post(f"/api/skills/{math['quadratic-function']}/audits")

    assert response.status_code == 200
    assert node_status(client, math["quadratic-equation"]) == "locked"


def test_a_mastered_node_can_be_audited_again_and_stays_mastered_after_a_fail(client, math):
    pass_node(client, math["discriminant"])
    assert node_status(client, math["discriminant"]) == "mastered"

    fail_node(client, math["discriminant"])

    assert node_status(client, math["discriminant"]) == "mastered"
    pass_node(client, math["discriminant"])  # and it can be passed again
    assert node_status(client, math["discriminant"]) == "mastered"


# ---------------------------------------------------------------- 提交回答


def test_it08_a_turn_can_return_a_probe_and_the_session_stays_active(client, client_engine, math):
    audit_id = start(client, math["discriminant"])

    response = client.post(f"/api/audits/{audit_id}/turns", json={"content": FIRST})

    assert response.status_code == 200
    probe = response.json()
    assert probe == {
        "type": "probe",
        "question": "Pick the most important term in your explanation and tell me what it means and why it matters.",
        "feedback": PROBE_FEEDBACK,
        "point": POINTS[0],
    }
    assert [role for role, _ in stored_turns(client_engine, audit_id)] == ["auditor", "user", "auditor"]
    assert stored_turns(client_engine, audit_id)[1] == ("user", FIRST)
    assert stored_turns(client_engine, audit_id)[2] == ("auditor", probe["question"])
    assert stored_audit(client_engine, audit_id).status == AuditStatus.active
    with Session(client_engine) as session:  # what she said about the answer is kept with her question
        assert session.exec(select(AuditTurn.feedback).order_by(AuditTurn.id)).all() == [None, None, PROBE_FEEDBACK]


def test_it09_pass_upheld_opens_the_next_node_masters_this_one_and_records_the_reward(client, client_engine, math):
    audit_id = start(client, math["discriminant"])

    probe, verdict = answer_turns(client, audit_id, FIRST, LONG)

    assert probe["type"] == "probe"
    assert verdict == {
        "type": "verdict",
        "passed": True,
        "score": 91,  # min(95, 70 + 210 // 10)
        "gaps": [],
        "evidence": [],
        "lessons": [],
        "comment": "You explained the core idea and why it holds.",
        "feedback": PASS_FEEDBACK,
        "points": held(True, True, True),
        "unlocked_skill_ids": [math["root-coefficient"]],  # the next in the learning order
        "reward_amount": 55,
        "reward_multiplier": 1.1,
    }
    assert node_status(client, math["discriminant"]) == "mastered"
    assert node_status(client, math["root-coefficient"]) == "available"
    assert node_status(client, math["quadratic-equation"]) == "locked"  # one node at a time

    with Session(client_engine) as session:
        root = session.get(SkillNode, math["discriminant"])
        assert root.mastery_score == 91
        audit = session.get(AuditSession, audit_id)
        assert (audit.status, audit.score, audit.comment, audit.gaps_json) == (
            AuditStatus.passed, 91, "You explained the core idea and why it holds.", "[]",
        )
        (reward,) = session.exec(select(RewardEvent)).all()
        assert (reward.session_id, reward.amount, reward.multiplier) == (audit_id, 55, 1.1)


def test_the_probe_and_verdict_shapes_are_exactly_the_contract_keys(client, math):
    audit_id = start(client, math["discriminant"])

    probe, verdict = answer_turns(client, audit_id, FIRST, LONG)

    assert set(probe) == {"type", "question", "feedback", "point"}
    assert set(verdict) == {
        "type", "passed", "score", "gaps", "evidence", "lessons", "comment", "feedback", "points",
        "unlocked_skill_ids", "reward_amount", "reward_multiplier",
    }


def test_it13_a_pass_the_challenger_overturns_becomes_one_more_probe(client, client_engine, math):
    audit_id = start(client, math["discriminant"])

    first, challenge = answer_turns(client, audit_id, FIRST, MEDIUM)

    assert first["type"] == "probe"
    # The Challenger's question, after what the Auditor said about the answer.
    assert challenge == {"type": "probe", "question": CHALLENGER_QUESTION, "feedback": PASS_FEEDBACK, "point": None}
    audit = stored_audit(client_engine, audit_id)
    assert audit.challenged is True
    assert audit.status == AuditStatus.active
    assert stored_turns(client_engine, audit_id)[-1] == ("auditor", CHALLENGER_QUESTION)
    assert node_status(client, math["discriminant"]) == "available"  # not mastered yet


def test_it14_after_an_overturn_the_next_pass_is_final_and_the_challenger_is_not_called_again(
    client, client_engine, monkeypatch, math
):
    provider = CountingProvider()
    use_provider(monkeypatch, provider)
    audit_id = start(client, math["discriminant"])

    _probe, challenge, verdict = answer_turns(client, audit_id, FIRST, MEDIUM, MEDIUM)

    assert challenge["type"] == "probe"
    assert verdict["type"] == "verdict" and verdict["passed"] is True
    assert provider.counts == {"point_lister": 1, "auditor": 7, "challenger": 1}
    assert node_status(client, math["discriminant"]) == "mastered"
    assert stored_audit(client_engine, audit_id).status == AuditStatus.passed


def test_it14_a_fail_after_an_overturn_is_final_too(client, math):
    audit_id = start(client, math["discriminant"])
    answer_turns(client, audit_id, FIRST, MEDIUM)  # overturned

    verdict = answer_turns(client, audit_id, "I don't know")[0]  # the latest answer admits it

    assert verdict["type"] == "verdict" and verdict["passed"] is False


def test_it15_with_the_challenger_disabled_a_pass_is_final_at_once(client, monkeypatch, math):
    monkeypatch.setattr(settings, "challenger_enabled", False)
    provider = CountingProvider()
    use_provider(monkeypatch, provider)
    audit_id = start(client, math["discriminant"])

    _probe, verdict = answer_turns(client, audit_id, FIRST, MEDIUM)

    assert verdict["type"] == "verdict" and verdict["passed"] is True
    assert provider.counts == {"point_lister": 1, "auditor": 4}


def test_a_fail_is_never_sent_to_the_challenger(client, monkeypatch, math):
    provider = CountingProvider()
    use_provider(monkeypatch, provider)
    audit_id = start(client, math["discriminant"])

    answer_turns(client, audit_id, FIRST, SHORT)

    assert provider.counts == {"point_lister": 1, "auditor": 4}


def test_a_challenger_that_errors_upholds_the_pass(client, monkeypatch, math):
    class ChallengerDown(CountingProvider):
        def complete(self, messages):
            if "[agent: challenger]" in messages[0]["content"]:
                raise RuntimeError("challenger is down")
            return super().complete(messages)

    use_provider(monkeypatch, ChallengerDown())
    audit_id = start(client, math["discriminant"])

    _probe, verdict = answer_turns(client, audit_id, FIRST, MEDIUM)

    assert verdict["type"] == "verdict" and verdict["passed"] is True


def test_it16_a_fail_closes_the_session_and_leaves_the_node_status_alone(client, client_engine, math):
    audit_id = start(client, math["discriminant"])

    _probe, verdict = answer_turns(client, audit_id, FIRST, SHORT)

    assert verdict == {
        "type": "verdict",
        "passed": False,
        "score": 45,
        "gaps": [
            "You stated the definition but not why it works.",
            "You didn't cover the exceptions.",
        ],
        "evidence": [
            {"gap": gap, "said": SHORT[:80], "right": "The mechanism has to be explained step by step, with what each step is for."}
            for gap in (
                "You stated the definition but not why it works.",
                "You didn't cover the exceptions.",
            )
        ],
        "lessons": [],
        "comment": "The answer stops at the conclusion and lacks reasons.",
        "feedback": FAIL_FEEDBACK,
        "points": held(False, True, True, note="Named it without saying why it holds."),
        "unlocked_skill_ids": [],
        "reward_amount": None,
        "reward_multiplier": None,
    }
    assert node_status(client, math["discriminant"]) == "available"
    assert node_status(client, math["algebra"]) == "locked"
    audit = stored_audit(client_engine, audit_id)
    assert (audit.status, audit.score) == (AuditStatus.failed, 45)
    assert json.loads(audit.gaps_json) == verdict["gaps"]
    assert audit.comment == verdict["comment"]
    with Session(client_engine) as session:
        assert session.exec(select(RewardEvent)).all() == []
        assert session.get(SkillNode, math["discriminant"]).mastery_score is None


def test_a_failed_audit_can_be_followed_by_a_new_one(client, math):
    fail_node(client, math["discriminant"])

    verdict = pass_node(client, math["discriminant"])

    assert verdict["passed"] is True


@pytest.mark.parametrize("closing", ["pass", "fail"])
def test_it17_a_turn_on_a_closed_session_is_a_400(client, client_engine, math, closing):
    audit_id = start(client, math["discriminant"])
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
    audit_id = start(client, math["discriminant"])

    assert client.post(f"/api/audits/{audit_id}/turns", json={"content": content}).status_code == 422


def test_it18_an_auditor_failure_is_a_502_and_the_answer_is_kept(client, client_engine, monkeypatch, math):
    audit_id = start(client, math["discriminant"])
    use_provider(monkeypatch, BrokenProvider())

    response = client.post(f"/api/audits/{audit_id}/turns", json={"content": FIRST})

    assert response.status_code == 502
    assert response.json() == {"detail": "The auditor is temporarily unavailable. Please try again."}
    assert stored_turns(client_engine, audit_id)[-1] == ("user", FIRST)
    assert stored_audit(client_engine, audit_id).status == AuditStatus.active


def test_it18_after_the_outage_the_resent_answer_replaces_the_unanswered_one(client, client_engine, monkeypatch, math):
    audit_id = start(client, math["discriminant"])
    use_provider(monkeypatch, BrokenProvider())
    client.post(f"/api/audits/{audit_id}/turns", json={"content": FIRST})
    spy = ScriptedProvider(auditor=probe_json("Shall we go on?"))
    use_provider(monkeypatch, spy)

    # The client puts the text back in the input; the user sends it again (maybe edited).
    response = client.post(f"/api/audits/{audit_id}/turns", json={"content": "Sending again"})

    assert response.json() == {"type": "probe", "question": "Shall we go on?", "feedback": None, "point": None}
    (messages,) = spy.calls_for("auditor")
    assert [m["content"] for m in messages[1:] if m["role"] == "user"] == ["Sending again"]
    assert [role for role, _ in stored_turns(client_engine, audit_id)] == ["auditor", "user", "auditor"]


def test_a_resend_does_not_use_up_the_turn_limit(client, client_engine, monkeypatch, math):
    audit_id = start(client, math["discriminant"])
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
    audit_id = start(client, math["discriminant"])
    use_provider(monkeypatch, RacingProvider(client_engine, audit_id))

    response = client.post(f"/api/audits/{audit_id}/turns", json={"content": FIRST})

    assert response.status_code == 400
    assert response.json()["detail"] == "audit session is already closed"
    with Session(client_engine) as session:
        assert session.exec(select(RewardEvent)).all() == []


def test_a_malformed_auditor_answer_becomes_the_generic_probe(client, monkeypatch, math):
    use_provider(monkeypatch, ScriptedProvider(auditor="I am not sure what to say"))
    audit_id = start(client, math["discriminant"])

    result = answer_turns(client, audit_id, FIRST)[0]

    assert result == {
        "type": "probe",
        "question": "Could you explain that part a bit more specifically?",
        "feedback": None,
        "point": None,
    }


# ---------------------------------------------------------------- 轮数上限


def test_the_turn_limit_forces_a_failing_verdict_with_score_zero(client, client_engine, monkeypatch, math):
    use_provider(monkeypatch, ScriptedProvider(auditor=probe_json("Keep going")))
    audit_id = start(client, math["discriminant"])

    results = answer_turns(client, audit_id, *["answer"] * 6)  # three points, two questions each

    assert [r["type"] for r in results] == ["probe"] * 5 + ["verdict"]
    assert results[-1]["passed"] is False
    assert results[-1]["score"] == 0
    assert results[-1]["unlocked_skill_ids"] == []
    assert results[-1]["points"] == held(None, None, None)  # nothing settled: all stay open
    assert stored_audit(client_engine, audit_id).status == AuditStatus.failed
    assert node_status(client, math["discriminant"]) == "available"


def test_night_mode_doubles_the_turn_limit(client, monkeypatch, math):
    use_provider(monkeypatch, ScriptedProvider(auditor=probe_json()))
    audit_id = start(client, math["discriminant"], "night")

    results = answer_turns(client, audit_id, *["answer"] * 12)

    assert [r["type"] for r in results] == ["probe"] * 11 + ["verdict"]
    assert results[-1]["score"] == 0


def test_a_task_node_is_forced_after_four_answers_and_eight_at_night(client, monkeypatch):
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: ScriptedProvider(planner=TASK_COURSE))
    ids = ids_by_slug(generate(client, "Moving", search_syllabus=False))
    use_provider(monkeypatch, ScriptedProvider(auditor=probe_json()))

    day = answer_turns(client, start(client, ids["labels"]), *["answer"] * 4)
    night = answer_turns(client, start(client, ids["labels"], "night"), *["answer"] * 8)

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


def test_the_position_and_parts_reach_the_auditor_prompt(client, client_engine, monkeypatch, math):
    set_status_by_api(client_engine, math["high-school-math"])
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
    audit_id = start(client, math["discriminant"])

    answer_turns(client, audit_id, FIRST)

    assert "Pacing: light" in spy.system_prompts("auditor")[0]
    assert stored_audit(client_engine, audit_id).max_turns == 6  # two a point, as when rested


def test_a_normal_or_unknown_condition_paces_normally(client, client_engine, monkeypatch, math):
    spy = ScriptedProvider(auditor=probe_json())
    use_provider(monkeypatch, spy)
    answer_turns(client, start(client, math["discriminant"]), FIRST)  # no check-ins: unknown
    add_checkins(client_engine, [8, 8, 8])
    answer_turns(client, start(client, math["discriminant"]), FIRST)  # rested: normal

    assert ["Pacing: normal" in p for p in spy.system_prompts("auditor")] == [True, True]


def test_the_pass_standard_does_not_change_under_light_pacing(client, client_engine, math):
    add_checkins(client_engine, [4, 4, 4], [5, 5, 5])

    audit_id = start(client, math["discriminant"])
    _probe, short = answer_turns(client, audit_id, FIRST, SHORT)
    _probe, long = answer_turns(client, start(client, math["discriminant"]), FIRST, LONG)

    assert short["passed"] is False
    assert long["passed"] is True


# ---------------------------------------------------------------- replay: evidence, lessons, GET one audit

MOCK_RIGHT = "The mechanism has to be explained step by step, with what each step is for."


def reflect(client, audit_id: int) -> dict:
    response = client.post(f"/api/audits/{audit_id}/reflection", json={"reflection": "I thought no real roots meant no solutions."})
    assert response.status_code == 200, response.text
    return response.json()


def test_a_failed_audit_carries_the_users_own_words_as_evidence_and_the_replay_returns_them(client, math):
    audit_id = start(client, math["discriminant"])

    _probe, verdict = answer_turns(client, audit_id, FIRST, SHORT)

    assert [(e["gap"], e["said"], e["right"]) for e in verdict["evidence"]] == [(gap, SHORT, MOCK_RIGHT) for gap in verdict["gaps"]]
    response = client.get(f"/api/audits/{audit_id}")
    assert response.status_code == 200
    body = response.json()
    assert body["id"] == audit_id and body["status"] == "failed" and body["score"] == 45
    assert body["evidence"] == verdict["evidence"]
    assert body["gaps"] == verdict["gaps"]
    assert [t["role"] for t in body["turns"]] == ["auditor", "user", "auditor", "user"]
    assert body["turns"][1]["content"] == FIRST and body["turns"][3]["content"] == SHORT
    assert body["skill_title"] == "Discriminant"
    assert body["created_at"].endswith("Z") or body["created_at"].endswith("+00:00")
    assert body["principle"] is None


def test_after_a_reflection_the_replay_returns_the_lesson_with_no_checks_yet(client, math):
    audit_id = fail_node(client, math["discriminant"])

    principle = reflect(client, audit_id)

    body = client.get(f"/api/audits/{audit_id}").json()
    assert body["principle"] == principle
    assert body["principle"]["held"] == 0 and body["principle"]["relapsed"] == 0


def test_the_replay_of_an_unknown_audit_is_404(client):
    response = client.get("/api/audits/999")

    assert response.status_code == 404
    assert response.json()["detail"] == "audit session not found"


def test_the_same_mistake_again_is_a_relapse_of_the_lesson_and_is_recorded(client, client_engine, math):
    first = fail_node(client, math["discriminant"])
    principle = reflect(client, first)

    second = start(client, math["discriminant"])
    _probe, verdict = answer_turns(client, second, FIRST, SHORT)

    assert verdict["lessons"] == [{"principle_id": principle["id"], "title": principle["title"], "held": False}]
    (listed,) = client.get("/api/principles").json()
    assert listed["id"] == principle["id"]
    assert (listed["relapsed"], listed["held"]) == (1, 0)
    with Session(client_engine) as session:
        (check,) = session.exec(select(PrincipleCheck)).all()
        assert (check.principle_id, check.session_id, check.held) == (principle["id"], second, False)
    assert client.get(f"/api/audits/{second}").json()["lessons"] == verdict["lessons"]


def test_only_the_audit_a_lesson_was_made_from_is_marked_reflected(client, math):
    first = fail_node(client, math["discriminant"])
    second = fail_node(client, math["discriminant"])
    reflect(client, first)

    listed = {a["id"]: a["reflected"] for a in client.get("/api/audits").json()}
    overview = {a["id"]: a["reflected"] for a in client.get(f"/api/skills/{math['discriminant']}/overview").json()["audits"]}

    assert listed == {first: True, second: False}
    assert overview == listed


def test_an_audit_stored_before_evidence_existed_still_gives_one_empty_entry_per_gap(client, client_engine, math):
    audit_id = fail_node(client, math["discriminant"])
    with Session(client_engine) as session:
        audit = session.get(AuditSession, audit_id)
        audit.evidence_json = None
        session.add(audit)
        session.commit()

    body = client.get(f"/api/audits/{audit_id}").json()

    assert len(body["gaps"]) == 2
    assert body["evidence"] == [{"gap": gap, "said": None, "right": None} for gap in body["gaps"]]


# ---------------------------------------------------------------- votes: several judgements, the majority


class VotingProvider(CountingProvider):
    """The first Auditor call is a probe; the verdict calls after it give `verdicts` in the order
    they come (they run in parallel threads, so a test relies only on how many of them pass).
    A verdict that is an Exception is raised."""

    def __init__(self, *verdicts):
        super().__init__()
        self._verdicts = list(verdicts)
        self._lock = threading.Lock()
        self._verdict_calls = 0

    def complete(self, messages):
        if "[agent: auditor]" not in messages[0]["content"]:
            return super().complete(messages)
        with self._lock:
            self.counts["auditor"] = self.counts.get("auditor", 0) + 1
            if self.counts["auditor"] == 1:
                return probe_json("Why?")
            verdict = self._verdicts[min(self._verdict_calls, len(self._verdicts) - 1)]
            self._verdict_calls += 1
        if isinstance(verdict, Exception):
            raise verdict
        return verdict_json(verdict, 80 if verdict else 20)


def judged(client, client_engine, monkeypatch, math, *verdicts):
    monkeypatch.setattr(settings, "challenger_enabled", False)
    provider = VotingProvider(*verdicts)
    use_provider(monkeypatch, provider)
    audit_id = start(client, math["discriminant"])
    _probe, verdict = answer_turns(client, audit_id, FIRST, LONG)
    assert verdict["type"] == "verdict"
    return audit_id, verdict, provider


def test_with_one_vote_the_auditor_is_called_once_on_a_verdict_and_there_is_no_agreement(
    client, client_engine, monkeypatch, math
):
    monkeypatch.setattr(settings, "auditor_votes", 1)
    monkeypatch.setattr(settings, "challenger_enabled", False)
    provider = CountingProvider()
    use_provider(monkeypatch, provider)
    audit_id = start(client, math["discriminant"])

    answer_turns(client, audit_id, FIRST, LONG)

    assert provider.counts["auditor"] == 2
    assert client.get(f"/api/audits/{audit_id}").json()["agreement"] is None


def test_by_default_a_verdict_is_judged_three_times_and_the_mock_agrees_with_itself(client, monkeypatch, math):
    monkeypatch.setattr(settings, "challenger_enabled", False)
    provider = CountingProvider()
    use_provider(monkeypatch, provider)
    audit_id = start(client, math["discriminant"])

    answer_turns(client, audit_id, FIRST, LONG)

    assert provider.counts["auditor"] == 4  # a probe, then three judgements
    assert client.get(f"/api/audits/{audit_id}").json()["agreement"] == 1.0


def test_one_pass_in_three_is_a_fail_with_two_thirds_agreement(client, client_engine, monkeypatch, math):
    audit_id, verdict, provider = judged(client, client_engine, monkeypatch, math, True, False, False)

    assert verdict["passed"] is False
    assert provider.counts["auditor"] == 4
    body = client.get(f"/api/audits/{audit_id}").json()
    assert body["status"] == "failed"
    assert body["agreement"] == pytest.approx(2 / 3)


def test_two_passes_in_three_is_a_pass_with_two_thirds_agreement(client, client_engine, monkeypatch, math):
    audit_id, verdict, _ = judged(client, client_engine, monkeypatch, math, True, True, False)

    assert verdict["passed"] is True
    body = client.get(f"/api/audits/{audit_id}").json()
    assert body["status"] == "passed"
    assert body["agreement"] == pytest.approx(2 / 3)


def test_a_tie_between_two_votes_is_a_fail(client, client_engine, monkeypatch, math):
    monkeypatch.setattr(settings, "auditor_votes", 2)

    audit_id, verdict, _ = judged(client, client_engine, monkeypatch, math, True, False)

    assert verdict["passed"] is False
    assert client.get(f"/api/audits/{audit_id}").json()["agreement"] == 0.5


def test_an_extra_vote_that_raises_does_not_vote(client, client_engine, monkeypatch, math):
    audit_id, verdict, _ = judged(client, client_engine, monkeypatch, math, True, True, RuntimeError("down"))

    assert verdict["passed"] is True
    assert client.get(f"/api/audits/{audit_id}").json()["agreement"] == 1.0


def test_the_judge_version_is_stored_on_the_finalized_audit(client, client_engine, math):
    from app.agents.auditor import JUDGE_VERSION

    audit_id = start(client, math["discriminant"])
    assert stored_audit(client_engine, audit_id).judge_version is None

    answer_turns(client, audit_id, FIRST, LONG)

    assert stored_audit(client_engine, audit_id).judge_version == JUDGE_VERSION


# ---------------------------------------------------------------- feedback and the learner


def points_difficulties(client_engine, skill_id: int) -> dict[str, float]:
    with Session(client_engine) as session:
        rows = session.exec(select(LearnerPoint).where(LearnerPoint.skill_id == skill_id)).all()
        return {r.title: r.difficulty for r in rows}


def test_too_hard_on_a_failed_audit_is_set_and_raises_the_difficulty_once(client, client_engine, math):
    audit_id = fail_node(client, math["discriminant"])
    before = points_difficulties(client_engine, math["discriminant"])

    first = client.post(f"/api/audits/{audit_id}/feedback", json={"kind": "too_hard"})
    after = points_difficulties(client_engine, math["discriminant"])
    second = client.post(f"/api/audits/{audit_id}/feedback", json={"kind": "too_hard"})

    assert first.status_code == 200 and first.json()["too_hard"] is True
    assert before and set(after) == set(before)
    # Only the point the audit did not pass gets harder; the ones explained right stay.
    missed = {p["title"] for p in stored_audit(client_engine, audit_id).points if p["ok"] is not True}
    assert missed and missed != set(before)
    assert all(after[t] == pytest.approx(before[t] + (learner.TOO_HARD_STEP if t in missed else 0)) for t in before)
    assert second.status_code == 200
    assert points_difficulties(client_engine, math["discriminant"]) == after


def test_misheard_marks_the_audit_disputed_and_raises_the_false_fail_rate(client, client_engine, math):
    audit_id = fail_node(client, math["discriminant"])
    before = client.get("/api/learner").json()

    response = client.post(f"/api/audits/{audit_id}/feedback", json={"kind": "misheard"})

    assert response.status_code == 200 and response.json()["disputed"] is True
    assert stored_audit(client_engine, audit_id).disputed is True
    assert client.get("/api/learner").json()["judge_false_fail"] > before["judge_false_fail"]


def test_feedback_on_a_passed_or_an_active_audit_is_a_400(client, math):
    pass_node(client, math["discriminant"])
    passed_id = client.get("/api/audits").json()[0]["id"]
    active_id = start(client, math["root-coefficient"])

    for audit_id in (passed_id, active_id):
        response = client.post(f"/api/audits/{audit_id}/feedback", json={"kind": "too_hard"})
        assert response.status_code == 400
        assert response.json()["detail"] == "feedback is only accepted for a failed audit"


def test_feedback_on_an_unknown_audit_is_a_404(client):
    response = client.post("/api/audits/999/feedback", json={"kind": "too_hard"})

    assert response.status_code == 404
    assert response.json()["detail"] == "audit session not found"


def test_an_unknown_kind_of_feedback_is_a_422(client, math):
    audit_id = fail_node(client, math["discriminant"])

    assert client.post(f"/api/audits/{audit_id}/feedback", json={"kind": "boring"}).status_code == 422


def test_the_learner_has_exactly_these_keys_and_aims_at_three_quarters(client, math):
    body = client.get("/api/learner").json()

    assert set(body) == {
        "ability", "target_chance", "judge_false_pass", "judge_false_fail", "nodes", "history", "styles", "evaluation",
    }
    assert body["target_chance"] == 0.75
    assert body["ability"] == 0
    assert body["nodes"] and all(set(n) == {"skill_id", "title", "chance"} for n in body["nodes"])


def test_the_learner_lists_the_available_nodes_nearest_the_target_first(client, math):
    body = client.get("/api/learner").json()

    available = {n["id"] for n in client.get("/api/skills").json() if n["status"] == "available"}
    assert {n["skill_id"] for n in body["nodes"]} == available
    distances = [abs(n["chance"] - 0.75) for n in body["nodes"]]
    assert distances == sorted(distances)


def test_after_a_failed_audit_that_missed_every_point_the_ability_is_lower(client, monkeypatch, math):
    verdict = json.dumps({
        "action": "verdict", "pass": False, "score": 10, "gaps": ["g"], "comment": "No.",
        "points": [{"point": title, "ok": False, "note": "n"} for title in POINTS],
    })
    use_provider(monkeypatch, ScriptedProvider(auditor=[probe_json("Why?"), verdict]))
    before = client.get("/api/learner").json()["ability"]
    audit_id = start(client, math["discriminant"])

    _probe, result = answer_turns(client, audit_id, FIRST, SHORT)

    assert result["passed"] is False
    assert client.get("/api/learner").json()["ability"] < before


def test_two_of_three_judgements_wanting_to_ask_on_keep_the_audit_going(monkeypatch):
    """A verdict two of the three would not give yet is not given: the audit goes on."""
    from app.agents.auditor import AuditorTurnResult
    from app.services import audit_flow

    verdict = AuditorTurnResult(is_verdict=True, passed=True, score=90, gaps=[], comment="ok")
    probe = AuditorTurnResult(is_verdict=False, question="And the edge case?")

    chosen, agreement, challenge = audit_flow._voted(verdict, lambda: probe, alongside=lambda: "challenge?")

    assert chosen is probe and agreement == pytest.approx(2 / 3)
    assert challenge is None  # a pass that was not given is not challenged


def test_on_a_final_turn_judgements_that_disagree_are_not_a_pass(monkeypatch):
    from app.agents.auditor import AuditorTurnResult
    from app.services import audit_flow

    passed = AuditorTurnResult(is_verdict=True, passed=True, score=90, gaps=[], comment="ok")
    failed = AuditorTurnResult(is_verdict=True, passed=False, score=40, gaps=["x"], comment="no")
    monkeypatch.setattr(audit_flow.settings, "auditor_votes", 2)

    chosen, agreement, _ = audit_flow._voted(passed, lambda: failed, final=True)

    assert chosen is failed and agreement == 0.5


def test_the_challenger_runs_beside_the_votes_and_its_question_is_kept_for_a_pass():
    from app.agents.auditor import AuditorTurnResult
    from app.services import audit_flow

    passed = AuditorTurnResult(is_verdict=True, passed=True, score=90, gaps=[], comment="ok")

    chosen, agreement, challenge = audit_flow._voted(passed, lambda: passed, alongside=lambda: "Why does it hold?")

    assert chosen.passed and agreement == 1.0 and challenge == "Why does it hold?"


def test_the_learner_keeps_the_ability_after_each_audit(client, math):
    assert client.get("/api/learner").json()["history"] == []

    first = fail_node(client, math["discriminant"])
    second = start(client, math["discriminant"])
    answer_turns(client, second, FIRST, LONG)

    body = client.get("/api/learner").json()
    history = body["history"]

    assert [(h["audit_id"], h["passed"], h["skill_title"]) for h in history] == [
        (first, False, "Discriminant"),
        (second, True, "Discriminant"),
    ]
    assert set(history[0]) == {
        "audit_id", "skill_id", "skill_title", "passed", "ability", "progress", "agreement", "created_at",
    }
    assert history[-1]["ability"] == body["ability"]  # the last step is where the learner stands
    assert all(0 <= h["progress"] <= 1 for h in history)
