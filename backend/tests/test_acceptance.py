"""验收场景（plan 1.3 的第 1-7 步），全程走 HTTP 接口，使用 Mock LLM 和 Mock 搜索。

这就是 docs/api-contract.md 第 4 节的演示脚本；Flutter 的 FakeApiClient 跑的是同一份，
所以这条测试通过，等于离线演示通了。
"""

from app.utils import local_today
from tests.helpers import FIRST, LONG, SHORT, answer_turns, start

SHORT_REFLECTION = "I thought no real roots meant no solutions."


def statuses(client) -> dict[str, str]:
    return {n["title"]: n["status"] for n in client.get("/api/skills", params={"course_id": 1}).json()}


def test_acceptance_scenario_end_to_end(client):
    # 1. The user enters “Math”. Nothing needs clarifying.
    assert client.post("/api/skills/clarify", json={"topic": "Math"}).json() == {
        "needs_clarification": False,
        "questions": [],
    }

    # 2. The system generates a course: 12 nodes, a syllabus source, and a learning order over the tree
    #    in which each chapter has one open node (parts before what contains them; the root comes last).
    generated = client.post("/api/skills/generate", json={"topic": "Math"}).json()
    ids = {n["title"]: n["id"] for n in generated["nodes"]}
    assert len(generated["nodes"]) == 12
    assert generated["course"]["source_course"] == "High School Mathematics Curriculum (Ministry of Education)"
    assert generated["course"]["source_url"].startswith("https://")
    now = statuses(client)
    assert [now.pop(t) for t in ("Discriminant", "Linear Functions", "Limits of Sequences")] == ["available"] * 3
    assert set(now.values()) == {"locked"}
    assert ids["Quadratic Equations"] == 5 and ids["Quadratic Functions"] == 10  # the ids used throughout the contract's examples

    # Passing its two parts opens the way to “Quadratic Equations” (a long explanation passes at once).
    first_audit = start(client, ids["Discriminant"])
    _probe, verdict = answer_turns(client, first_audit, FIRST, LONG)
    assert verdict["passed"] is True
    assert verdict["unlocked_skill_ids"] == [ids["Roots and Coefficients"]]

    second_audit = start(client, ids["Roots and Coefficients"])
    _probe, verdict = answer_turns(client, second_audit, FIRST, LONG)
    assert verdict["passed"] is True
    assert verdict["unlocked_skill_ids"] == [ids["Quadratic Equations"]]
    assert statuses(client)["Quadratic Equations"] == "available"

    # 3. The user audits “Quadratic Equations” and fails with a short answer.
    started = client.post(f"/api/skills/{ids['Quadratic Equations']}/audits").json()
    failed_audit = started["session"]["id"]
    assert started["session"]["node_position"] == "branch"  # it has children in the contract's table
    assert started["opening_question"].startswith("“Quadratic Equations” covers Discriminant, Roots and Coefficients.")
    probe, verdict = answer_turns(client, failed_audit, FIRST, SHORT)
    assert probe["type"] == "probe"
    assert verdict["type"] == "verdict" and verdict["passed"] is False
    assert verdict["score"] == 45 and len(verdict["gaps"]) == 2
    assert statuses(client)["Quadratic Equations"] == "available"  # a fail leaves the node as it was
    assert statuses(client)["Sequences"] == "locked"  # and the next one of its chapter closed

    # 4. The user submits a short reflection; the system stores a principle and the misconception.
    reflection = client.post(f"/api/audits/{failed_audit}/reflection", json={"reflection": SHORT_REFLECTION})
    assert reflection.status_code == 200
    principle = reflection.json()
    assert principle["title"] == "Revisit “Quadratic Equations”"
    assert principle["misconception"] == SHORT_REFLECTION  # the reflection (cut to 60 characters)
    assert principle["skill_id"] == ids["Quadratic Equations"] and principle["skill_title"] == "Quadratic Equations"
    assert [p["id"] for p in client.get("/api/principles").json()] == [principle["id"]]

    # 5. The user passes “Quadratic Equations” on a later attempt; the next node in the order opens.
    retry = start(client, ids["Quadratic Equations"])
    _probe, verdict = answer_turns(client, retry, FIRST, LONG)
    assert verdict["passed"] is True
    assert verdict["unlocked_skill_ids"] == [ids["Sequences"]]
    now = statuses(client)
    assert now["Quadratic Equations"] == "mastered" and now["Sequences"] == "available"

    # 6. Passing “Linear Functions” opens “Quadratic Functions” (it requires both), whose audit refers back to
    #    the stored misconception in its follow-up question (“Quadratic Equations” is its requires neighbour).
    function_audit = start(client, ids["Linear Functions"])
    _probe, verdict = answer_turns(client, function_audit, FIRST, LONG)
    assert verdict["unlocked_skill_ids"] == [ids["Quadratic Functions"]]

    quadratic_function = start(client, ids["Quadratic Functions"])
    (follow_up,) = answer_turns(client, quadratic_function, FIRST)
    assert follow_up == {
        "type": "probe",
        "question": f"You once thought “{SHORT_REFLECTION}”. How is this explanation different?",
    }

    # 7. The knowledge graph shows the misconception linked to the skill where it originated.
    graph = client.get("/api/graph").json()
    assert {"source": f"principle:{principle['id']}", "target": f"skill:{ids['Quadratic Equations']}", "kind": "origin", "reason": None} in graph["edges"]
    assert any(n["id"] == f"principle:{principle['id']}" and n["kind"] == "principle" for n in graph["nodes"])
    assert {e["kind"] for e in graph["edges"]} >= {"contains", "requires", "origin"}


def test_acceptance_with_a_clarified_topic(client):
    """“Statistics” is ambiguous: one question, and the answer rides along in the topic sent to generation."""
    clarify = client.post("/api/skills/clarify", json={"topic": "Statistics"}).json()
    assert clarify["needs_clarification"] is True and len(clarify["questions"]) == 1

    topic = f"Statistics\n\nQ: {clarify['questions'][0]}\nA: University-level statistics"
    generated = client.post("/api/skills/generate", json={"topic": topic, "search_syllabus": False}).json()

    assert generated["course"]["topic"] == topic
    assert generated["nodes"][0]["title"] == "Statistics"  # the first line of the topic
    assert [n["status"] for n in generated["nodes"]].count("available") == 3  # one per chapter


VOICE_EXAMPLE = "I slept about six hours last night and didn't exercise. I had ramen for lunch and I'm a bit tired."


def test_acceptance_check_in_briefing_plan_and_search(client):
    """The Analyst and Super Managing parts of the demo, offline: contract examples end to end."""
    ids = {n["slug"]: n["id"] for n in client.post("/api/skills/generate", json={"topic": "Math"}).json()["nodes"]}

    # Voice check-in of the contract example: sleep, exercise and diet filled, focus and stress asked for.
    checkin = client.post("/api/checkins", json={"transcript": VOICE_EXAMPLE}).json()
    assert checkin == {
        "checkin": {"date": local_today().isoformat(), "sleep_hours": 6, "exercised": False, "diet_note": "lunch: ramen",
                    "focus": None, "stress": None, "transcript": VOICE_EXAMPLE, "source": "voice",
                    "sleep_quality": None, "exercise_minutes": None, "weight_kg": None},
        "missing_fields": ["focus", "stress"],
    }
    # The client's one follow-up replaces the record.
    followup = client.post("/api/checkins", json={"transcript": VOICE_EXAMPLE + "\nI focused well but I was stressed."}).json()
    assert followup["missing_fields"] == [] and followup["checkin"]["stress"] == 4

    # Audits: pass the two parts of Quadratic Equations, fail it, store the misconception.
    for slug in ("discriminant", "root-coefficient"):
        _probe, verdict = answer_turns(client, start(client, ids[slug]), FIRST, LONG)
        assert verdict["passed"] is True
    failed_audit = start(client, ids["quadratic-equation"])
    answer_turns(client, failed_audit, FIRST, SHORT)
    reflection = client.post(f"/api/audits/{failed_audit}/reflection", json={"reflection": SHORT_REFLECTION}).json()

    # Briefing: fresh facts, no narrative yet; then narration, which is cached.
    before = client.get("/api/narrator/briefing").json()
    assert before["narrative"] is None and before["narrative_generated_at"] is None
    facts = before["facts"]
    assert facts["nodes"] == {"total": 12, "mastered": 2, "available": 3, "locked": 7}
    assert facts["audits"] == {"total": 3, "passed": 2, "failed": 1}
    assert facts["misconception_clusters"] == [
        {"label": SHORT_REFLECTION, "occurrences": 1, "skills": ["Quadratic Equations"], "cross_skill": False,
         "principle_ids": [reflection["id"]]}
    ]
    assert facts["condition"] == {"days": 1, "avg_sleep_hours": 6.0, "avg_stress": 4.0, "flag": "low"}

    after = client.post("/api/narrator/narrate").json()
    assert after["facts"] == facts
    assert after["narrative"] == (
        f"You've cleared 2 of 12 nodes. The misconception “{SHORT_REFLECTION}” showed up 1 time "
        "in Quadratic Equations. Average sleep over the last day: 6.0 h."
    )
    assert len(after["narrative"]) <= 400 and after["narrative_generated_at"]
    assert client.get("/api/narrator/briefing").json() == after

    # Study plan: the open node of each chapter; the condition is low, so leaves first.
    plan = client.post("/api/plan/generate").json()
    assert [s["skill_title"] for s in plan["steps"]] == ["Linear Functions", "Limits of Sequences", "Quadratic Equations"]
    assert all(s["rationale"] == "Prerequisites checked — you can take this on now." for s in plan["steps"])
    assert plan["steps"][0]["course_id"] == 1 and plan["steps"][0]["node_type"] == "concept"
    assert client.get("/api/plan/current").json() == plan

    # Search plan from the stored misconception: three results, urls from the (mock) search only.
    search = client.post(f"/api/skills/{ids['quadratic-equation']}/search-plan", json={"misconception_id": reflection["id"]})
    body = search.json()
    assert search.status_code == 200 and body["gap"] == SHORT_REFLECTION
    assert body["queries"][0].startswith("Quadratic Equations ") and len(body["items"]) == 3
    assert all(i["url"].startswith("https://example.invalid/") for i in body["items"])
