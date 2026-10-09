"""The same course asked for again, and courses inside courses found by embedding recall and a
judge (app/services/course_match.py; contract #2, #44). The embedding and the judge are stand-ins
here: the judge answers what each test says, and records what it was asked."""

import hashlib
import json

import pytest
from sqlmodel import Session, select

from app.models import AuditSession, SkillNode
from app.routers import skills
from app.agents.planner import SyllabusText
from app.services import course_generation, course_match
from tests.helpers import ScriptedProvider, generate, ids_by_slug, pass_node


def node(slug, title, parents=(), expand=False):
    return {"slug": slug, "title": title, "description": f"{title}.", "parents": list(parents),
            "node_type": "concept", "expand": expand}


def scripted(client, monkeypatch, topic, *nodes) -> dict:
    provider = ScriptedProvider(planner=json.dumps({"nodes": list(nodes), "requires": []}))
    original = skills.get_provider
    monkeypatch.setattr(skills, "get_provider", lambda agent=None: provider)
    body = generate(client, topic, search_syllabus=False)
    monkeypatch.setattr(skills, "get_provider", original)
    return body


class Judge:
    """Answers each question by name from `answers` (a value, or a function of the choices)."""

    def __init__(self, **answers):
        self.answers = answers
        self.asked: list[tuple[str, list[dict]]] = []

    def __call__(self, text, questions):
        self.asked.append((text, questions))
        out = {}
        for q in questions:
            answer = self.answers.get(q["name"], ("none", 0.9))
            if callable(answer):
                answer = answer([c["value"] for c in q["choices"]], [c.get("description", "") for c in q["choices"]])
            out[q["name"]] = answer
        return out


def by_title(choice_title, confidence=0.9):
    """Picks the choice whose description ends with `choice_title`."""

    def pick(values, descriptions):
        for v, d in zip(values, descriptions, strict=True):
            if d.split(" > ")[-1].split(" (")[0] == choice_title:
                return (v, confidence)
        return ("none", confidence)

    return pick


def recall_all(texts):
    """0.55 on a shared axis and 0.835 on the text's own: two different texts are 0.30 apart."""
    out = []
    for t in texts:
        v = [0.0] * 1000
        v[0] = 0.55
        v[1 + int(hashlib.md5(t.encode()).hexdigest(), 16) % 999] = 0.835
        out.append(v)
    return out


@pytest.fixture
def judge(monkeypatch):
    def use(**answers):
        j = Judge(**answers)
        monkeypatch.setattr(course_match, "default_decide", lambda: j)
        # Every two titles are near enough to be recalled (0.30), none the same: the judge decides.
        monkeypatch.setattr(course_match, "default_embed", lambda: recall_all)
        return j

    return use


def by_slug(body) -> dict[str, dict]:
    return {n["slug"]: n for n in body["nodes"]}


# ---------------------------------------------------------------- the same course again


def test_a_course_asked_for_again_under_another_name_is_the_one_there(client, judge):
    vision = generate(client, "Computer Vision", search_syllabus=False)
    asked = judge(same=lambda values, _: (values[0], 0.92))

    again = generate(client, "计算机视觉", search_syllabus=False)

    assert (again["course"]["id"], again["merged"]) == (vision["course"]["id"], True)
    text, (question,) = asked.asked[0]
    assert text == "Requested course: 计算机视觉" and question["name"] == "same"
    assert [c["value"] for c in question["choices"]] == ["c1", "none"]


def test_an_unsure_judge_builds_a_new_course(client, judge):
    generate(client, "Computer Vision", search_syllabus=False)
    judge(same=lambda values, _: (values[0], 0.4))

    again = generate(client, "Robot perception", search_syllabus=False)

    assert again["merged"] is False and again["course"]["id"] == 2


def test_a_course_asked_for_again_with_a_syllabus_takes_what_it_lacks(client, client_engine, judge):
    math = generate(client, "Math", search_syllabus=False)
    pass_node(client, ids_by_slug(math)["discriminant"])
    judge(same=lambda values, _: (values[0], 0.9))

    with Session(client_engine) as session:
        result = course_generation.generate_course(
            session,
            topic="高中数学",
            difficulty="standard",
            search_syllabus=True,
            planner_provider=ScriptedProvider(),
            syllabus_provider=ScriptedProvider(),
            search_provider=None,
            syllabus_text=SyllabusText(source="calc.txt", text="1. Calculus\n2. Probability"),
        )
        assert (result.merged, result.added, result.course.id) == (True, 1, 1)
        titles = [n.title for n in result.nodes]
        assert "Probability" in titles and titles.count("Calculus") == 1
        # Progress stays.
        assert session.exec(select(AuditSession)).first() is not None
        assert session.get(SkillNode, ids_by_slug(math)["discriminant"]).status == "mastered"


# ---------------------------------------------------------------- courses inside courses


def cs_course(client, monkeypatch):
    return scripted(
        client, monkeypatch, "Computer Science",
        node("cs", "Computer Science"), node("ai", "Artificial Intelligence", ["cs"], expand=True),
        node("os", "Operating Systems", ["cs"], expand=True),
    )


def test_a_course_built_after_goes_under_the_area_it_belongs_to(client, judge, monkeypatch):
    vision = generate(client, "Computer Vision", search_syllabus=False)
    judge(where=by_title("Artificial Intelligence"), how=("part", 0.9))

    cs = by_slug(cs_course(client, monkeypatch))

    # Computer Vision is a new part under AI, and it is the vision course.
    added = cs["computer-vision"]
    assert added["linked_course_id"] == vision["course"]["id"]
    edges = client.get("/api/courses/2/map").json()["edges"]
    assert any(e["from_id"] == cs["ai"]["id"] and e["to_id"] == added["id"] for e in edges)


def test_a_course_built_before_holds_the_new_one(client, judge, monkeypatch):
    cs = ids_by_slug(cs_course(client, monkeypatch))
    judge(where=by_title("Artificial Intelligence"), how=("part", 0.9))

    vision = generate(client, "Computer Vision", search_syllabus=False)

    linked = [n for n in client.get("/api/courses/1/map").json()["nodes"] if n["linked_course_id"]]
    assert [(n["title"], n["linked_course_id"]) for n in linked] == [("Computer Vision", vision["course"]["id"])]
    assert cs["ai"]


def test_a_node_that_is_the_course_gives_way_to_it_when_nothing_was_learned(client, judge, monkeypatch):
    cs = ids_by_slug(scripted(
        client, monkeypatch, "Computer Science",
        node("cs", "Computer Science"), node("vision", "Vision", ["cs"]),
        node("edges", "Edge Detection", ["vision"]), node("os", "Operating Systems", ["cs"]),
    ))
    judge(where=by_title("Vision"), how=("same", 0.9))

    vision = generate(client, "Computer Vision", search_syllabus=False)

    after = by_slug(client.get("/api/courses/1/map").json())
    assert after["vision"]["linked_course_id"] == vision["course"]["id"]
    assert "edges" not in after  # its own parts gave way to the course
    assert cs["edges"]


def test_a_node_learned_in_place_is_left_as_it_is(client, judge, monkeypatch):
    cs = ids_by_slug(scripted(
        client, monkeypatch, "Computer Science",
        node("cs", "Computer Science"), node("vision", "Vision", ["cs"]),
        node("edges", "Edge Detection", ["vision"]), node("os", "Operating Systems", ["cs"]),
    ))
    pass_node(client, cs["edges"])
    judge(where=by_title("Vision"), how=("same", 0.9))

    generate(client, "Computer Vision", search_syllabus=False)

    after = by_slug(client.get("/api/courses/1/map").json())
    assert after["vision"]["linked_course_id"] is None and "edges" in after


def test_a_failing_judge_changes_nothing(client, monkeypatch):
    def broken(text, questions):
        raise RuntimeError("down")

    monkeypatch.setattr(course_match, "default_decide", lambda: broken)
    cs_course(client, monkeypatch)

    vision = generate(client, "Computer Vision", search_syllabus=False)

    assert vision["merged"] is False
    assert not any(n["linked_course_id"] for n in client.get("/api/courses/1/map").json()["nodes"])


def test_without_a_judge_only_exact_titles_match(client, monkeypatch):
    monkeypatch.setattr(course_match, "default_decide", lambda: None)
    cs_course(client, monkeypatch)

    generate(client, "Computer Vision", search_syllabus=False)

    assert not any(n["linked_course_id"] for n in client.get("/api/courses/1/map").json()["nodes"])


# ---------------------------------------------------------------- one course: the same node twice


def test_a_title_a_plural_away_is_the_same_node():
    axes = {"markov": [1.0, 0.0, 0.0], "bandits": [0.0, 1.0, 0.0], "policy": [0.0, 0.0, 1.0]}

    def embed(texts):
        return [axes[t.lower().split()[0].split("-")[0]] for t in texts]

    near = course_match.near_titles(
        ["Markov Decision Processes", "Bandits", "policy-gradient"],
        ["Markov Decision Process", "Policy Gradient"],
        embed,
    )
    assert near == {"Markov Decision Processes", "policy-gradient"}
    # Without embeddings only the exact (normalised) title matches.
    assert course_match.near_titles(["Markov Decision Processes"], ["Markov Decision Process"], None) == set()


def test_similarities_fall_back_to_overlap_without_embeddings():
    scores = course_match.similarities("Computer Vision", ["Computer Vision Basics", "Operating Systems"], None)
    assert scores[0] > scores[1]
