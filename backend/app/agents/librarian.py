import json
import logging

from app.llm.base import LLMProvider, Message, complete_with_json_retry

logger = logging.getLogger(__name__)

# Bounds how much candidate text goes into one Librarian call — a body can
# be long, but the judgment only needs enough to tell what a principle is
# about, not the full text.
CANDIDATE_BODY_CHARS = 120

SYSTEM_PROMPT = """\
你是关联图书管理员（Librarian）。有一条新蒸馏出的原则：

标题：{title}
内容：{body}

下面是候选列表，每项前面标了它的引用编号：
{candidates}

任务：
1. related —— 从候选里挑出和这条原则真正有语义关联的（不是字面凑巧重叠），
   最多 4 个。原则×原则的关联通常是"同一类教训""互为前提"；原则×技能的关联
   是"这条原则用得上这个技能"。没有真正相关的就留空数组，不要为了凑数硬选。
2. contradicts —— 只从"principle"类型的候选里挑出和这条新原则在建议做法上
   直接冲突的（比如一条说"当X时我会做A"，另一条说"当X时我会做B"且A、B矛盾）。
   多数情况下这个列表应该是空的，只有真的读出矛盾才填。

只输出严格 JSON：
{{"related": [{{"ref": <编号>, "reason": "<一句话原因，不超过30字>"}}, ...],
  "contradicts": [{{"ref": <编号>, "reason": "<一句话原因，不超过30字>"}}, ...]}}
不要输出 JSON 之外的任何文字。
"""


class Librarian:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def link(
        self,
        title: str,
        body: str,
        candidates: list[tuple[str, int, str, str]],
    ) -> tuple[list[tuple[str, int, str]], list[tuple[int, str]]]:
        """判断新原则与候选节点的关联/矛盾。

        candidates: 每项是 (kind, id, title, body_or_description)，kind 为
        "principle" 或 "skill"。返回 (related, contradicts)：
        - related: 列表 of (target_kind, target_id, reason)
        - contradicts: 列表 of (principle_id, reason) —— 只会来自候选里
          kind="principle" 的项。
        """
        if not candidates:
            return [], []

        candidate_lines = []
        for i, (kind, cid, ctitle, ctext) in enumerate(candidates):
            excerpt = ctext[:CANDIDATE_BODY_CHARS]
            candidate_lines.append(f"[{i}] ({kind}) {ctitle} —— {excerpt}")

        system = SYSTEM_PROMPT.format(
            title=title,
            body=body,
            candidates="\n".join(candidate_lines),
        )
        messages: list[Message] = [
            {"role": "system", "content": system},
            {"role": "user", "content": f"{title}\n{body}"},
        ]
        logger.info("librarian.link() calling provider=%s candidates=%d", self._provider.name, len(candidates))
        try:
            raw = complete_with_json_retry(self._provider, messages)
            data = json.loads(raw)
        except (json.JSONDecodeError, TypeError):
            logger.warning("librarian.link() failed to parse provider response, skipping linking")
            return [], []

        related: list[tuple[str, int, str]] = []
        for item in data.get("related", []):
            ref = item.get("ref")
            reason = item.get("reason", "")
            if not isinstance(ref, int) or not (0 <= ref < len(candidates)):
                continue
            kind, cid, _ctitle, _ctext = candidates[ref]
            related.append((kind, cid, reason))

        contradicts: list[tuple[int, str]] = []
        for item in data.get("contradicts", []):
            ref = item.get("ref")
            reason = item.get("reason", "")
            if not isinstance(ref, int) or not (0 <= ref < len(candidates)):
                continue
            kind, cid, _ctitle, _ctext = candidates[ref]
            if kind == "principle":
                contradicts.append((cid, reason))

        return related, contradicts
