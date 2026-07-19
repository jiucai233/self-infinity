import json
import logging
from dataclasses import dataclass

from app.llm.base import LLMProvider, Message, complete_with_json_retry

logger = logging.getLogger(__name__)

MAX_QUESTIONS = 2

SYSTEM_PROMPT = """\
你是澄清官（Clarifier）。用户会给你一个学习主题，你要判断：这个主题是不是已经
具体到可以直接拆解成一棵靠谱的技能树，还是模糊到需要先反问用户一两个问题，
把范围收窄之后再拆解才不会跑偏。

判断依据：
- 如果主题已经指向一个明确、边界清楚的知识点或技术，直接可以拆解，不需要澄清。
  例如"B 树"——这已经是一个具体的数据结构，不用再问，可以直接生成。
- 如果主题很宽泛、有多个互不相同的子方向、或者不知道用户想要的深度，
  就应该先反问，不要瞎猜着往下拆。
  例如"做饭"——中餐、法餐、烘焙……方向完全不同，应该问"你想深入哪个具体方向/菜系？"
  例如"强化学习"——入门认知和能实际调参落地是完全不同的范围，应该问
  "你希望学到什么深度——入门认知还是能实际动手做？"
  例如"我要学编程"——连语言、方向都没有，必须先问清楚。

规则：
1. 最多问 2 个问题，宁可少问、问在点子上，也不要为了凑数硬问。
2. 问题要像在帮用户想清楚自己要什么，而不是考察用户，语气参考"你想深入哪个具体
   方向""你希望学到什么深度"这种收窄范围/收窄目标的问法。
3. 只输出严格 JSON，二选一：
   {"needs_clarification": true, "questions": ["<问题1>", "<问题2，可省略>"]}
   {"needs_clarification": false, "questions": []}
不要输出 JSON 之外的任何文字。
"""


@dataclass
class ClarifyResult:
    needs_clarification: bool
    questions: list[str]


class Clarifier:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def clarify(self, topic: str) -> ClarifyResult:
        messages: list[Message] = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": topic},
        ]
        logger.info("clarifier.clarify() calling provider=%s", self._provider.name)
        raw = complete_with_json_retry(self._provider, messages)
        try:
            data = json.loads(raw)
            needs_clarification = bool(data["needs_clarification"])
            questions = [str(q) for q in data.get("questions", [])][:MAX_QUESTIONS]
            if needs_clarification and not questions:
                raise ValueError("needs_clarification=true but no questions provided")
        except (json.JSONDecodeError, KeyError, TypeError, ValueError):
            # 协议兜底：解析失败时不能让流程卡住，直接判定为"不需要澄清"，
            # 退化为照旧直接生成——系统必须收敛，不允许澄清环节本身成为阻塞点。
            logger.warning(
                "clarifier.clarify() failed to parse provider response, falling back to no-clarification"
            )
            return ClarifyResult(needs_clarification=False, questions=[])

        return ClarifyResult(needs_clarification=needs_clarification, questions=questions)
