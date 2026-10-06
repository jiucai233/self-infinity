import json
import logging
from dataclasses import dataclass

from app.llm.base import LLMProvider, Message, agent_tag, complete_with_json_retry

logger = logging.getLogger(__name__)

MAX_QUESTIONS = 2

SYSTEM_PROMPT = (
    agent_tag("clarifier")
    + """
You help set up a learning course. The user entered a topic (next message).

Decide whether the topic can be read in ways that would lead to clearly
different lists of sub-topics. Real ambiguity: level ("statistics": high-school
probability, or university statistics). Not ambiguity: a broad but clear
topic ("high school math").

Rules:
- Ask at most 2 questions. Ask none if the readings would lead to
  mostly the same sub-topics.
- Each question offers concrete options.
- Write questions in English.

Output only JSON:
{"needs_clarification": true, "questions": ["..."]}
"""
)


@dataclass
class ClarifyResult:
    needs_clarification: bool
    questions: list[str]


class Clarifier:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def clarify(self, topic: str) -> ClarifyResult:
        """Never raises: a Clarifier that fails simply means "no clarification" (plan 7.4)."""
        messages: list[Message] = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": topic},
        ]
        logger.info("clarifier.clarify() calling provider=%s", self._provider.name)
        try:
            raw = complete_with_json_retry(self._provider, messages)
            data = json.loads(raw)
            raw_questions = data.get("questions") or []
            questions = [q for q in (str(q).strip() for q in raw_questions) if q][:MAX_QUESTIONS]
            # true 却没有问题，等于没有可问的。
            if bool(data.get("needs_clarification")) and questions:
                return ClarifyResult(needs_clarification=True, questions=questions)
        except Exception:
            # 澄清环节本身不能成为阻塞点：任何失败都退化为"不需要澄清"，直接生成。
            logger.warning("clarifier failed, falling back to no-clarification", exc_info=True)
        return ClarifyResult(needs_clarification=False, questions=[])
