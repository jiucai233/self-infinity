"""The developer panel (contract #34): finished audits with their transcripts, reviews of the
Auditor's verdicts, and the metrics they add up to."""

from app.config import settings
from app.services.audit_review import kappa
from tests.helpers import MATH_ORDER, fail_node, generate, ids_by_slug, pass_node, start
from tests.test_accounts import ALICE, BOB, accounts_fixture, auth  # noqa: F401


def panel(client, **params) -> dict:
    response = client.get("/api/dev/audits", params=params)
    assert response.status_code == 200, response.text
    return response.json()


def review(client, audit_id: int, value, leaked: bool = False):
    return client.put(f"/api/dev/audits/{audit_id}/review", json={"review": value, "leaked": leaked})


def test_finished_audits_newest_first_with_the_transcript(client):
    ids = ids_by_slug(generate(client, "Math"))
    failed = fail_node(client, ids["discriminant"])
    pass_node(client, ids["discriminant"])
    start(client, ids["root-coefficient"])  # still running: not listed

    audits = panel(client)["audits"]

    assert [a["status"] for a in audits] == ["passed", "failed"]
    old = audits[1]
    assert old["id"] == failed and old["skill_title"] == "Discriminant"
    assert old["score"] == 45 and len(old["gaps"]) == 2 and old["comment"]
    assert [t["role"] for t in old["turns"]] == ["auditor", "user", "auditor", "user"]
    assert (old["review"], old["leaked"]) == (None, False)
    assert len(panel(client, limit=1)["audits"]) == 1


def test_metrics_before_any_review(client):
    ids = ids_by_slug(generate(client, "Math"))
    fail_node(client, ids["discriminant"])
    pass_node(client, ids["discriminant"])

    metrics = panel(client)["metrics"]

    assert metrics["finished"] == 2 and metrics["pass_rate"] == 0.5
    assert metrics["avg_gaps_when_failed"] == 2 and metrics["avg_answers"] == 2
    assert metrics["reviewed"] == 0
    assert metrics["agreement"] is None and metrics["kappa"] is None
    assert (metrics["too_strict"], metrics["too_lenient"], metrics["leaked"]) == (0, 0, 0)


def test_reviews_add_up_to_agreement_kappa_and_the_two_kinds_of_misjudgement(client):
    ids = ids_by_slug(generate(client, "Math"))
    fails = [fail_node(client, ids["discriminant"]) for _ in range(2)]
    for slug in MATH_ORDER[:2]:
        pass_node(client, ids[slug])
    passed_ids = [a["id"] for a in panel(client)["audits"] if a["status"] == "passed"]

    assert review(client, fails[0], "right").status_code == 200
    assert review(client, fails[1], "too_strict").status_code == 200
    assert review(client, passed_ids[0], "right", leaked=True).json()["leaked"] is True
    assert review(client, passed_ids[1], "too_lenient").status_code == 200

    metrics = panel(client)["metrics"]
    assert metrics["reviewed"] == 4 and metrics["agreement"] == 0.5
    assert (metrics["too_strict"], metrics["too_lenient"], metrics["leaked"]) == (1, 1, 1)
    # Auditor: fail fail pass pass; human: fail pass pass fail -> agreement no better than chance.
    assert metrics["kappa"] == 0.0


def test_a_review_must_fit_the_verdict_and_can_be_cleared(client):
    ids = ids_by_slug(generate(client, "Math"))
    failed = fail_node(client, ids["discriminant"])
    running = start(client, ids["discriminant"])

    assert review(client, failed, "too_lenient").json() == {"detail": "too_lenient is for a passed audit"}
    assert review(client, running, "right").json() == {"detail": "audit is not finished"}
    assert review(client, 999, "right").status_code == 404
    assert review(client, failed, "wrong").status_code == 422

    review(client, failed, "too_strict", leaked=True)
    cleared = review(client, failed, None).json()
    assert (cleared["review"], cleared["leaked"]) == (None, False)
    assert panel(client)["metrics"]["reviewed"] == 0


def test_kappa():
    assert kappa([]) is None
    assert kappa([(True, True), (False, False)]) == 1.0
    assert kappa([(True, True), (True, True)]) is None  # both always say pass: undefined
    assert kappa([(True, False), (False, True)]) == -1.0


def test_with_accounts_only_the_listed_emails_are_developers(accounts, monkeypatch):
    alice = auth(ALICE, email="alice@example.com")
    bob = auth(BOB, email="bob@example.com")
    monkeypatch.setattr(settings, "dev_emails", " Alice@Example.com , carol@example.com")

    assert accounts.get("/api/dev/audits", headers=alice).status_code == 200
    assert accounts.get("/api/me", headers=alice).json()["is_dev"] is True
    assert accounts.get("/api/dev/audits", headers=bob).json() == {"detail": "developers only"}
    assert accounts.put("/api/dev/audits/1/review", headers=bob, json={"review": None}).status_code == 403
    assert accounts.get("/api/dev/voice", headers=bob).status_code == 403
    assert accounts.get("/api/dev/voice", headers=alice).status_code == 200
    assert accounts.get("/api/me", headers=bob).json()["is_dev"] is False
