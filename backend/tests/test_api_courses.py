"""课程相关接口：generate / courses / map / skills / recommendation（IT-01 ~ IT-04、IT-22、IT-23）。"""

from datetime import datetime

import pytest
from sqlmodel import Session, select

from app.models import Course, SkillEdge, SkillNode
from app.llm.mock import MockProvider
from tests.helpers import BrokenProvider, ScriptedProvider, generate, ids_by_slug, pass_node, planner_json


def test_it01_generate_saves_the_course_and_only_the_root_is_available(client, client_engine):
    body = generate(client, "Math")

    assert body["course"]["id"] == 1
    statuses = {n["slug"]: n["status"] for n in body["nodes"]}
    assert statuses.pop("high-school-math") == "available"
    assert set(statuses.values()) == {"locked"}
    assert len(body["nodes"]) == 12

    with Session(client_engine) as session:
        assert len(session.exec(select(Course)).all()) == 1
        assert len(session.exec(select(SkillNode)).all()) == 12
        assert len(session.exec(select(SkillEdge)).all()) == 15  # 12 contains + 3 requires


def test_it01_the_response_matches_the_contract_shapes(client):
    body = generate(client, "Math")

    assert set(body) == {"course", "nodes", "edges"}
    assert set(body["course"]) == {"id", "topic", "source_course", "source_url", "created_at"}
    assert body["course"]["topic"] == "Math"
    assert set(body["nodes"][0]) == {
        "id", "course_id", "slug", "title", "description", "status", "node_type", "mastery_score",
    }
    assert all(n["course_id"] == 1 and n["mastery_score"] is None and n["node_type"] == "concept" for n in body["nodes"])
    assert [n["id"] for n in body["nodes"]] == list(range(1, 13))  # in the Planner's order, ids from 1
    for edge in body["edges"]:
        assert set(edge) == {"from_id", "to_id", "kind", "is_primary", "reason"}


def test_it01_edges_carry_primary_flags_and_reasons_by_kind(client):
    ids = ids_by_slug(generate(client, "Math"))
    edges = client.get("/api/courses/1/map").json()["edges"]
    by_pair = {(e["from_id"], e["to_id"], e["kind"]): e for e in edges}

    main = by_pair[(ids["calculus"], ids["sequence-limit"], "contains")]
    other = by_pair[(ids["sequences"], ids["sequence-limit"], "contains")]
    assert (main["is_primary"], main["reason"]) == (True, None)
    assert (other["is_primary"], other["reason"]) == (False, None)

    requires = by_pair[(ids["quadratic-equation"], ids["quadratic-function"], "requires")]
    assert (requires["is_primary"], requires["reason"]) == (None, "The x-intercepts of a quadratic function are the roots of a quadratic equation.")
    assert [e["kind"] for e in edges].count("requires") == 3
    assert [e["kind"] for e in edges].count("contains") == 12


def test_it01_the_course_records_the_syllabus_it_found(client):
    course = generate(client, "Math")["course"]

    assert course["source_course"] == "High School Mathematics Curriculum (Ministry of Education)"
    assert course["source_url"] == "https://example.invalid/1"


def test_it01_search_syllabus_false_leaves_the_source_empty(client):
    course = generate(client, "Math", search_syllabus=False)["course"]

    assert course["source_course"] is None and course["source_url"] is None


def test_it01_other_topics_have_no_source(client):
    course = generate(client, "History")["course"]

    assert course["source_course"] is None and course["source_url"] is None


def test_it01_the_clarification_answers_stay_in_the_topic(client):
    topic = "Statistics\n\nQ: Do you mean high-school probability and statistics, or university-level statistics?\nA: University"

    course = generate(client, topic)["course"]

    assert course["topic"] == topic


class SpySearch:
    name = "spy"

    def __init__(self, fail: bool = False):
        self.fail = fail
        self.queries: list[str] = []

    def search(self, query, limit=5, *, pages=False):
        self.queries.append(query)
        if self.fail:
            raise RuntimeError("search is down")
        return []


def test_it01_syllabus_search_is_skipped_entirely_when_switched_off(client, monkeypatch):
    spy = SpySearch()
    monkeypatch.setattr("app.routers.skills.get_search_provider", lambda: spy)

    response = client.post("/api/skills/generate", json={"topic": "Math", "search_syllabus": False})

    assert response.status_code == 200
    assert spy.queries == []


def test_it01_a_broken_search_still_produces_a_course_without_a_source(client, monkeypatch):
    spy = SpySearch(fail=True)
    monkeypatch.setattr("app.routers.skills.get_search_provider", lambda: spy)

    response = client.post("/api/skills/generate", json={"topic": "Math"})

    assert response.status_code == 200
    assert len(spy.queries) == 3  # two syllabus phrasings and the official docs
    assert response.json()["course"]["source_course"] is None
    assert len(response.json()["nodes"]) == 12


def test_it01_a_broken_syllabus_finder_still_produces_a_course_without_a_source(client, monkeypatch):
    def provider_for(agent=None):
        return BrokenProvider() if agent == "syllabus_finder" else MockProvider()

    monkeypatch.setattr("app.routers.skills.get_provider", provider_for)

    response = client.post("/api/skills/generate", json={"topic": "Math"})

    assert response.status_code == 200
    assert response.json()["course"]["source_url"] is None
    assert len(response.json()["nodes"]) == 12


def test_it01_the_syllabus_found_is_handed_to_the_planner(client, monkeypatch):
    spy = ScriptedProvider()
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: spy)

    client.post("/api/skills/generate", json={"topic": "Math"})

    (prompt,) = spy.system_prompts("planner")
    assert "Reference outline (High School Mathematics Curriculum (Ministry of Education))" in prompt


def test_it01_a_generic_course_has_ten_nodes_and_one_root(client):
    body = generate(client, "History")

    assert [n["title"] for n in body["nodes"]][:4] == ["History", "Core Concepts", "Key Methods", "Applications"]
    assert [n["status"] for n in body["nodes"]].count("available") == 1


def test_it01_the_validation_counts_are_stored_with_the_course_settings(client, client_engine):
    generate(client, "Math", node_count=20, max_depth=5, difficulty="deep")

    with Session(client_engine) as session:
        import json

        saved = json.loads(session.get(Course, 1).settings_json)
    assert saved["node_count"] == 20 and saved["max_depth"] == 5 and saved["difficulty"] == "deep"
    assert saved["validation"]["levels"] == 4
    assert saved["validation"]["depth_exceeded"] is False
    assert set(saved["validation"]["removals"]) == {str(n) for n in range(1, 12)}


@pytest.mark.parametrize(
    "bad",
    [
        {"node_count": 3},
        {"node_count": 31},
        {"max_depth": 1},
        {"max_depth": 7},
        {"difficulty": "insane"},
        {"search_syllabus": "perhaps"},
    ],
)
def test_it02_out_of_range_settings_are_rejected(client, bad):
    assert client.post("/api/skills/generate", json={"topic": "Math", **bad}).status_code == 422


def test_it02_boundary_values_are_accepted(client):
    for settings in ({"node_count": 4, "max_depth": 2}, {"node_count": 30, "max_depth": 6, "difficulty": "intro"}):
        assert client.post("/api/skills/generate", json={"topic": "Math", **settings}).status_code == 200


@pytest.mark.parametrize("topic", ["", "   ", "\n\t"])
def test_it03_a_blank_topic_is_rejected(client, topic):
    assert client.post("/api/skills/generate", json={"topic": topic}).status_code == 422
    assert client.post("/api/skills/generate", json={}).status_code == 422


def test_it04_planner_failure_is_a_readable_502_and_saves_nothing(client, monkeypatch):
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: BrokenProvider())

    response = client.post("/api/skills/generate", json={"topic": "Math", "search_syllabus": False})

    assert response.status_code == 502
    assert response.json() == {"detail": "Course generation failed. Please try again."}
    assert client.get("/api/courses").json() == []
    assert client.get("/api/skills").json() == []


def test_it04_unparseable_planner_output_is_a_502(client, monkeypatch):
    provider = ScriptedProvider(planner="here is your course!")
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: provider)

    response = client.post("/api/skills/generate", json={"topic": "Math", "search_syllabus": False})

    assert response.status_code == 502
    assert client.get("/api/courses").json() == []


def test_it04_two_roots_twice_is_a_502_after_exactly_one_retry(client, monkeypatch):
    two_roots = planner_json([("a", []), ("b", [])])
    provider = ScriptedProvider(planner=two_roots)
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: provider)

    response = client.post("/api/skills/generate", json={"topic": "Math", "search_syllabus": False})

    assert response.status_code == 502
    assert len(provider.calls_for("planner")) == 2
    assert "found 2" in provider.calls_for("planner")[1][-1]["content"]  # the retry says what was wrong


def test_it04_two_roots_then_a_valid_course_succeeds(client, monkeypatch):
    two_roots = planner_json([("a", []), ("b", [])])
    valid = planner_json([("root", []), ("child", ["root"])])
    provider = ScriptedProvider(planner=[two_roots, valid])
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: provider)

    response = client.post("/api/skills/generate", json={"topic": "Math", "search_syllabus": False})

    assert response.status_code == 200
    assert [n["slug"] for n in response.json()["nodes"]] == ["root", "child"]


def test_the_validator_cleans_a_messy_plan_before_it_is_saved(client, monkeypatch):
    messy = planner_json(
        [("root", []), ("a", ["root", "ghost"]), ("b", ["a", "c"]), ("c", ["b"]), ("lost", ["ghost"]), ("d", ["root"])],
        [("d", "b"), ("b", "d"), ("root", "c"), ("a", "a"), ("a", "b")],
    )
    provider = ScriptedProvider(planner=messy)
    monkeypatch.setattr("app.routers.skills.get_provider", lambda agent=None: provider)

    body = client.post("/api/skills/generate", json={"topic": "Math", "search_syllabus": False}).json()
    ids = ids_by_slug(body)
    contains = {(e["from_id"], e["to_id"], e["is_primary"]) for e in body["edges"] if e["kind"] == "contains"}
    requires = [(e["from_id"], e["to_id"]) for e in body["edges"] if e["kind"] == "requires"]

    assert contains == {
        (ids["root"], ids["a"], True),
        (ids["a"], ids["b"], True),
        (ids["c"], ids["b"], False),
        (ids["root"], ids["c"], True),  # c's only parent closed a loop; it hangs off the root
        (ids["root"], ids["lost"], True),  # its only parent never existed
        (ids["root"], ids["d"], True),
    }
    # Dropped: b->d closes a loop, root->c and a->b point at an ancestor, a->a is a self edge.
    assert requires == [(ids["d"], ids["b"])]


def test_it22_graph_after_generation_has_contains_and_requires_in_the_right_direction(client):
    ids = ids_by_slug(generate(client, "Math"))

    edges = client.get("/api/graph").json()["edges"]

    assert {"source": f"skill:{ids['algebra']}", "target": f"skill:{ids['quadratic-equation']}", "kind": "contains", "reason": None} in edges
    assert {
        "source": f"skill:{ids['quadratic-equation']}",
        "target": f"skill:{ids['quadratic-function']}",
        "kind": "requires",
        "reason": "The x-intercepts of a quadratic function are the roots of a quadratic equation.",
    } in edges
    # no edge points from a child back to its parent
    assert not [e for e in edges if e["kind"] == "contains" and e["source"] == f"skill:{ids['quadratic-equation']}" and e["target"] == f"skill:{ids['algebra']}"]
    assert {e["kind"] for e in edges} == {"contains", "requires"}
    assert [e["kind"] for e in edges].count("contains") == 12


def test_it23_two_courses_with_the_same_titles_have_independent_statuses(client):
    first = generate(client, "Math")
    second = generate(client, "Math")
    assert [n["title"] for n in first["nodes"]] == [n["title"] for n in second["nodes"]]
    assert first["course"]["id"] == 1 and second["course"]["id"] == 2

    pass_node(client, first["nodes"][0]["id"])

    first_now = client.get("/api/skills", params={"course_id": 1}).json()
    second_now = client.get("/api/skills", params={"course_id": 2}).json()
    assert [n["status"] for n in first_now][:4] == ["mastered", "available", "available", "available"]
    assert [n["status"] for n in second_now][:4] == ["available", "locked", "locked", "locked"]
    assert all(n["status"] == "locked" for n in second_now[1:])
    # Same slugs in both courses is fine: slugs are unique per course only.
    assert [n["slug"] for n in first_now] == [n["slug"] for n in second_now]


# ---------------------------------------------------------------- GET /courses, /courses/{id}/map, /skills


def test_courses_are_listed_newest_first(client):
    generate(client, "Math")
    generate(client, "History")
    generate(client, "Chemistry")

    courses = client.get("/api/courses").json()

    assert [c["topic"] for c in courses] == ["Chemistry", "History", "Math"]
    assert [c["id"] for c in courses] == [3, 2, 1]
    assert set(courses[0]) == {"id", "topic", "source_course", "source_url", "created_at"}


def test_the_course_list_is_empty_on_a_fresh_database(client):
    assert client.get("/api/courses").json() == []
    assert client.get("/api/skills").json() == []
    assert client.get("/api/principles").json() == []
    assert client.get("/api/graph").json() == {"nodes": [], "edges": []}


def test_course_map_has_every_node_by_id_and_every_edge_of_both_kinds(client):
    generated = generate(client, "Math")

    body = client.get("/api/courses/1/map").json()

    assert body["course"] == generated["course"]
    assert body["nodes"] == generated["nodes"]
    assert body["edges"] == generated["edges"]
    assert [n["id"] for n in body["nodes"]] == sorted(n["id"] for n in body["nodes"])


def test_course_map_only_has_that_courses_nodes(client):
    generate(client, "Math")
    generate(client, "History")

    body = client.get("/api/courses/2/map").json()

    assert len(body["nodes"]) == 10
    assert {n["course_id"] for n in body["nodes"]} == {2}
    ids = {n["id"] for n in body["nodes"]}
    assert all(e["from_id"] in ids and e["to_id"] in ids for e in body["edges"])


def test_course_map_404s_for_an_unknown_course(client):
    response = client.get("/api/courses/99/map")

    assert response.status_code == 404
    assert response.json() == {"detail": "course not found"}


def test_skills_can_be_narrowed_to_a_course_and_are_ordered_by_id(client):
    generate(client, "Math")
    generate(client, "History")

    everything = client.get("/api/skills").json()
    only_second = client.get("/api/skills", params={"course_id": 2}).json()

    assert [n["id"] for n in everything] == list(range(1, 23))
    assert [n["id"] for n in only_second] == list(range(13, 23))
    assert client.get("/api/skills", params={"course_id": 99}).json() == []


def test_timestamps_are_timezone_aware_utc(client):
    generate(client, "Math")

    stamp = client.get("/api/courses").json()[0]["created_at"]

    parsed = datetime.fromisoformat(stamp)
    assert parsed.tzinfo is not None
    assert parsed.utcoffset().total_seconds() == 0
    assert stamp.endswith("Z") or stamp.endswith("+00:00")


# ---------------------------------------------------------------- GET /skills/recommendation


def test_recommendation_has_a_tier_for_every_skill_node(client):
    generate(client, "Math")
    generate(client, "History")

    body = client.get("/api/skills/recommendation").json()

    assert set(body) == {"context_bucket", "suggested_tier", "skill_tiers"}
    assert body["context_bucket"] in ("low", "mid", "high")
    assert body["suggested_tier"] in ("easy", "medium", "hard")
    assert set(body["skill_tiers"]) == {str(i) for i in range(1, 23)}  # string keys, locked nodes included
    assert set(body["skill_tiers"].values()) <= {"easy", "medium", "hard"}


def test_recommendation_tiers_follow_contains_depth(client):
    ids = ids_by_slug(generate(client, "Math"))

    tiers = client.get("/api/skills/recommendation").json()["skill_tiers"]

    # concept: 2.0 x (1 + 0.5 x depth): depth 0 -> 2.0 medium, depth 1 -> 3.0 medium, depth 2 -> 4.0 hard
    assert tiers[str(ids["high-school-math"])] == "medium"
    assert tiers[str(ids["algebra"])] == "medium"
    assert tiers[str(ids["quadratic-equation"])] == "hard"
    assert tiers[str(ids["discriminant"])] == "hard"
    # sequence-limit sits under calculus (its main parent) at depth 2, though it is also under sequences (depth 2)
    assert tiers[str(ids["sequence-limit"])] == "hard"


def test_recommendation_on_an_empty_database(client):
    body = client.get("/api/skills/recommendation").json()

    assert body["skill_tiers"] == {}
    assert body["suggested_tier"] in ("easy", "medium", "hard")
