import json
import logging
from dataclasses import dataclass

from app.config import settings
from app.llm.base import LLMProvider, Message, complete_with_json_retry
from app.models import NodeType

logger = logging.getLogger(__name__)

CONCEPT_SYSTEM_PROMPT = """\
你是费曼审计官（Feynman Auditor）。用户正在尝试证明自己真正理解了知识点「{skill_title}」
（{skill_description}）。

规则：
1. 每轮只问一个问题。
2. 优先追问"为什么"，直到触及第一性原理，不要满足于表层复述。
3. 全场至少一次，故意提出一个看似合理但含有细微错误的理解，检验用户能否发现并纠正。
4. 你不教学、不给答案、不安慰。
5. 最多追问 {max_turns} 轮，之后必须给出裁决。
6. 只输出严格 JSON，二选一：
   {{"action": "probe", "question": "<下一个问题>"}}
   {{"action": "verdict", "pass": true|false, "score": 0-100, "gaps": ["<未掌握的点>"], "comment": "<裁决理由>"}}
不要输出 JSON 之外的任何文字。
"""

TASK_SYSTEM_PROMPT = """\
你是任务核验官（Task Verifier）。用户正在完成任务清单里的一步「{skill_title}」
（{skill_description}）。

这是一个具体步骤，不是需要深挖原理的知识点。规则：
1. 你只需要确认用户是不是真的知道该怎么做、或者已经做到了，不追问"为什么"，
   不故意刁难，不设埋错陷阱。
2. 最多追问 {max_turns} 轮，问清楚"具体打算怎么做/具体做了什么"就够了。
3. 裁决从宽：只要回答具体、不是空话套话（比如不是"随便弄弄""应该可以吧"这种），就应该通过。
4. 只输出严格 JSON，二选一：
   {{"action": "probe", "question": "<下一个问题>"}}
   {{"action": "verdict", "pass": true|false, "score": 0-100, "gaps": ["<不够具体的地方>"], "comment": "<裁决理由>"}}
不要输出 JSON 之外的任何文字。
"""

PRINCIPLE_INJECTION_TEMPLATE = """\

该用户过去在类似问题上暴露过以下原则，请在提问时纳入考虑：
{principle_lines}"""


@dataclass
class AuditorTurnResult:
    is_verdict: bool
    question: str | None = None
    passed: bool | None = None
    score: int | None = None
    gaps: list[str] | None = None
    comment: str | None = None


class Auditor:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def next_turn(
        self,
        skill_title: str,
        skill_description: str,
        history: list[Message],
        node_type: NodeType = NodeType.concept,
        relevant_principles: list[str] | None = None,
        max_turns: int | None = None,
    ) -> AuditorTurnResult:
        if max_turns is None:
            max_turns = settings.audit_max_turns if node_type == NodeType.concept else settings.task_max_turns
        template = CONCEPT_SYSTEM_PROMPT if node_type == NodeType.concept else TASK_SYSTEM_PROMPT
        system = template.format(
            skill_title=skill_title,
            skill_description=skill_description,
            max_turns=max_turns,
        )
        if relevant_principles:
            principle_lines = "\n".join(f"- {p}" for p in relevant_principles)
            system += PRINCIPLE_INJECTION_TEMPLATE.format(principle_lines=principle_lines)
        messages: list[Message] = [{"role": "system", "content": system}, *history]

        logger.info(
            "auditor.next_turn() calling provider=%s node_type=%s",
            self._provider.name,
            node_type.value,
        )
        raw = complete_with_json_retry(self._provider, messages)
        user_turn_count = sum(1 for m in history if m["role"] == "user")
        data = self._parse(raw, user_turn_count=user_turn_count, max_turns=max_turns)

        if data["action"] == "probe":
            return AuditorTurnResult(is_verdict=False, question=data["question"])
        return AuditorTurnResult(
            is_verdict=True,
            passed=data["pass"],
            score=data["score"],
            gaps=data.get("gaps", []),
            comment=data.get("comment", ""),
        )

    @staticmethod
    def _parse(raw: str, user_turn_count: int, max_turns: int) -> dict:
        try:
            data = json.loads(raw)
            if data.get("action") in ("probe", "verdict"):
                # 协议兜底：即使模型输出合法 JSON，若已达最大追问轮次仍执意 probe，
                # 也不能放任其无限追问——系统必须强制收敛为裁决。
                if data["action"] == "probe" and user_turn_count >= max_turns:
                    return Auditor._forced_verdict()
                return data
        except (json.JSONDecodeError, AttributeError):
            pass

        # 协议兜底：模型输出不合规时，轮次未超限则视为一次追问失败重试，
        # 超过上限强制 fail 裁决——系统必须收敛，不允许审计悬而不决。
        if user_turn_count < max_turns:
            return {"action": "probe", "question": "能再具体说说你的理解吗？"}
        return Auditor._forced_verdict()

    @staticmethod
    def _forced_verdict() -> dict:
        return {
            "action": "verdict",
            "pass": False,
            "score": 0,
            "gaps": ["审计官未能产出有效裁决"],
            "comment": "达到最大追问轮次，系统强制裁决为未通过。",
        }
