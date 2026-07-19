from unittest.mock import patch

from sqlmodel import Session, SQLModel, create_engine
from sqlmodel.pool import StaticPool

from app.agents.retrieval import find_relevant_principles
from app.llm.base import Message
from app.llm.mock import MockProvider
from app.models import Principle, SkillNode


def _make_session() -> Session:
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    SQLModel.metadata.create_all(engine)
    return Session(engine)


def test_find_relevant_principles_matches_by_keyword_overlap():
    session = _make_session()

    skill = SkillNode(slug="recursion", title="递归", description="函数调用自身解决子问题")
    session.add(skill)
    session.flush()

    matching = Principle(
        title="递归先想终止条件",
        body="当我写递归函数时，我将先确认终止条件，再写递推关系。",
        source_session_id=1,
    )
    unrelated_a = Principle(
        title="部署前先备份",
        body="当我上线新版本时，我将先做好数据库备份，再执行迁移脚本。",
        source_session_id=1,
    )
    unrelated_b = Principle(
        title="沟通先讲结论",
        body="当我汇报进度时，我将先说结论，再补充细节和风险。",
        source_session_id=1,
    )
    session.add_all([matching, unrelated_a, unrelated_b])
    session.commit()

    results = find_relevant_principles(session, skill)

    assert matching in results
    assert unrelated_a not in results
    assert unrelated_b not in results


def test_find_relevant_principles_returns_empty_when_nothing_relevant():
    session = _make_session()

    skill = SkillNode(slug="graph-bfs", title="图的 BFS", description="层序遍历与最短路径")
    session.add(skill)
    session.flush()

    unrelated = Principle(
        title="部署前先备份",
        body="当我上线新版本时，我将先做好数据库备份，再执行迁移脚本。",
        source_session_id=1,
    )
    session.add(unrelated)
    session.commit()

    assert find_relevant_principles(session, skill) == []


def test_find_relevant_principles_respects_limit_and_ranking():
    session = _make_session()

    skill = SkillNode(slug="recursion", title="递归", description="函数调用自身解决子问题")
    session.add(skill)
    session.flush()

    strong_match = Principle(
        title="递归函数子问题",
        body="当我写递归函数时，我将先想清楚子问题怎么分解，再动手写代码。",
        source_session_id=1,
    )
    weak_match = Principle(
        title="写代码先测试",
        body="当我写函数时，我将先写好测试用例，再开始实现。",
        source_session_id=1,
    )
    session.add_all([strong_match, weak_match])
    session.commit()

    results = find_relevant_principles(session, skill, limit=1)

    assert results == [strong_match]


class _CapturingProvider:
    """包一层 MockProvider，记录每次调用真正收到的 messages，方便断言 system prompt 内容。

    审计逻辑本身仍然由 MockProvider 的既有脚本驱动，这里只做透传 + 记录，
    不改变任何 pass/fail 行为。
    """

    name = "mock"

    def __init__(self) -> None:
        self._inner = MockProvider()
        self.calls: list[list[Message]] = []

    def complete(self, messages: list[Message]) -> str:
        self.calls.append(messages)
        return self._inner.complete(messages)

    def audit_system_prompts(self) -> list[str]:
        prompts = []
        for messages in self.calls:
            system = next((m["content"] for m in messages if m["role"] == "system"), "")
            if "正在听用户给你讲解" in system or "任务核验官" in system:
                prompts.append(system)
        return prompts


def _generate_root_skill(client, topic: str) -> dict:
    resp = client.post("/api/skills/generate", json={"topic": topic})
    assert resp.status_code == 200
    nodes = resp.json()
    return next(n for n in nodes if n["parent_id"] is None)


def _fail_audit_and_reflect(client, skill_id: int, reflection: str) -> None:
    start = client.post(f"/api/skills/{skill_id}/audits")
    audit_id = start.json()["session"]["id"]

    weak_answer = "不知道，反正大概就是这样吧。"
    client.post(f"/api/audits/{audit_id}/turns", json={"content": weak_answer})
    client.post(f"/api/audits/{audit_id}/turns", json={"content": weak_answer})
    verdict = client.post(f"/api/audits/{audit_id}/turns", json={"content": weak_answer}).json()
    assert verdict["passed"] is False

    reflection_resp = client.post(f"/api/audits/{audit_id}/reflection", json={"reflection": reflection})
    assert reflection_resp.status_code == 200


def test_submit_turn_injects_relevant_principle_into_system_prompt(client):
    # 先在“递归专题”上审计失败并反思，蒸馏出一条包含“递归”字样的原则。
    skill_a = _generate_root_skill(client, "递归专题")
    _fail_audit_and_reflect(client, skill_a["id"], "下次做递归题先想清楚终止条件再动手写代码。")

    principles = client.get("/api/principles").json()
    assert len(principles) == 1
    principle_text_fragment = principles[0]["body"][:10]

    # 再对一个关键词高度相关（同样包含“递归”）的新技能点提交回答，system prompt 里应该
    # 出现刚才蒸馏出的原则内容。
    skill_b = _generate_root_skill(client, "递归进阶练习")
    start_b = client.post(f"/api/skills/{skill_b['id']}/audits")
    audit_b_id = start_b.json()["session"]["id"]

    provider = _CapturingProvider()
    with patch("app.routers.audits.get_provider", return_value=provider):
        client.post(f"/api/audits/{audit_b_id}/turns", json={"content": "我打算先写终止条件"})

    audit_prompts = provider.audit_system_prompts()
    assert audit_prompts
    assert any(principle_text_fragment in prompt for prompt in audit_prompts)
    assert any("该用户过去在类似问题上暴露过以下原则" in prompt for prompt in audit_prompts)


def test_submit_turn_omits_principle_section_when_nothing_relevant(client):
    # 同样先制造一条“递归”相关的原则……
    skill_a = _generate_root_skill(client, "递归专题")
    _fail_audit_and_reflect(client, skill_a["id"], "下次做递归题先想清楚终止条件再动手写代码。")

    principles = client.get("/api/principles").json()
    assert len(principles) == 1

    # ……但这次对一个完全不相关的技能点提交回答，system prompt 里不应该出现任何原则内容，
    # 也不应该出现空的注入小节。
    skill_c = _generate_root_skill(client, "网络安全基础")
    start_c = client.post(f"/api/skills/{skill_c['id']}/audits")
    audit_c_id = start_c.json()["session"]["id"]

    provider = _CapturingProvider()
    with patch("app.routers.audits.get_provider", return_value=provider):
        client.post(f"/api/audits/{audit_c_id}/turns", json={"content": "我打算先做资产梳理"})

    audit_prompts = provider.audit_system_prompts()
    assert audit_prompts
    for prompt in audit_prompts:
        assert "该用户过去在类似问题上暴露过以下原则" not in prompt
