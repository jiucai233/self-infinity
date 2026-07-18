"""回归测试：即使 LLM 顽固地返回合法 JSON 的 probe 动作，审计也必须在 max_turns 强制收敛为裁决。"""

from app.agents.auditor import Auditor
from app.llm.base import Message
from app.models import NodeType


class StubbornProbeProvider:
    """无论轮次多少，永远返回一个格式合法的 probe。用来暴露"合法 JSON 但拒不裁决"的收敛漏洞。"""

    name = "stubborn-probe"

    def complete(self, messages: list[Message]) -> str:
        return '{"action": "probe", "question": "还是不够具体，再说说？"}'


def _run_until_verdict(node_type: NodeType, max_turns: int):
    auditor = Auditor(StubbornProbeProvider())
    history: list[Message] = []

    for turn in range(max_turns + 3):
        result = auditor.next_turn(
            skill_title="测试技能",
            skill_description="用于收敛测试",
            history=history,
            node_type=node_type,
        )
        user_turn_count = sum(1 for m in history if m["role"] == "user")

        if result.is_verdict:
            return result, user_turn_count

        # 模拟用户又回答了一轮，继续追问
        history.append({"role": "assistant", "content": result.question or ""})
        history.append({"role": "user", "content": "还是原来那个答案。"})

    raise AssertionError(f"审计在 {max_turns + 3} 轮内未能收敛为裁决")


def test_concept_audit_forces_verdict_when_llm_keeps_probing():
    from app.config import settings

    result, user_turn_count = _run_until_verdict(NodeType.concept, settings.audit_max_turns)

    assert result.is_verdict is True
    assert result.passed is False
    assert user_turn_count >= settings.audit_max_turns
    assert result.gaps


def test_task_audit_forces_verdict_when_llm_keeps_probing():
    from app.config import settings

    result, user_turn_count = _run_until_verdict(NodeType.task, settings.task_max_turns)

    assert result.is_verdict is True
    assert result.passed is False
    assert user_turn_count >= settings.task_max_turns
    assert result.gaps
