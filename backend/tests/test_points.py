"""The knowledge points inside a leaf, and picking an unfinished audit up again.

A leaf is the smallest node: the Planner (or, for a node that has none, the Point Lister
before its first audit) gives it its knowledge points; an audit examines the ones still open
and writes each result back, so the next one starts from what was missed; and a leaf that has
points is not broken down. An audit left unfinished goes on where it stopped.
"""

import json
from datetime import timedelta

import pytest
from sqlmodel import Session, select

from app.agents.planner import Planner
from app.agents.point_lister import PointLister, clean_points
from app.models import AuditSession, AuditStatus, EdgeKind, SkillNode, SkillStatus, utcnow
from app.services import audit_flow, points
from tests.helpers import (
    FIRST,
    LONG,
    SHORT,
    BrokenProvider,
    ScriptedProvider,
    answer_turns,
    fail_node,
    generate,
    ids_by_slug,
    link,
    make_course,
    make_skill,
    pass_node,
    probe_json,
    start,
)

POINTS = ["What Discriminant is", "Why Discriminant holds", "Where Discriminant fails"]
NOTE = "Named it without saying why it holds."


@pytest.fixture(name="math")
def math_fixture(client):
    return ids_by_slug(generate(client, "Math"))


def node(client, skill_id: int) -> dict:
    return next(n for n in client.get("/api/skills").json() if n["id"] == skill_id)


def begin(client, skill_id: int, **body) -> dict:
    response = client.post(f"/api/skills/{skill_id}/audits", json=body)
    assert response.status_code == 200, response.text
    return response.json()


# ---------------------------------------------------------------- where the points come from


def test_clean_points_trims_drops_doubles_and_keeps_six():
    raw = ["  Self-attention ", "self-attention", "", None, "x" * 60, "b", "c", "d", "e", "f"]

    assert clean_points(raw) == ["Self-attention", "x" * 40, "b", "c", "d", "e"]
    assert clean_points("Self-attention") == []


def test_the_planner_gives_a_concept_leaf_its_points(client, monkeypatch):
    plan = json.dumps(
        {
            "nodes": [
                {"slug": "dl", "title": "Deep Learning", "description": "d", "parents": [], "points": ["ignored"]},
                {
                    "slug": "tf",
                    "title": "Transformer Basics",
                    "description": "d",
                    "parents": ["dl"],
                    "points": ["Self-attention", "Feed-forward layer", "Positional encoding"],
                },
                {"slug": "later", "title": "Vision Models", "description": "d", "parents": ["dl"], "expand": True,
                 "points": ["ignored"]},
            ],
            "requires": [],
        }
    )
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: ScriptedProvider(planner=plan))

    nodes = {n["slug"]: n for n in generate(client, "Deep Learning", search_syllabus=False)["nodes"]}

    assert nodes["tf"]["points"] == [
        {"title": "Self-attention", "ok": None, "note": None},
        {"title": "Feed-forward layer", "ok": None, "note": None},
        {"title": "Positional encoding", "ok": None, "note": None},
    ]
    assert nodes["dl"]["points"] == [] and nodes["later"]["points"] == []  # not leaves


def test_the_planner_prompt_asks_for_points_and_keeps_them_inside_the_leaf():
    provider = ScriptedProvider(planner=json.dumps({"nodes": [{"slug": "a", "title": "A", "parents": []}]}))
    Planner(provider).generate("Deep Learning")
    (prompt,) = provider.system_prompts("planner")

    assert "What is inside a leaf is its knowledge points, never more nodes" in prompt
    assert "- points: for a concept leaf, its three to six knowledge points" in prompt


def test_the_point_lister_names_the_leaf_and_refuses_a_thin_answer():
    provider = ScriptedProvider(point_lister=json.dumps({"points": ["Self-attention", "Positional encoding"]}))
    listed = PointLister(provider).list("Deep Learning", "Transformer Basics", "Attention and position")
    (prompt,) = provider.system_prompts("point_lister")

    assert listed == ["Self-attention", "Positional encoding"]
    assert "Leaf: Transformer Basics\nCovers: Attention and position" in prompt
    assert PointLister(ScriptedProvider(point_lister='{"points": ["Only one"]}')).list("c", "t", "d") == []
    assert PointLister(ScriptedProvider(point_lister="not json")).list("c", "t", "d") == []


def test_a_leaf_without_points_gets_them_before_its_first_audit_only(client, monkeypatch, math):
    assert node(client, math["discriminant"])["points"] == []
    spy = ScriptedProvider()
    monkeypatch.setattr("app.routers.audits.get_provider", lambda agent=None: spy)

    fail_node(client, math["discriminant"])
    start(client, math["discriminant"])

    assert len(spy.calls_for("point_lister")) == 1
    assert [p["title"] for p in node(client, math["discriminant"])["points"]] == POINTS


def test_a_branch_a_task_and_a_challenge_get_no_points(client, client_engine, math):
    with Session(client_engine) as session:
        algebra = session.get(SkillNode, math["algebra"])
        algebra.status = SkillStatus.available
        session.add(algebra)
        session.commit()

    assert begin(client, math["algebra"])["session"]["points"] == []
    assert begin(client, math["functions"], test_out=True)["session"]["points"] == []
    assert node(client, math["algebra"])["points"] == []


def test_a_failing_point_lister_leaves_the_audit_as_it_was(client, monkeypatch, math):
    monkeypatch.setattr("app.routers.audits.get_provider", lambda agent=None: BrokenProvider())

    body = begin(client, math["discriminant"])

    assert body["session"]["points"] == []
    assert body["opening_question"] == "Explain “Discriminant” from scratch to someone who has never heard of it."


# ---------------------------------------------------------------- what an audit does with them


def test_a_fail_records_what_held_and_what_was_missed_with_its_note(client, client_engine, math):
    audit_id = fail_node(client, math["discriminant"])

    assert node(client, math["discriminant"])["points"] == [
        {"title": POINTS[0], "ok": False, "note": NOTE},
        {"title": POINTS[1], "ok": True, "note": None},
        {"title": POINTS[2], "ok": True, "note": None},
    ]
    with Session(client_engine) as session:  # the audit keeps its own result too
        assert [p["ok"] for p in session.get(AuditSession, audit_id).points] == [False, True, True]


def test_the_next_audit_asks_only_about_what_was_missed(client, client_engine, monkeypatch, math):
    fail_node(client, math["discriminant"])
    spy = ScriptedProvider()
    monkeypatch.setattr("app.routers.audits.get_provider", lambda agent=None: spy)

    body = begin(client, math["discriminant"])
    answer_turns(client, body["session"]["id"], FIRST)

    assert body["opening_question"] == (
        "What you already explained right stays cleared. This time only “What Discriminant is”: "
        "what does it do, and why is it needed?"
    )
    assert body["session"]["points"] == [{"title": POINTS[0], "ok": None, "note": NOTE}]
    with Session(client_engine) as session:
        assert session.get(AuditSession, body["session"]["id"]).max_turns == 4  # one point: the least
    (prompt,) = spy.system_prompts("auditor")
    assert f"- {POINTS[0]} — {NOTE}\n" in prompt  # she sees what was wrong last time
    assert f"do not ask about them again: {POINTS[1]}, {POINTS[2]}\n" in prompt


def test_passing_what_was_missed_clears_the_node(client, math):
    fail_node(client, math["discriminant"])

    verdict = pass_node(client, math["discriminant"])

    assert verdict["points"] == [{"title": POINTS[0], "ok": True, "note": None}]
    after = node(client, math["discriminant"])
    assert after["status"] == "mastered"
    assert [(p["ok"], p["note"]) for p in after["points"]] == [(True, None)] * 3


def test_a_review_of_a_mastered_node_asks_every_point_again(client, math):
    pass_node(client, math["discriminant"])

    body = begin(client, math["discriminant"])

    assert [p["title"] for p in body["session"]["points"]] == POINTS
    assert body["opening_question"].startswith("Let's take “Discriminant” one piece at a time.")


def test_a_point_the_audit_did_not_settle_keeps_what_it_had():
    skill = SkillNode(course_id=1, slug="s", title="S", description="")
    skill.points_json = points.dump(
        [{"title": "A", "ok": False, "note": "old note"}, {"title": "B", "ok": True}, {"title": "C", "ok": None}]
    )

    points.record_results(
        skill, [{"title": "A", "ok": None}, {"title": "B", "ok": False, "note": "new"}, {"title": "C", "ok": True}]
    )

    assert skill.points == [
        {"title": "A", "ok": False, "note": "old note"},
        {"title": "B", "ok": False, "note": "new"},
        {"title": "C", "ok": True, "note": None},
    ]


def test_her_feedback_goes_back_to_her_with_her_question(client, monkeypatch, math):
    spy = ScriptedProvider(
        auditor=[json.dumps({"action": "probe", "feedback": "Half right: the sign is wrong.", "question": "Why?"})]
    )
    monkeypatch.setattr("app.routers.audits.get_provider", lambda agent=None: spy)
    audit_id = start(client, math["discriminant"])

    first, _second = answer_turns(client, audit_id, FIRST, "Because of the square root.")

    assert (first["feedback"], first["question"]) == ("Half right: the sign is wrong.", "Why?")
    history = spy.calls_for("auditor")[-1]
    assert history[-2] == {"role": "assistant", "content": "Half right: the sign is wrong.\n\nWhy?"}


# ---------------------------------------------------------------- the smallest node


def test_a_leaf_with_points_is_not_broken_down(client, monkeypatch, math):
    start(client, math["discriminant"])  # it has its points now
    spy = ScriptedProvider()
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: spy)

    response = client.post(f"/api/skills/{math['discriminant']}/expand")

    assert response.status_code == 400
    assert response.json() == {"detail": "This node is the smallest piece: its knowledge points are inside it."}
    assert spy.calls_for("planner") == []


def test_a_leaf_without_points_and_a_branch_can_still_be_broken_down(client, math):
    assert client.post(f"/api/skills/{math['root-coefficient']}/expand").status_code == 200
    assert client.post(f"/api/skills/{math['algebra']}/expand").status_code == 200


def test_points_do_not_count_once_the_node_has_parts(client_engine):
    with Session(client_engine) as session:
        course = make_course(session)
        root = make_skill(session, course, "root")
        leaf = make_skill(session, course, "leaf")
        link(session, root, leaf, EdgeKind.contains)
        points.set_points(leaf, ["A", "B"])
        session.add(leaf)
        session.commit()
        assert points.has_points(session, leaf) is True

        link(session, leaf, make_skill(session, course, "part"), EdgeKind.contains)

        assert points.has_points(session, leaf) is False


# ---------------------------------------------------------------- picking an audit up again


def test_an_unfinished_audit_is_picked_up_with_its_dialogue(client, math):
    first = begin(client, math["discriminant"])
    (probe,) = answer_turns(client, first["session"]["id"], FIRST)

    again = begin(client, math["discriminant"])

    assert again["resumed"] is True
    assert again["session"]["id"] == first["session"]["id"]
    assert again["opening_question"] == first["opening_question"]
    assert again["session"]["turns"] == [
        {"role": "auditor", "content": first["opening_question"], "feedback": None},
        {"role": "user", "content": FIRST, "feedback": None},
        {"role": "auditor", "content": probe["question"], "feedback": probe["feedback"]},
    ]


def test_restart_begins_a_new_audit_and_that_one_is_picked_up_next(client, math):
    first = begin(client, math["discriminant"])
    answer_turns(client, first["session"]["id"], FIRST)

    fresh = begin(client, math["discriminant"], restart=True)
    again = begin(client, math["discriminant"])

    assert fresh["resumed"] is False and fresh["session"]["id"] != first["session"]["id"]
    assert len(fresh["session"]["turns"]) == 1
    assert again["session"]["id"] == fresh["session"]["id"]


def test_a_closed_audit_is_not_picked_up(client, math):
    closed = fail_node(client, math["discriminant"])

    body = begin(client, math["discriminant"])

    assert body["resumed"] is False and body["session"]["id"] != closed


def test_an_old_unfinished_audit_is_not_picked_up(client, client_engine, math):
    stale = start(client, math["discriminant"])
    with Session(client_engine) as session:
        audit = session.get(AuditSession, stale)
        audit.created_at = utcnow() - timedelta(hours=audit_flow.RESUME_HOURS + 1)
        session.add(audit)
        session.commit()

    assert begin(client, math["discriminant"])["resumed"] is False


def test_an_audit_and_a_challenge_of_one_node_do_not_pick_each_other_up(client, math):
    challenge = begin(client, math["functions"], test_out=True)

    again = begin(client, math["functions"], test_out=True)

    assert again["resumed"] is True and again["session"]["id"] == challenge["session"]["id"]
    assert again["session"]["test_out"] is True


def test_picking_up_calls_no_model(client, monkeypatch, math):
    start(client, math["discriminant"])
    monkeypatch.setattr("app.routers.audits.get_provider", lambda agent=None: BrokenProvider())

    assert begin(client, math["discriminant"])["resumed"] is True


def test_a_picked_up_audit_goes_on_to_its_verdict(client, client_engine, math):
    first = start(client, math["discriminant"])
    answer_turns(client, first, FIRST)

    resumed = begin(client, math["discriminant"])["session"]["id"]
    (verdict,) = answer_turns(client, resumed, LONG)

    assert verdict["passed"] is True
    with Session(client_engine) as session:
        audits = session.exec(select(AuditSession)).all()
        assert [(a.id, a.status) for a in audits] == [(first, AuditStatus.passed)]


def test_short_answers_after_picking_up_still_fail(client, math):
    first = start(client, math["discriminant"])
    answer_turns(client, first, FIRST)

    (verdict,) = answer_turns(client, begin(client, math["discriminant"])["session"]["id"], SHORT)

    assert verdict["passed"] is False


def test_the_probe_json_helper_has_no_feedback(client, monkeypatch, math):
    monkeypatch.setattr("app.routers.audits.get_provider", lambda agent=None: ScriptedProvider(auditor=probe_json()))

    (probe,) = answer_turns(client, start(client, math["discriminant"]), FIRST)

    assert probe["feedback"] is None


# ---------------------------------------------------------------- a break-down that finds one leaf

ONE_LEAF = json.dumps({"nodes": [], "points": ["Epipolar geometry", "Triangulation", "Bundle adjustment"]})


def test_a_category_the_planner_finds_to_be_one_leaf_stays_whole_with_its_points(client, monkeypatch):
    vision = {n["slug"]: n for n in generate(client, "Computer Vision")["nodes"]}
    geometry = next(n for n in vision.values() if n["unexpanded"])
    spy = ScriptedProvider(planner=ONE_LEAF)
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: spy)

    body = client.post(f"/api/skills/{geometry['id']}/expand").json()

    after = next(n for n in body["nodes"] if n["id"] == geometry["id"])
    assert len(body["nodes"]) == len(vision)  # no parts were added
    assert after["unexpanded"] is False  # a leaf now: it can be audited
    assert [p["title"] for p in after["points"]] == ["Epipolar geometry", "Triangulation", "Bundle adjustment"]
    # ... and it is the smallest piece from here on.
    assert client.post(f"/api/skills/{geometry['id']}/expand").status_code == 400
    assert len(spy.calls_for("planner")) == 1


def test_the_break_down_prompt_decides_leaf_or_category_first(client, monkeypatch):
    vision = {n["slug"]: n for n in generate(client, "Computer Vision")["nodes"]}
    geometry = next(n for n in vision.values() if n["unexpanded"])
    spy = ScriptedProvider(planner=ONE_LEAF)
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: spy)

    client.post(f"/api/skills/{geometry['id']}/expand")

    (prompt,) = spy.system_prompts("planner")
    assert "First decide what that node is" in prompt
    assert "Its components, steps and variants are its knowledge\n  points, not nodes." in prompt
    assert 'output an empty "nodes" list and,\n  beside it, a "points" list' in prompt


def test_points_beside_parts_are_ignored(client, monkeypatch):
    vision = {n["slug"]: n for n in generate(client, "Computer Vision")["nodes"]}
    geometry = next(n for n in vision.values() if n["unexpanded"])
    answer = json.dumps(
        {
            "nodes": [{"slug": "stereo", "title": "Stereo Vision", "description": "d", "parents": [geometry["slug"]]}],
            "points": ["Should not be kept"],
        }
    )
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: ScriptedProvider(planner=answer))

    body = client.post(f"/api/skills/{geometry['id']}/expand").json()

    assert next(n for n in body["nodes"] if n["id"] == geometry["id"])["points"] == []
    assert any(n["title"] == "Stereo Vision" for n in body["nodes"])
