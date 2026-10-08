"""奖励：通过审计后记录 RewardEvent；失败没有奖励。（难度按 contains 边的深度算。）"""

from sqlmodel import Session, SQLModel, create_engine, select
from sqlmodel.pool import StaticPool

from app.models import EdgeKind, NodeType, RewardEvent, SkillStatus
from app.services.incentive import BASE_REWARD, LEVEL_MULTIPLIER_BASE, compute_reward, node_difficulty_score
from tests.helpers import fail_node, generate, ids_by_slug, link, make_course, make_skill, pass_node


def _engine():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    SQLModel.metadata.create_all(engine)
    return engine


def test_passing_audit_creates_reward_event(client, client_engine):
    ids = ids_by_slug(generate(client, "Math"))

    verdict = pass_node(client, ids["discriminant"])

    assert verdict["reward_amount"] == 55  # round(10 x 2.0 x (1 + 0.5 x depth 3) x 1.1)
    assert verdict["reward_multiplier"] == 1.1
    with Session(client_engine) as session:
        (event,) = session.exec(select(RewardEvent)).all()
        assert (event.amount, event.multiplier) == (55, 1.1)


def test_failing_audit_creates_no_reward_event(client, client_engine):
    ids = ids_by_slug(generate(client, "Math"))

    fail_node(client, ids["discriminant"])

    with Session(client_engine) as session:
        assert session.exec(select(RewardEvent)).all() == []


def test_deeper_nodes_earn_more():
    engine = _engine()
    with Session(engine) as session:
        course = make_course(session)
        root = make_skill(session, course, "root")
        child = make_skill(session, course, "child", status=SkillStatus.locked)
        grandchild = make_skill(session, course, "grandchild", status=SkillStatus.locked)
        link(session, root, child, EdgeKind.contains)
        link(session, child, grandchild, EdgeKind.contains)

        scores = [node_difficulty_score(session, n) for n in (root, child, grandchild)]

        assert scores == [2.0, 3.0, 4.0]  # concept: 2 x (1 + 0.5 x depth)


def test_task_nodes_are_worth_half_a_concept_at_the_same_depth():
    engine = _engine()
    with Session(engine) as session:
        course = make_course(session)
        concept = make_skill(session, course, "concept", node_type=NodeType.concept)
        task = make_skill(session, course, "task", node_type=NodeType.task)

        assert node_difficulty_score(session, concept) == 2.0
        assert node_difficulty_score(session, task) == 1.0


def test_the_level_multiplier_grows_every_five_mastered_nodes():
    engine = _engine()
    with Session(engine) as session:
        course = make_course(session)
        nodes = [make_skill(session, course, f"n{i}", node_type=NodeType.task) for i in range(6)]
        for node in nodes[:4]:
            node.status = SkillStatus.mastered
            session.add(node)
        session.commit()

        amount, multiplier = compute_reward(session, nodes[0])
        assert multiplier == LEVEL_MULTIPLIER_BASE**1  # 4 mastered -> level 1

        nodes[4].status = SkillStatus.mastered  # the fifth bumps the level
        session.add(nodes[4])
        session.commit()
        amount_after, multiplier_after = compute_reward(session, nodes[0])

        assert multiplier_after == LEVEL_MULTIPLIER_BASE**2
        assert amount == round(BASE_REWARD * 1.0 * multiplier)
        assert amount_after == round(BASE_REWARD * 1.0 * multiplier_after)
