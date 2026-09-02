"""Recommender：在已有节点里挑下一步。

最重要的一条是**不接受指向不存在节点的步骤** —— 模型编 skill_id 是必然会发生的，
而一个指向空气的步骤在前端就是个点了没反应的按钮。
"""

import pytest
from sqlmodel import Session, select

from app.agents.recommender import Recommender, format_context
from app.models import SkillNode, SkillStatus, StudyPlan
from app.services.profile import MisconceptionCluster
from app.models import utcnow


def test_invalid_skill_ids_are_dropped():
    steps = Recommender._parse(
        '{"steps": [{"skill_id": 1, "rationale": "有效"}, {"skill_id": 999, "rationale": "编造的"}]}',
        valid_ids={1, 2},
    )

    assert [s.skill_id for s in steps] == [1]


def test_duplicate_steps_are_dropped():
    steps = Recommender._parse(
        '{"steps": [{"skill_id": 1, "rationale": "第一次"}, {"skill_id": 1, "rationale": "又来一次"}]}',
        valid_ids={1},
    )

    assert len(steps) == 1


def test_plan_is_capped_at_five_steps():
    payload = '{"steps": [' + ",".join(f'{{"skill_id": {i}, "rationale": "r"}}' for i in range(1, 9)) + "]}"

    assert len(Recommender._parse(payload, valid_ids=set(range(1, 9)))) == 5


def test_all_invalid_ids_is_an_error_not_an_empty_plan():
    """一份全是废步骤的计划不该被当成"没什么可做"静默返回。"""
    with pytest.raises(ValueError):
        Recommender._parse('{"steps": [{"skill_id": 999, "rationale": "编造的"}]}', valid_ids={1})


def test_malformed_output_raises():
    with pytest.raises(ValueError):
        Recommender._parse("这不是 JSON", valid_ids={1})


def test_no_available_nodes_means_no_llm_call():
    """没有可选节点时直接返回空，不该浪费一次调用。"""

    class ExplodingProvider:
        name = "exploding"

        def complete(self, messages):
            raise AssertionError("不该被调用")

    assert Recommender(ExplodingProvider()).recommend([], {}, "easy", "mid", []) == []


def test_context_marks_cross_domain_clusters():
    cluster = MisconceptionCluster(
        label="以为相关性就是因果关系",
        occurrences=2,
        skills=["统计学", "投资"],
        first_seen=utcnow(),
        last_seen=utcnow(),
    )

    context = format_context("hard", "high", [cluster], health=80.0, sanity=60.0)

    assert "【跨领域】" in context
    assert "统计学、投资" in context
    assert "hard" in context


def test_generate_plan_requires_available_nodes(client, client_engine):
    with Session(client_engine) as session:
        for skill in session.exec(select(SkillNode)).all():
            skill.status = SkillStatus.locked
            session.add(skill)
        session.commit()

    assert client.post("/api/plan/generate").status_code == 400


def test_current_plan_is_null_before_anything_is_generated(client):
    resp = client.get("/api/plan/current")

    assert resp.status_code == 200
    assert resp.json() is None


def test_generate_then_read_back(client, client_engine):
    generated = client.post("/api/plan/generate")
    assert generated.status_code == 200
    body = generated.json()

    assert body["steps"]
    assert body["suggested_tier"]
    # 每一步都指向一个真实存在的节点，并带回它当下的标题。
    for step in body["steps"]:
        assert step["skill_title"]
        assert step["rationale"]

    with Session(client_engine) as session:
        assert len(session.exec(select(StudyPlan)).all()) == 1

    assert client.get("/api/plan/current").json()["id"] == body["id"]


def test_steps_pointing_at_deleted_nodes_are_skipped(client, client_engine):
    body = client.post("/api/plan/generate").json()
    removed_id = body["steps"][0]["skill_id"]

    with Session(client_engine) as session:
        session.delete(session.get(SkillNode, removed_id))
        session.commit()

    remaining = client.get("/api/plan/current").json()

    assert removed_id not in [s["skill_id"] for s in remaining["steps"]]
