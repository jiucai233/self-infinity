"""Challenger（审计复核官）行为测试。

重点不在"它能挑出问题"，而在**它会收敛**——一个能无限追杀的复核官等于永不通过，
那是这个设计唯一真正的失败模式（见 app/agents/challenger.py 的模块注释）。
"""

from unittest.mock import patch

from sqlmodel import Session

from app.agents.challenger import Challenger
from app.config import settings
from app.llm.mock import MockProvider
from app.models import AuditSession, Principle

# MockProvider 的 concept 协议：前两轮固定追问，第三轮起裁决；这段回答同时满足
# 长度与关键词要求，因此三轮之后必定是 pass —— 也就是能走到 Challenger 的前提。
GOOD_ANSWER = (
    "因为每次调用规模减半，所以是对数级；如果输入不满足有序这个前提条件，"
    "这个方法就不成立，是有明确边界的，不是任何情况下都对。"
)
# 与 GOOD_ANSWER 文本重叠足够高，会被 MockProvider._challenge 判定为"又落进去了"。
HIT_MISCONCEPTION = "以为任何情况下都成立，忽略了前提条件"
# 与 GOOD_ANSWER 完全不沾边，复核官应当维持原判。
MISS_MISCONCEPTION = "以为记住结论就等于理解了机制"


def _root_skill_id(client) -> int:
    skills = client.get("/api/skills").json()
    return next(s["id"] for s in skills if s["slug"] == "big-o")


def _seed_misconception(engine, text: str) -> None:
    with Session(engine) as session:
        audit = AuditSession(skill_id=1)
        session.add(audit)
        session.flush()
        session.add(
            Principle(
                title="历史原则",
                body="当我讲解一个方法时，我将先说清楚它的适用前提。",
                misconception=text,
                source_session_id=audit.id,
            )
        )
        session.commit()


def _run_until_verdict_or_probe(client, audit_id: int, rounds: int) -> dict:
    resp = None
    for _ in range(rounds):
        resp = client.post(f"/api/audits/{audit_id}/turns", json={"content": GOOD_ANSWER})
    return resp.json()


def test_no_history_means_no_challenge(client):
    """没有历史 misconception 时，pass 裁决直接落地——复核官无从挑战。"""
    skill_id = _root_skill_id(client)
    audit_id = client.post(f"/api/skills/{skill_id}/audits").json()["session"]["id"]

    result = _run_until_verdict_or_probe(client, audit_id, 3)

    assert result["type"] == "verdict"
    assert result["passed"] is True


def test_unrelated_misconception_upholds_verdict(client, client_engine):
    """历史 misconception 和本次讲解无关时，必须维持原判。

    这条守的是"宁可放过也不要编造挑战"——复核官不该因为库里有东西就非挑不可。
    """
    _seed_misconception(client_engine, MISS_MISCONCEPTION)
    skill_id = _root_skill_id(client)
    audit_id = client.post(f"/api/skills/{skill_id}/audits").json()["session"]["id"]

    result = _run_until_verdict_or_probe(client, audit_id, 3)

    assert result["type"] == "verdict"
    assert result["passed"] is True


def test_recurring_misconception_overturns_into_one_more_probe(client, client_engine):
    """命中历史 misconception 时，pass 不落地，转成最后一个追问。"""
    _seed_misconception(client_engine, HIT_MISCONCEPTION)
    skill_id = _root_skill_id(client)
    audit_id = client.post(f"/api/skills/{skill_id}/audits").json()["session"]["id"]

    result = _run_until_verdict_or_probe(client, audit_id, 3)

    assert result["type"] == "probe"
    assert HIT_MISCONCEPTION in result["question"]

    with Session(client_engine) as session:
        assert session.get(AuditSession, audit_id).challenged is True


def test_challenge_happens_at_most_once(client, client_engine):
    """收敛保证：被复核过一次之后，再出 pass 也不会被二次挑战。

    这是整个设计的安全阀。没有它，一个乐于挑刺的模型可以把任何审计拖成永不通过。
    """
    _seed_misconception(client_engine, HIT_MISCONCEPTION)
    skill_id = _root_skill_id(client)
    audit_id = client.post(f"/api/skills/{skill_id}/audits").json()["session"]["id"]

    challenged = _run_until_verdict_or_probe(client, audit_id, 3)
    assert challenged["type"] == "probe"

    # 用户回应挑战后，Auditor 再次给出 pass —— 这一次必须直接落地。
    final = client.post(f"/api/audits/{audit_id}/turns", json={"content": GOOD_ANSWER}).json()

    assert final["type"] == "verdict"
    assert final["passed"] is True


def test_disabled_challenger_is_a_no_op(client, client_engine, monkeypatch):
    """开关关掉时行为回到纯 Auditor —— M2 消融对比依赖这个。"""
    monkeypatch.setattr(settings, "challenger_enabled", False)
    _seed_misconception(client_engine, HIT_MISCONCEPTION)
    skill_id = _root_skill_id(client)
    audit_id = client.post(f"/api/skills/{skill_id}/audits").json()["session"]["id"]

    result = _run_until_verdict_or_probe(client, audit_id, 3)

    assert result["type"] == "verdict"
    assert result["passed"] is True


def test_challenger_failure_upholds_the_verdict(client, client_engine):
    """复核官自己炸了不能拖垮整场审计——它只能收紧裁决，不能制造新的失败模式。"""
    _seed_misconception(client_engine, HIT_MISCONCEPTION)
    skill_id = _root_skill_id(client)
    audit_id = client.post(f"/api/skills/{skill_id}/audits").json()["session"]["id"]

    with patch.object(Challenger, "review", side_effect=RuntimeError("provider down")):
        result = _run_until_verdict_or_probe(client, audit_id, 3)

    assert result["type"] == "verdict"
    assert result["passed"] is True


def test_overturn_without_a_question_is_not_a_valid_challenge():
    """声称要推翻却提不出具体问题，等同于没有挑战。"""
    result = Challenger._parse('{"action": "overturn", "question": "  ", "reason": "说不清"}')
    assert result.overturned is False


def test_malformed_challenger_output_upholds():
    result = Challenger._parse("这不是 JSON")
    assert result.overturned is False


def test_challenger_prompt_carries_both_sources():
    """挑战来源必须同时出现在 prompt 里：节点自身范围 + 该用户的历史 misconception。

    这两个来源就是搜索空间的边界，少任何一个，限定就失效了。
    """
    captured: dict[str, str] = {}

    class CapturingProvider(MockProvider):
        def complete(self, messages):
            captured["system"] = messages[0]["content"]
            return super().complete(messages)

    Challenger(CapturingProvider()).review(
        "递归",
        "函数调用自身解决子问题",
        [{"role": "user", "content": "随便说点什么"}],
        [HIT_MISCONCEPTION],
    )

    assert "函数调用自身解决子问题" in captured["system"]
    assert HIT_MISCONCEPTION in captured["system"]
