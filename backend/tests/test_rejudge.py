"""Finished audits judged again under the Auditor's current rules (contract #50)."""

from sqlmodel import Session

from app.agents.auditor import JUDGE_VERSION
from app.models import AuditSession
from tests.helpers import ScriptedProvider, fail_node, generate, ids_by_slug, pass_node, verdict_json


def make_old(client_engine, *ids):
    with Session(client_engine) as session:
        for audit_id in ids:
            row = session.get(AuditSession, audit_id)
            row.judge_version = "2026-10-01"
            session.add(row)
        session.commit()


def test_old_audits_are_judged_again_beside_their_verdict(client, client_engine, monkeypatch):
    ids = ids_by_slug(generate(client, "Math"))
    failed = fail_node(client, ids["discriminant"])
    pass_node(client, ids["discriminant"])
    passed = failed + 1
    make_old(client_engine, failed)
    spy = ScriptedProvider(auditor=verdict_json(True))
    monkeypatch.setattr("app.routers.dev.get_provider", lambda agent=None: spy)

    assert client.get("/api/dev/rejudge").json() == {"version": JUDGE_VERSION, "judged": 0, "changed": 0, "left": 1}
    body = client.post("/api/dev/rejudge").json()

    assert body == {"version": JUDGE_VERSION, "judged": 1, "changed": 1, "left": 0}
    assert len(spy.calls_for("auditor")) == 1  # the current audit is not judged again
    assert "final turn" in spy.system_prompts("auditor")[0]
    with Session(client_engine) as session:
        row = session.get(AuditSession, failed)
        assert (row.status, row.rejudged_passed, row.rejudged_version) == ("failed", True, JUDGE_VERSION)
        assert session.get(AuditSession, passed).rejudged_version is None
    assert client.get("/api/dev/rejudge").json()["changed"] == 1
    assert client.post("/api/dev/rejudge").json()["judged"] == 0


def test_a_judgement_that_fails_leaves_the_audit_for_next_time(client, client_engine, monkeypatch):
    ids = ids_by_slug(generate(client, "Math"))
    failed = fail_node(client, ids["discriminant"])
    make_old(client_engine, failed)
    spy = ScriptedProvider(auditor="not json at all")
    monkeypatch.setattr("app.routers.dev.get_provider", lambda agent=None: spy)

    body = client.post("/api/dev/rejudge").json()

    assert (body["judged"], body["left"]) == (0, 1)
