"""审计复核官（Challenger）：唯一一个目标函数与 Auditor 对立的角色。

Auditor 的目标是判定用户是否掌握；Challenger 的目标是**推翻通过裁决**。裁决因此
不再是单方输出，而是两个对立收益的角色交互后的结果——这是本系统里唯一构成博弈、
因而可以称为 multi-agent 的地方（白皮书 §2 口径表：角色之间没有独立目标函数就不
构成 MAS，其余角色仍然只是多角色 LLM 编排）。

引入动机是工程性的：M2 校准跑分显示 task 协议在多轮追问场景下放水率约 16.7%，
超过 ≤10% 的验收门槛，而准确率已达标——也就是说问题出在"该拒的没拒"，正好是一个
对立角色能纠正的偏差类型。

# 为什么需要限定挑战来源

放开让 LLM"找问题"必然导致永不通过：任何解释都能被追问到崩，模型极擅长挑刺。所以
Challenger 的搜索空间被硬性限制在两个来源：

1. 该技能节点自身声明的范围（skill.description）；
2. 该用户历史上诊断出的 misconception。

第 2 条同时解决了另一个问题：misconception 库此前只是"失败之后的记录"，除了在反思
提交时弹一条"这不是第一次了"之外不参与任何决策。挂到这里之后，记忆系统第一次真正
进入审计回路——挑战不是泛泛质疑，而是针对这个用户自己的历史弱点。

# 收敛保证

每个审计会话最多被挑战一次（AuditSession.challenged）。挑战不直接翻转裁决，而是变成
最后一个追问：用户有机会回应，再由 Auditor 出最终裁决，届时 challenged 已为真，不会
再次触发。因此 Challenger 最多让一次审计多出一轮，不存在无限追杀。
"""

import json
import logging
from dataclasses import dataclass

from app.llm.base import LLMProvider, Message, complete_with_json_retry

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """\
你是审计复核官（Challenger）。审计官刚刚判定用户通过了对「{skill_title}」的讲解，
你的职责是尝试推翻这个通过裁决。

你只有一次机会，并且只能从以下两个来源发起挑战：

(a) 该知识点自身声明的范围：{skill_description}
    ——用户的讲解是否漏掉了这个范围内某个必须覆盖的情形？

(b) 该用户历史上被诊断出的错误心智模型：
{misconception_lines}
    ——用户这次的讲解里，是否又落进了其中某一条？

严格禁止：
1. 不得引入上述两个来源之外的知识来挑刺。你不是在考核用户的知识广度，
   也不是在展示你自己知道多少。
2. 不得因为"讲得还不够深入""可以再详细一点"这类程度问题发起挑战。只有实质性的
   遗漏、或者历史错误心智模型的复发，才构成有效挑战。
3. 如果这两个来源里都找不到实质问题，必须维持原判——维持原判是正常结果，不是失职。
   宁可放过一个可疑的，也不要为了显得尽责而编造一个挑战。

只输出严格 JSON，二选一：
{{"action": "uphold", "reason": "<维持原判的理由>"}}
{{"action": "overturn", "question": "<针对该遗漏或复发提出的一个具体问题>", "reason": "<挑战依据>"}}
不要输出 JSON 之外的任何文字。
"""

_NO_MISCONCEPTIONS = "    （该用户暂无历史记录，本次只能依据来源 (a) 判断）"


@dataclass
class ChallengeResult:
    overturned: bool
    question: str | None = None
    reason: str = ""


class Challenger:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def review(
        self,
        skill_title: str,
        skill_description: str,
        history: list[Message],
        misconceptions: list[str],
    ) -> ChallengeResult:
        """复核一个 pass 裁决。返回 overturned=False 表示维持原判。

        任何异常都由调用方兜底为"维持原判"——Challenger 是对既有裁决的加强，
        它自己出问题不应该让整场审计失败。
        """
        if misconceptions:
            misconception_lines = "\n".join(f"    - {m}" for m in misconceptions)
        else:
            misconception_lines = _NO_MISCONCEPTIONS

        system = SYSTEM_PROMPT.format(
            skill_title=skill_title,
            skill_description=skill_description,
            misconception_lines=misconception_lines,
        )
        messages: list[Message] = [{"role": "system", "content": system}, *history]

        logger.info("challenger.review() calling provider=%s", self._provider.name)
        raw = complete_with_json_retry(self._provider, messages)
        return self._parse(raw)

    @staticmethod
    def _parse(raw: str) -> ChallengeResult:
        try:
            data = json.loads(raw)
        except (json.JSONDecodeError, TypeError):
            # 复核官自己不合规时维持原判：它的作用是收紧裁决，不是制造新的失败模式。
            logger.warning("challenger returned non-JSON, upholding verdict")
            return ChallengeResult(overturned=False, reason="复核官未产出有效结论，维持原判。")

        if data.get("action") != "overturn":
            return ChallengeResult(overturned=False, reason=data.get("reason", ""))

        question = (data.get("question") or "").strip()
        if not question:
            # 声称要推翻却提不出具体问题，等同于没有有效挑战。
            logger.warning("challenger overturned without a question, upholding verdict")
            return ChallengeResult(overturned=False, reason="复核官未能提出具体质疑，维持原判。")

        return ChallengeResult(overturned=True, question=question, reason=data.get("reason", ""))
