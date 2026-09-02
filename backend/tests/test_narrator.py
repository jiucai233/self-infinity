"""Narrator：画像端点与叙述端点。

关键分界:GET /briefing 永远不花钱、永远返回最新画像;POST /narrate 是唯一会调 LLM 的
地方。测试守住这条线,否则首屏会变成每次打开都烧一次额度。
"""

from unittest.mock import patch

import pytest
from sqlmodel import Session, SQLModel, create_engine, select
from sqlmodel.pool import StaticPool

from app.agents.narrator import Narrator, format_facts
from app.llm.mock import MockProvider
from app.models import AuditSession, AuditStatus, NarratorBriefing, Principle, SkillNode, SkillStatus
from app.services.profile import build_profile

A = "以为相关性就是因果关系"
B = "以为相关性就是因果，忽略了混淆变量"


def _seed_cross_domain_failures(engine) -> None:
    """在两个不相关技能点上各栽一次同一个心智模型 —— 跨领域复发的最小构造。"""
    with Session(engine) as session:
        for title, misconception in (("统计学", A), ("投资", B)):
            skill = SkillNode(
                slug=title, title=title, description=f"{title}的说明", status=SkillStatus.available
            )
            session.add(skill)
            session.flush()
            audit = AuditSession(skill_id=skill.id, status=AuditStatus.failed)
            session.add(audit)
            session.flush()
            session.add(
                Principle(
                    title="原则",
                    body="当我再遇到时，我将…",
                    misconception=misconception,
                    source_session_id=audit.id,
                )
            )
        session.commit()


def test_briefing_works_on_an_empty_database(client):
    resp = client.get("/api/narrator/briefing")

    assert resp.status_code == 200
    body = resp.json()
    assert body["clusters"] == []
    assert body["narrative"] is None
    assert body["pass_rate"] is None


def test_briefing_does_not_call_the_llm(client):
    """首屏不能花钱。"""
    with patch.object(Narrator, "narrate", side_effect=AssertionError("briefing 不该调用 LLM")):
        assert client.get("/api/narrator/briefing").status_code == 200


def test_briefing_surfaces_cross_domain_clusters(client, client_engine):
    _seed_cross_domain_failures(client_engine)

    body = client.get("/api/narrator/briefing").json()

    assert len(body["clusters"]) == 1
    cluster = body["clusters"][0]
    assert cluster["cross_domain"] is True
    assert cluster["occurrences"] == 2
    assert set(cluster["skills"]) == {"统计学", "投资"}


def test_narrate_persists_and_is_served_back_by_briefing(client, client_engine):
    _seed_cross_domain_failures(client_engine)

    narrated = client.post("/api/narrator/narrate").json()
    assert narrated["narrative"]

    with Session(client_engine) as session:
        assert len(session.exec(select(NarratorBriefing)).all()) == 1

    # 之后的 briefing 拿到的是这份缓存，而不是重新生成。
    reread = client.get("/api/narrator/briefing").json()
    assert reread["narrative"] == narrated["narrative"]
    assert reread["narrative_generated_at"] is not None


def test_narrative_names_the_domains_it_crosses(client, client_engine):
    """跨领域必须点名具体哪几个领域 —— 这是这段叙述唯一不可替代的价值。"""
    _seed_cross_domain_failures(client_engine)

    narrative = client.post("/api/narrator/narrate").json()["narrative"]

    assert "统计学" in narrative
    assert "投资" in narrative


def test_narrate_returns_502_when_the_provider_fails(client):
    with patch.object(Narrator, "narrate", side_effect=RuntimeError("provider down")):
        assert client.post("/api/narrator/narrate").status_code == 502


def test_facts_carry_the_cross_domain_marker():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    SQLModel.metadata.create_all(engine)
    _seed_cross_domain_failures(engine)

    with Session(engine) as session:
        facts = format_facts(build_profile(session))

    assert "【跨领域】" in facts
    assert "统计学" in facts and "投资" in facts


def test_facts_say_so_when_there_is_nothing_to_report():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        facts = format_facts(build_profile(session))

    assert "暂无记录" in facts


def test_blank_narrative_is_rejected():
    class BlankProvider(MockProvider):
        def complete(self, messages):
            return '{"narrative": "   "}'

    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        profile = build_profile(session)

    with pytest.raises(ValueError):
        Narrator(BlankProvider()).narrate(profile)
