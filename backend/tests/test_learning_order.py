"""The learning order laid over a course's tree: parts before what contains them, prerequisites
first, the planner's order otherwise. Each chapter (a child of the root) has one open node, so
the player picks the chapter; the root comes last."""

from sqlmodel import Session

from app.models import SkillNode, SkillStatus
from app.services.tree import course_order, open_every_course
from tests.helpers import MATH_ORDER, generate, ids_by_slug, pass_node


def statuses(client) -> dict[str, str]:
    return {n["slug"]: n["status"] for n in client.get("/api/skills").json()}


def test_the_math_course_is_learned_bottom_up_in_outline_order(client, client_engine):
    course = generate(client, "Math")

    with Session(client_engine) as session:
        assert [n.slug for n in course_order(session, course["course"]["id"])] == MATH_ORDER
    # One open node per chapter: Algebra, Functions, Calculus.
    assert [s for s, status in statuses(client).items() if status == "available"] == [
        "discriminant", "linear-function", "sequence-limit",
    ]


def test_passing_the_open_node_opens_the_next_one_of_its_chapter_only(client):
    ids = ids_by_slug(generate(client, "Math"))

    for slug, opened in [("discriminant", "root-coefficient"), ("root-coefficient", "quadratic-equation"),
                         ("quadratic-equation", "sequences"), ("linear-function", "quadratic-function")]:
        assert pass_node(client, ids[slug])["unlocked_skill_ids"] == [ids[opened]]

    now = statuses(client)
    assert sorted(s for s in MATH_ORDER if now[s] == "available") == ["quadratic-function", "sequence-limit", "sequences"]
    # A mastered node can be retaken; it opens nothing new.
    assert pass_node(client, ids["discriminant"])["unlocked_skill_ids"] == []


def test_a_finished_chapter_opens_nothing_in_the_others(client):
    ids = ids_by_slug(generate(client, "Math"))
    for slug in ["linear-function", "quadratic-function"]:
        pass_node(client, ids[slug])

    assert pass_node(client, ids["functions"])["unlocked_skill_ids"] == []
    assert statuses(client)["high-school-math"] == "locked"


def test_the_root_opens_last(client):
    ids = ids_by_slug(generate(client, "Math"))
    for slug in MATH_ORDER[:-1]:
        pass_node(client, ids[slug])

    assert statuses(client)["high-school-math"] == "available"
    assert pass_node(client, ids["high-school-math"])["unlocked_skill_ids"] == []


def test_each_course_has_its_own_open_node(client):
    generate(client, "Math")
    cooking = ids_by_slug(generate(client, "Cooking"))

    open_ = [n for n in client.get("/api/skills").json() if n["status"] == "available"]
    assert sorted(n["slug"] for n in open_) == [
        "applications-1", "core-concepts-1", "discriminant", "linear-function", "main-methods-1", "sequence-limit",
    ]
    assert cooking["root"] not in {n["id"] for n in open_}


def test_a_course_that_opened_at_the_root_is_moved_over(client, client_engine):
    ids = ids_by_slug(generate(client, "Math"))
    with Session(client_engine) as session:
        for node_id, status in [(ids["high-school-math"], SkillStatus.available), (ids["discriminant"], SkillStatus.locked)]:
            node = session.get(SkillNode, node_id)
            node.status = status
            session.add(node)
        session.commit()

        assert open_every_course(session) == 2
        session.commit()
        assert open_every_course(session) == 0  # idempotent
    assert [s for s, status in statuses(client).items() if status == "available"] == [
        "discriminant", "linear-function", "sequence-limit",
    ]
