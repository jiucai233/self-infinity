"""Linker：把新教训和已有的教训、节点连起来。

教训存下来之后，Linker 判断它和哪些已有的东西*真的*有关系，生成两种链接：

- **related**：这条教训适用于那个节点，或和那条旧教训出自同一个想法；
- **contradicts**：用户自己的两条教训在同一情境下要求相反的做法。很少见。

链接的用处：Memory Retriever 顺着链接走，所以在 “Quadratic Equations” 学到的教训会在审计 “Quadratic Functions”
时回来；知识图谱把它们画出来；矛盾则让用户看到自己的两条规则不可能同时成立。

它在 reflection 的响应发出**之后**才运行（BackgroundTasks），失败只意味着没有链接，教训本身
早已保存。所以这里的 link() 对模型输出的各种问题一律宽容，只对 provider 异常不做吞咽——
吞不吞由编排层（app/services/linking.py）决定。
"""

import json
import logging
from dataclasses import dataclass

from app.llm.base import LLMProvider, Message, agent_tag, complete_with_json_retry

logger = logging.getLogger(__name__)

MAX_RELATED = 4
MAX_REASON = 40
CANDIDATE_TEXT_CHARS = 120

SYSTEM_PROMPT = (
    agent_tag("linker")
    + """
The user saved a new lesson. Decide which existing items it is genuinely
connected to.

New lesson:
{title}: {body} (misconception: {misconception})

Candidates (P = past lesson, S = skill node):
{numbered_candidates}

related: the new lesson applies to the candidate, or comes from the same
underlying idea. Judge by meaning, not by shared words.

contradicts: only between two lessons (P), and only when they recommend
conflicting actions in the same situation. This is rare; the list is
usually empty.

Rules:
- At most 4 related. Fewer is better than weak links.
- reason: at most 40 characters, in English.
- Refer to candidates only by number.

Output only JSON:
{{"related": [{{"ref": 0, "reason": "..."}}], "contradicts": [{{"ref": 0, "reason": "..."}}]}}
"""
)


@dataclass(frozen=True)
class LinkCandidate:
    kind: str  # "principle" | "skill"
    id: int
    title: str
    text: str  # a lesson's body, or a node's description


@dataclass
class LinkJudgment:
    related: list[tuple[LinkCandidate, str]]
    contradicts: list[tuple[LinkCandidate, str]]


def _one_line(text: str) -> str:
    return " ".join(str(text).split())


class Linker:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def link(
        self, title: str, body: str, misconception: str | None, candidates: list[LinkCandidate]
    ) -> LinkJudgment:
        if not candidates:
            return LinkJudgment(related=[], contradicts=[])

        numbered = "\n".join(
            f"[{i}] {'P' if c.kind == 'principle' else 'S'}  {_one_line(c.title)} — "
            f"{_one_line(c.text)[:CANDIDATE_TEXT_CHARS]}"
            for i, c in enumerate(candidates)
        )
        system = SYSTEM_PROMPT.format(
            title=_one_line(title),
            body=_one_line(body),
            misconception=_one_line(misconception or ""),
            numbered_candidates=numbered,
        )
        messages: list[Message] = [
            {"role": "system", "content": system},
            {"role": "user", "content": "Judge the links."},
        ]
        logger.info("linker.link() calling provider=%s candidates=%d", self._provider.name, len(candidates))
        raw = complete_with_json_retry(self._provider, messages)
        try:
            data = json.loads(raw)
        except (json.JSONDecodeError, TypeError):
            logger.warning("linker returned non-JSON, skipping linking")
            return LinkJudgment(related=[], contradicts=[])
        if not isinstance(data, dict):
            return LinkJudgment(related=[], contradicts=[])

        related: list[tuple[LinkCandidate, str]] = []
        seen: set[int] = set()
        for ref, reason in _refs(data.get("related"), len(candidates)):
            if ref in seen:
                continue
            seen.add(ref)
            related.append((candidates[ref], reason))
        related = related[:MAX_RELATED]

        contradicts: list[tuple[LinkCandidate, str]] = []
        seen = set()
        for ref, reason in _refs(data.get("contradicts"), len(candidates)):
            candidate = candidates[ref]
            # 矛盾只存在于两条教训之间；指向节点的矛盾没有意义。
            if candidate.kind != "principle" or ref in seen:
                continue
            seen.add(ref)
            contradicts.append((candidate, reason))

        return LinkJudgment(related=related, contradicts=contradicts)


def _refs(items, count: int) -> list[tuple[int, str]]:
    """Valid (ref, reason) pairs; refs outside the candidate list are ignored."""
    if not isinstance(items, list):
        return []
    result = []
    for item in items:
        if not isinstance(item, dict):
            continue
        ref = item.get("ref")
        if isinstance(ref, bool) or not isinstance(ref, int) or not 0 <= ref < count:
            continue
        result.append((ref, _one_line(item.get("reason") or "")[:MAX_REASON]))
    return result
