import random

from sqlmodel import Session, SQLModel, create_engine, select
from sqlmodel.pool import StaticPool

from app.models import BanditArm, EdgeKind, NodeType, SkillNode, SkillStatus
from app.services import bandit
from tests.helpers import generate, ids_by_slug, link, make_course, make_skill, pass_node


def _engine():
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    SQLModel.metadata.create_all(engine)
    return engine


def _skill(node_type: NodeType, depth: int, session: Session) -> SkillNode:
    # Chains `depth` contains-parents above a leaf so node_difficulty_score's
    # contains-edge depth counting has something real to walk.
    course = make_course(session)
    parent = None
    for i in range(depth):
        node = make_skill(session, course, f"p{i}", node_type=node_type, status=SkillStatus.locked)
        if parent is not None:
            link(session, parent, node, EdgeKind.contains)
        parent = node
    leaf = make_skill(session, course, "leaf", node_type=node_type)
    if parent is not None:
        link(session, parent, leaf, EdgeKind.contains)
    return leaf


def test_difficulty_tier_buckets_by_type_and_depth():
    engine = _engine()
    with Session(engine) as session:
        task_root = _skill(NodeType.task, depth=0, session=session)
        assert bandit.difficulty_tier(session, task_root) == "easy"

        concept_root = _skill(NodeType.concept, depth=0, session=session)
        assert bandit.difficulty_tier(session, concept_root) == "medium"

        concept_deep = _skill(NodeType.concept, depth=2, session=session)
        assert bandit.difficulty_tier(session, concept_deep) == "hard"


def test_context_bucket_with_no_audit_history_is_a_valid_bucket():
    engine = _engine()
    with Session(engine) as session:
        bucket = bandit.context_bucket(session)
        assert bucket in bandit.CONTEXT_BUCKETS


def test_update_arm_shifts_the_beta_posterior():
    engine = _engine()
    with Session(engine) as session:
        arm = bandit._get_or_create_arm(session, "mid", "easy")
        assert (arm.alpha, arm.beta) == (1.0, 1.0)

        bandit.update_arm(session, "mid", "easy", reward=True)
        session.commit()
        arm = bandit._get_or_create_arm(session, "mid", "easy")
        assert arm.alpha == 2.0
        assert arm.beta == 1.0

        bandit.update_arm(session, "mid", "easy", reward=False)
        session.commit()
        arm = bandit._get_or_create_arm(session, "mid", "easy")
        assert arm.alpha == 2.0
        assert arm.beta == 2.0


def test_choose_tier_favors_the_arm_with_a_strongly_skewed_posterior():
    engine = _engine()
    with Session(engine) as session:
        # Stack the deck: "hard" has an overwhelmingly successful posterior
        # in the "high" bucket, the other two tiers overwhelmingly failing.
        for tier in bandit.TIERS:
            arm = bandit._get_or_create_arm(session, "high", tier)
            if tier == "hard":
                arm.alpha, arm.beta = 200.0, 1.0
            else:
                arm.alpha, arm.beta = 1.0, 200.0
            session.add(arm)
        session.commit()

        random.seed(0)
        picks = [bandit.choose_tier(session, "high") for _ in range(30)]
        assert picks.count("hard") >= 28


def test_depth_is_counted_along_the_main_parent_not_the_second_parent():
    engine = _engine()
    with Session(engine) as session:
        course = make_course(session)
        root = make_skill(session, course, "root")
        mid = make_skill(session, course, "mid")
        deep = make_skill(session, course, "deep")
        both = make_skill(session, course, "both")
        link(session, root, mid, EdgeKind.contains)
        link(session, mid, deep, EdgeKind.contains)
        link(session, root, both, EdgeKind.contains, primary=True)  # depth 1 via the main parent
        link(session, deep, both, EdgeKind.contains, primary=False)  # would be depth 3 via the other

        # concept: 2.0 x (1 + 0.5 x depth): depth 1 -> 3.0 "medium", depth 3 -> 5.0 "hard"
        assert bandit.difficulty_tier(session, both) == "medium"
        assert bandit.difficulty_tier(session, deep) == "hard"
        assert bandit.difficulty_tier(session, root) == "medium"


def test_recommendation_endpoint_shape(client):
    ids = ids_by_slug(generate(client, "Math"))

    resp = client.get("/api/skills/recommendation")
    assert resp.status_code == 200
    body = resp.json()

    assert body["context_bucket"] in bandit.CONTEXT_BUCKETS
    assert body["suggested_tier"] in bandit.TIERS
    # One entry per skill node, locked ones included, keyed by the id as a string.
    assert set(body["skill_tiers"].keys()) == {str(i) for i in ids.values()}
    # The root is a depth-0 concept node -> difficulty score 2.0 -> "medium".
    assert body["skill_tiers"][str(ids["high-school-math"])] == "medium"
    # The first node to learn, a leaf at depth 3 -> 2.0 x (1 + 0.5 x 3) = 5.0 -> "hard".
    assert body["skill_tiers"][str(ids["discriminant"])] == "hard"


def test_passing_an_audit_updates_the_bandit_arm(client, client_engine):
    ids = ids_by_slug(generate(client, "Math"))

    verdict = pass_node(client, ids["discriminant"])
    assert verdict["passed"] is True

    # The discriminant is a "hard" tier node — passing it should have grown the alpha
    # (success count) on the "hard" arm for whatever bucket the user was
    # in right before this audit resolved.
    with Session(client_engine) as session:
        hard_arms = session.exec(select(BanditArm).where(BanditArm.tier == "hard")).all()
    assert len(hard_arms) >= 1
    assert any(arm.alpha > 1.0 for arm in hard_arms)


def test_failing_an_audit_grows_the_beta_of_that_arm(client, client_engine):
    from tests.helpers import fail_node

    ids = ids_by_slug(generate(client, "Math"))

    fail_node(client, ids["discriminant"])

    with Session(client_engine) as session:
        hard_arms = session.exec(select(BanditArm).where(BanditArm.tier == "hard")).all()
    assert any(arm.beta > 1.0 for arm in hard_arms)
    assert not any(arm.alpha > 1.0 for arm in hard_arms)
