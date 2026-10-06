"""Recorder：把一次失败和用户的反思变成一条可复用的教训。

教训由三部分组成：

- **misconception**：用户当时*以为什么是对的*（不是他答错了什么），≤ 60 characters；
- **body**：下次怎么做，"When ..., I ..."形式的具体行为规则，≤ 120 characters；
- **title**：这条规则的短名，≤ 40 characters。

misconception 是后面一切的索引：Memory Retriever 把它交给 Auditor 去追问，Challenger 用它
检查旧毛病有没有复发，Profile Builder 用它给反复出现的错误聚类。
"""

import json
import logging
from dataclasses import dataclass

from app.llm.base import LLMProvider, Message, agent_tag, complete_with_json_retry

logger = logging.getLogger(__name__)

MAX_TITLE = 40
MAX_BODY = 120
MAX_MISCONCEPTION = 60

SYSTEM_PROMPT = (
    agent_tag("recorder")
    + """
The user failed an audit and wrote a short reflection (next message). Turn it
into one lesson they can reuse.

Node: {title}
Gaps found by the examiner: {gaps}

Step 1. Diagnose the wrong mental model: not what was answered wrongly,
but what the user believed to be true. Write it as "misconception",
at most 60 characters.

Step 2. Write a rule for next time as "body", at most 120 characters,
in the form "When ..., I ...".
It must name a concrete situation and a concrete action. No generic
advice such as "review carefully".

Step 3. Write a "title", at most 40 characters, naming the rule.

Write in English.

Output only JSON:
{{"title": "...", "body": "...", "misconception": "..."}}
"""
)

TOO_LONG_NOTICE = (
    "Some fields were too long: {problems}. Output the JSON again with title at most "
    f"{MAX_TITLE}, body at most {MAX_BODY} and misconception at most {MAX_MISCONCEPTION} characters."
)


class RecorderError(Exception):
    """The Recorder's output is unusable (not JSON, or a field is missing or empty)."""


@dataclass
class RecordedLesson:
    title: str
    body: str
    misconception: str


_LIMITS = {"title": MAX_TITLE, "body": MAX_BODY, "misconception": MAX_MISCONCEPTION}


class Recorder:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def distill(self, skill_title: str, gaps: list[str], reflection: str) -> RecordedLesson:
        system = SYSTEM_PROMPT.format(
            title=skill_title,
            gaps="; ".join(" ".join(g.split()) for g in gaps) if gaps else "(none recorded)",
        )
        messages: list[Message] = [
            {"role": "system", "content": system},
            {"role": "user", "content": reflection},
        ]
        logger.info("recorder.distill() calling provider=%s", self._provider.name)
        raw = complete_with_json_retry(self._provider, messages)
        lesson = self._parse(raw)

        too_long = _too_long(lesson)
        if too_long:
            # 超长先让模型自己改一次；改不好（或这次输出坏了）再硬截，不让教训丢掉。
            retry_messages: list[Message] = [
                *messages,
                {"role": "assistant", "content": raw},
                {"role": "user", "content": TOO_LONG_NOTICE.format(problems=", ".join(too_long))},
            ]
            try:
                lesson = self._parse(complete_with_json_retry(self._provider, retry_messages))
            except RecorderError:
                logger.warning("recorder retry produced unusable output, cutting the first one")
        return _cut(lesson)

    @staticmethod
    def _parse(raw: str) -> RecordedLesson:
        try:
            data = json.loads(raw)
        except (json.JSONDecodeError, TypeError) as exc:
            raise RecorderError("recorder output is not valid JSON") from exc
        if not isinstance(data, dict):
            raise RecorderError("recorder output must be a JSON object")
        fields = {}
        for key in _LIMITS:
            value = " ".join(str(data.get(key) or "").split())
            if not value:
                raise RecorderError(f"recorder output is missing {key!r}")
            fields[key] = value
        return RecordedLesson(**fields)


def _too_long(lesson: RecordedLesson) -> list[str]:
    return [key for key, limit in _LIMITS.items() if len(getattr(lesson, key)) > limit]


def _cut(lesson: RecordedLesson) -> RecordedLesson:
    return RecordedLesson(
        **{key: getattr(lesson, key)[:limit].rstrip() for key, limit in _LIMITS.items()}
    )
