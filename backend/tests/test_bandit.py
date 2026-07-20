import random

from sqlmodel import Session, SQLModel, create_engine, select
from sqlmodel.pool import StaticPool

from app.models import BanditArm, NodeType, SkillNode, SkillStatus
from app.services import bandit


def _engine():
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    SQLModel.metadata.create_all(engine)
    return engine


def _skill(node_type: NodeType, depth: int, session: Session) -> SkillNode:
    # Chains `depth` locked parents above a leaf so node_difficulty_score's
    # parent_id-hop counting has something real to walk.
    parent_id = None
    for _ in range(depth):
        parent = SkillNode(
            slug=f"p-{random.random()}",
            title="parent",
            description="",
            parent_id=parent_id,
            status=SkillStatus.locked,
            node_type=node_type,
        )
        session.add(parent)
        session.flush()
        parent_id = parent.id
    leaf = SkillNode(
        slug=f"leaf-{random.random()}",
        title="leaf",
        description="",
        parent_id=parent_id,
        status=SkillStatus.available,
        node_type=node_type,
    )
    session.add(leaf)
    session.flush()
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


def test_recommendation_endpoint_shape(client):
    resp = client.get("/api/skills/recommendation")
    assert resp.status_code == 200
    body = resp.json()

    assert body["context_bucket"] in bandit.CONTEXT_BUCKETS
    assert body["suggested_tier"] in bandit.TIERS

    skills = client.get("/api/skills").json()
    available_ids = {s["id"] for s in skills if s["status"] == "available"}
    assert set(body["skill_tiers"].keys()) == {str(i) for i in available_ids}

    # Seeded root ("Big-O 记号") is a depth-0 concept node -> difficulty
    # score 2.0 -> "medium" per difficulty_tier's thresholds.
    root_id = next(s["id"] for s in skills if s["slug"] == "big-o")
    assert body["skill_tiers"][str(root_id)] == "medium"


def test_passing_an_audit_updates_the_bandit_arm(client, client_engine):
    skills = client.get("/api/skills").json()
    root_id = next(s["id"] for s in skills if s["slug"] == "big-o")

    good_answer = (
        "因为每次调用规模减半，所以是对数级；如果输入不满足有序这个前提条件，"
        "这个方法就不成立，是有明确边界的，不是任何情况下都对。"
    )
    start = client.post(f"/api/skills/{root_id}/audits", json={"mode": "day"})
    audit_id = start.json()["session"]["id"]
    verdict = None
    for _ in range(6):
        result = client.post(f"/api/audits/{audit_id}/turns", json={"content": good_answer}).json()
        if result["type"] != "probe":
            verdict = result
            break
    assert verdict is not None
    assert verdict["passed"] is True

    # Root is a "medium" tier node — passing it should have grown the alpha
    # (success count) on the "medium" arm for whatever bucket the user was
    # in right before this audit resolved.
    with Session(client_engine) as session:
        medium_arms = session.exec(select(BanditArm).where(BanditArm.tier == "medium")).all()
    assert len(medium_arms) >= 1
    assert any(arm.alpha > 1.0 for arm in medium_arms)
