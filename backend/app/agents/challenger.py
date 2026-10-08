"""Challenger：只看 pass 的第二考官，唯一一个目标函数与 Auditor 对立的角色。

Auditor 的目标是判定用户是否掌握；Challenger 的目标是**推翻通过裁决**。裁决因此不再是
单方输出，而是两个对立收益的角色交互后的结果。

存在的理由：LLM 考官倾向于放过讲得流畅的解释（R-01），而同一次调用里既出题又评分，
容易和自己的提问保持一致。第二次调用、相反的目标，是对一个通过裁决的独立检验。它只管
通过，因为误放（false pass）才是代价高的错误——它会在薄弱的基础上解锁后面的节点；误拒
只是多花一次尝试。

# 为什么需要限定挑战来源

放开让 LLM"找问题"必然导致永不通过：任何解释都能被追问到崩，模型极擅长挑刺。所以
Challenger 的搜索空间被硬性限制在两个来源：

1. 该节点自身声明的范围（description 里点名的情形）；
2. 该用户历史上诊断出的 misconception。

第 2 条让 misconception 库第一次真正进入审计回路——挑战不是泛泛质疑，而是针对这个
用户自己的历史弱点。

# 收敛保证

每个审计会话最多被挑战一次（AuditSession.challenged）。挑战不直接翻转裁决，而是变成
最后一个追问：用户有机会回应，再由 Auditor 出最终裁决，届时 challenged 已为真，不会
再次触发。因此 Challenger 最多让一次审计多出一轮，不存在无限追杀。
"""

import json
import logging
from dataclasses import dataclass

from app.llm.base import LLMProvider, Message, agent_tag, complete_with_json_retry

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = (
    agent_tag("challenger")
    + """
Another examiner has just passed the user on this node. Your job is to
look for a reason the pass should not stand.

Node: {title}
Covers: {description}
The user's recent misconceptions:
<misconceptions>
{misconceptions}
</misconceptions>
The dialogue follows as chat messages.

You may challenge on only two grounds:
1. A case named in "Covers" that the explanation missed or got wrong.
2. The explanation repeats one of the recent misconceptions above.

Rules:
- Use no other knowledge. Never challenge because the answer
  "could be more detailed".
- If you challenge, write one question the user can answer in a few
  sentences. You are not failing the user; the question lets them show
  they understand.
- Never give the answer: the question must not contain or hint at it.
- Upholding is a normal result. When in doubt, uphold. Never invent a
  challenge.
- Write the question in English.

Output only JSON, one of:
{{"action": "uphold", "reason": "..."}}
{{"action": "overturn", "question": "...", "reason": "ground 1 or 2, and what was missed"}}
"""
)


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

        解析层面的任何问题都退化为维持原判；provider 抛出的异常由调用方兜底成同样的
        结果——Challenger 是对既有裁决的加强，它自己出问题不应该让整场审计失败。
        """
        lines = "\n".join(f"- {' '.join(m.split())}" for m in misconceptions if m and m.strip())
        system = SYSTEM_PROMPT.format(
            title=skill_title,
            description=skill_description,
            misconceptions=lines or "none",
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
            logger.warning("challenger returned non-JSON, upholding verdict")
            return ChallengeResult(overturned=False, reason="challenger output was not valid JSON")
        if not isinstance(data, dict):
            return ChallengeResult(overturned=False, reason="challenger output was not a JSON object")

        reason = str(data.get("reason") or "")
        if data.get("action") != "overturn":
            return ChallengeResult(overturned=False, reason=reason)

        question = str(data.get("question") or "").strip()
        if not question:
            # 声称要推翻却提不出具体问题，等同于没有有效挑战。
            logger.warning("challenger overturned without a question, upholding verdict")
            return ChallengeResult(overturned=False, reason="overturn without a question")

        return ChallengeResult(overturned=True, question=question, reason=reason)
