"""The audit length preference (contract #53) and the stars a verdict is shown as.

Short asks one point, standard every open point, thorough every point again; a pass is worth
1 / 2 / 3 stars by length (a challenge 3, a fail 0). Stars are only what the user sees: the
pass / fail decision and everything after it are as before.
"""

import pytest
from sqlmodel import Session

from app.models import AuditSession, AuditStatus, SkillNode, SkillStatus
from app.services import audit_flow
from tests.helpers import FIRST, LONG, SHORT, answer_turns, generate, ids_by_slug, make_audit, make_course, make_skill, start


@pytest.fixture(name="math")
def math_fixture(client):
    return ids_by_slug(generate(client, "Math"))


def set_length(client, length: str):
    response = client.put("/api/audit-length", json={"audit_length": length})
    assert response.status_code == 200, response.text
    return response.json()


def begin(client, skill_id: int, **body) -> dict:
    response = client.post(f"/api/skills/{skill_id}/audits", json=body)
    assert response.status_code == 200, response.text
    return response.json()


def stored(client_engine, audit_id: int) -> AuditSession:
    with Session(client_engine) as session:
        return session.get(AuditSession, audit_id)


def test_the_preference_defaults_to_standard_and_is_kept(client):
    assert client.get("/api/audit-length").json() == {"audit_length": "standard"}
    assert set_length(client, "thorough") == {"audit_length": "thorough"}
    assert client.get("/api/audit-length").json() == {"audit_length": "thorough"}


@pytest.mark.parametrize("value", ["long", "", None, 3])
def test_any_other_length_is_a_422(client, value):
    assert client.put("/api/audit-length", json={"audit_length": value}).status_code == 422
    assert client.get("/api/audit-length").json() == {"audit_length": "standard"}


def test_standard_is_what_audits_were_before(client, client_engine, math):
    body = begin(client, math["discriminant"])

    assert len(body["session"]["points"]) == 3
    audit = stored(client_engine, body["session"]["id"])
    assert (audit.max_turns, audit.length) == (6, "standard")


def test_short_examines_the_first_point_and_two_turns(client, client_engine, math):
    set_length(client, "short")
    body = begin(client, math["discriminant"])

    assert [p["title"] for p in body["session"]["points"]] == ["What Discriminant is"]
    audit = stored(client_engine, body["session"]["id"])
    assert (audit.max_turns, audit.length) == (2, "short")
    assert body["session"]["length"] == "short"


def test_thorough_examines_every_point_again_and_may_run_longer(client, client_engine, math):
    # A fail leaves two points held, one missed: standard asks the one, thorough all three.
    audit_id = start(client, math["discriminant"])
    answer_turns(client, audit_id, FIRST, SHORT)
    set_length(client, "thorough")

    body = begin(client, math["discriminant"], restart=True)

    assert len(body["session"]["points"]) == 3
    assert all(p["ok"] is None for p in body["session"]["points"])
    audit = stored(client_engine, body["session"]["id"])
    assert (audit.max_turns, audit.length) == (6, "thorough")


def test_max_turns_by_length():
    from app.models import NodeType

    f = audit_flow.max_turns_for
    assert [f(NodeType.concept, "day", 5, n) for n in ("short", "standard", "thorough")] == [2, 10, 10]
    assert f(NodeType.concept, "day", 7, "thorough") == 14
    assert f(NodeType.concept, "day", 1, "thorough") == 4
    assert f(NodeType.concept, "night", 1, "short") == 4
    # Without points: half (at least 2), as it was, two more.
    base = f(NodeType.concept, "day")
    assert (f(NodeType.concept, "day", 0, "short"), f(NodeType.concept, "day", 0, "thorough")) == (max(2, base // 2), base + 2)


def test_a_challenge_ignores_the_preference(client, client_engine, math):
    set_length(client, "short")
    body = begin(client, math["quadratic-equation"], test_out=True)

    audit = stored(client_engine, body["session"]["id"])
    assert audit.length is None and audit.test_out is True
    assert audit.max_turns == audit_flow.max_turns_for(audit_flow.NodeType.concept, "day")


@pytest.mark.parametrize("length,stars", [("short", 1), ("standard", 2), ("thorough", 3)])
def test_a_pass_is_worth_stars_by_length(client, client_engine, math, length, stars):
    set_length(client, length)
    audit_id = start(client, math["discriminant"])
    _probe, verdict = answer_turns(client, audit_id, FIRST, LONG)

    assert verdict["passed"] is True and verdict["stars"] == stars
    assert stored(client_engine, audit_id).stars == stars
    assert client.get(f"/api/audits/{audit_id}").json()["stars"] == stars
    assert next(a for a in client.get("/api/audits").json() if a["id"] == audit_id)["stars"] == stars
    node = next(n for n in client.get("/api/skills").json() if n["id"] == math["discriminant"])
    assert node["best_stars"] == stars and node["status"] == "mastered"


def test_a_fail_is_zero_stars_and_changes_nothing_else(client, client_engine, math):
    set_length(client, "thorough")
    audit_id = start(client, math["discriminant"])
    _probe, verdict = answer_turns(client, audit_id, FIRST, SHORT)

    assert verdict["passed"] is False and verdict["stars"] == 0
    node = next(n for n in client.get("/api/skills").json() if n["id"] == math["discriminant"])
    assert node["best_stars"] is None and node["status"] == "available"
    assert client.get(f"/api/audits/{audit_id}").json()["status"] == "failed"


def test_a_passed_challenge_is_three_stars(client, math):
    ids = ids_by_slug(generate(client, "Math"))
    set_length(client, "short")
    audit_id = begin(client, ids["quadratic-equation"], test_out=True)["session"]["id"]
    _probe, verdict = answer_turns(client, audit_id, FIRST, LONG)

    assert verdict["passed"] is True and verdict["stars"] == 3
    node = next(n for n in client.get("/api/skills").json() if n["id"] == ids["quadratic-equation"])
    assert node["best_stars"] == 3


def test_a_node_keeps_its_best_stars(client, client_engine, math):
    set_length(client, "thorough")
    first = start(client, math["discriminant"])
    answer_turns(client, first, FIRST, LONG)
    set_length(client, "short")
    again = start(client, math["discriminant"])
    _probe, verdict = answer_turns(client, again, FIRST, LONG)

    assert verdict["stars"] == 1
    node = next(n for n in client.get("/api/skills").json() if n["id"] == math["discriminant"])
    assert node["best_stars"] == 3
    overview = client.get(f"/api/skills/{math['discriminant']}/overview").json()
    assert overview["skill"]["best_stars"] == 3
    assert sorted(a["stars"] for a in overview["audits"]) == [1, 3]


def test_audits_from_before_stars_are_shown_as_two_for_a_pass_and_zero_for_a_fail(client, client_engine):
    with Session(client_engine) as session:
        skill = make_skill(session, make_course(session), "old", status=SkillStatus.mastered)
        passed = make_audit(session, skill, AuditStatus.passed, score=80).id
        failed = make_audit(session, skill, AuditStatus.failed, score=20).id
        active = make_audit(session, skill, AuditStatus.active).id
        skill_id = skill.id

    assert client.get(f"/api/audits/{passed}").json()["stars"] == 2
    assert client.get(f"/api/audits/{failed}").json()["stars"] == 0
    assert client.get(f"/api/audits/{active}").json()["stars"] == 0
    by_id = {a["id"]: a for a in client.get("/api/audits").json()}
    assert (by_id[passed]["stars"], by_id[failed]["stars"]) == (2, 0)
    # An older mastered node counts as two stars too.
    assert next(n for n in client.get("/api/skills").json() if n["id"] == skill_id)["best_stars"] == 2
