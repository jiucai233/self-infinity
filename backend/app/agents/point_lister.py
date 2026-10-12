"""Point Lister：列出一个叶子节点里的知识点。

叶子是最小的节点（一节教科书的量），再往下不是新节点，而是它里面的**知识点**——
“Transformer Basics” 里是 self-attention、前馈层、位置编码这些。审计按知识点一个一个考
（app/agents/auditor.py），所以它们必须是具体、有名字、各自能问出对错的东西。

新课的叶子由 Planner 直接带着知识点生成；这个 agent 只补那些没有的：旧课程的节点、手动加的
节点。输出坏了就当没有，审计照常按 Covers 进行。
"""

import json
import logging

from app.llm.base import LLMProvider, Message, agent_tag, complete_with_json_retry

logger = logging.getLogger(__name__)

MIN_POINTS = 2
MAX_POINTS = 6
MAX_POINT_CHARS = 40

SYSTEM_PROMPT = (
    agent_tag("point_lister")
    + """
A course is a tree of nodes; a leaf is the smallest node, one textbook
section. List the knowledge points inside one leaf: the three to six named
things a learner must be able to explain to say they know it.

Course: {course}
Leaf: {title}
Covers: {description}

- Each point is one mechanism, component, rule or case of this leaf, with
  its real name ("Self-attention", "Positional encoding", "Feed-forward
  layer" for "Transformer Basics"). One thing per point, the one a single
  question can settle: never two or three joined by "and" or a comma
  (with more than six, keep the six that matter most).
- Together they cover what "Covers" names, and nothing outside this leaf.
- No overview, history, summary or "applications" point.
- At most 40 characters each, in English, in the order one would learn
  them.

Output only JSON:
{{"points": ["...", "..."]}}
"""
)


def clean_points(value) -> list[str]:
    """Point titles from a model's list: trimmed, without doubles, at most MAX_POINTS."""
    titles: list[str] = []
    seen: set[str] = set()
    for item in value if isinstance(value, list) else []:
        title = " ".join(str(item or "").split())[:MAX_POINT_CHARS].strip()
        if title and title.casefold() not in seen:
            seen.add(title.casefold())
            titles.append(title)
    return titles[:MAX_POINTS]


class PointLister:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def list(self, course: str, title: str, description: str) -> list[str]:
        """The knowledge points of one leaf; [] when the model gives nothing usable."""
        messages: list[Message] = [
            {
                "role": "system",
                "content": SYSTEM_PROMPT.format(
                    course=course, title=title, description=description or "(no description)"
                ),
            },
            {"role": "user", "content": title},
        ]
        logger.info("point_lister.list() calling provider=%s", self._provider.name)
        raw = complete_with_json_retry(self._provider, messages)
        try:
            data = json.loads(raw)
        except (json.JSONDecodeError, TypeError):
            return []
        points = clean_points(data.get("points") if isinstance(data, dict) else None)
        return points if len(points) >= MIN_POINTS else []
