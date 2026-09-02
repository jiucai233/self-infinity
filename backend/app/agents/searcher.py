"""检索官（Searcher）：为一个具体的 gap 找补救材料。

**定位约束**：这个角色只在"审计暴露了某个 gap"或"某个错误心智模型反复发作"之后被调用，
入口强制要求带上下文（见 routers/skills.py 的 search-plan 端点）。它不提供"给我找 XX
的资料"这种泛检索——那会让系统退回成又一个学习资料推荐器，而本系统的立论恰恰是
"现有工具只记录学了、不验证会了"。检索在这里是验证失败之后的补救动作，不是入口。

**防幻觉的硬约束**：模型只负责生成检索词、以及从真实结果里挑哪几条有用；
**title 和 url 一律取自 SearchProvider 返回的原始结果，绝不由模型输出**。模型编链接
是必然会发生的，而一个编出来的 URL 比没有 URL 糟糕得多——用户点开才发现是假的。
所以筛选阶段模型只返回下标。
"""

import json
import logging
from dataclasses import dataclass

from app.llm.base import LLMProvider, Message, complete_with_json_retry
from app.search.base import SearchHit, SearchProvider

logger = logging.getLogger(__name__)

QUERY_SYSTEM_PROMPT = """\
你是检索规划官。用户在讲解「{skill_title}」（{skill_description}）时暴露了一个具体缺口：

{gap}

给出 2~3 条检索词，用来找能补上这个缺口的资料。

规则：
1. 检索词要针对**这个缺口**，不是这个主题的泛泛入门。"递归 入门教程"是坏的，
   "递归 为什么需要 base case 栈溢出"是好的。
2. 用适合搜索引擎的表达：关键词组合，不是完整问句，不要带"请问""如何才能"这类词。
3. 如果缺口本身是一个错误的心智模型，检索词要指向"为什么这样想是错的"，
   而不是指向那个错误说法本身——否则搜到的全是同样犯错的内容。

只输出严格 JSON：{{"queries": ["<检索词1>", "<检索词2>"]}}
不要输出 JSON 之外的任何文字。
"""

SELECT_SYSTEM_PROMPT = """\
你是资料筛选官。用户在「{skill_title}」上暴露的缺口是：

{gap}

下面是检索到的候选资料，每条带一个编号：

{candidates}

从中挑出真正能补上这个缺口的，最多 4 条。

规则：
1. 只能引用上面出现过的编号。**不要输出任何网址或标题**——那些由系统从原始结果里取，
   你写的任何链接都会被丢弃。
2. reason 要说清"这条能补上缺口的哪一部分"，不是复述标题或摘要。
3. 挑不出合适的就返回空列表。宁可不给，也不要凑数——用户按你的推荐花时间读完却发现
   没用，比直接说"没找到"更糟。

只输出严格 JSON：{{"picks": [{{"index": <编号>, "reason": "<为什么这条有用>"}}]}}
不要输出 JSON 之外的任何文字。
"""


@dataclass
class SearchPlanItem:
    title: str
    url: str
    snippet: str
    reason: str


class Searcher:
    def __init__(self, provider: LLMProvider, search_provider: SearchProvider):
        self._provider = provider
        self._search = search_provider

    def plan(self, skill_title: str, skill_description: str, gap: str) -> tuple[list[str], list[SearchPlanItem]]:
        queries = self._build_queries(skill_title, skill_description, gap)
        hits = self._collect(queries)
        if not hits:
            return queries, []
        return queries, self._select(skill_title, gap, hits)

    def _build_queries(self, skill_title: str, skill_description: str, gap: str) -> list[str]:
        messages: list[Message] = [
            {
                "role": "system",
                "content": QUERY_SYSTEM_PROMPT.format(
                    skill_title=skill_title, skill_description=skill_description, gap=gap
                ),
            },
            {"role": "user", "content": "请给出检索词。"},
        ]
        logger.info("searcher._build_queries() calling provider=%s", self._provider.name)
        raw = complete_with_json_retry(self._provider, messages)
        try:
            queries = [str(q).strip() for q in json.loads(raw)["queries"] if str(q).strip()]
        except (json.JSONDecodeError, KeyError, TypeError):
            logger.warning("searcher produced unusable queries, falling back to the gap text", exc_info=True)
            queries = []
        # 兜底用 skill + gap 拼一条：检索词生成失败不该让整个补救流程失败。
        return queries[:3] or [f"{skill_title} {gap}"[:120]]

    def _collect(self, queries: list[str]) -> list[SearchHit]:
        """跑完所有检索词并按 URL 去重，保留首次出现的顺序。"""
        seen: set[str] = set()
        hits: list[SearchHit] = []
        for query in queries:
            try:
                results = self._search.search(query)
            except Exception:
                # 一条检索词失败不该让整次补救失败，其余的照跑。
                logger.warning("search failed for query=%r", query, exc_info=True)
                continue
            for hit in results:
                if hit.url in seen:
                    continue
                seen.add(hit.url)
                hits.append(hit)
        return hits

    def _select(self, skill_title: str, gap: str, hits: list[SearchHit]) -> list[SearchPlanItem]:
        candidates = "\n".join(
            f"[{i}] {hit.title} —— {hit.snippet[:200]}" for i, hit in enumerate(hits)
        )
        messages: list[Message] = [
            {
                "role": "system",
                "content": SELECT_SYSTEM_PROMPT.format(
                    skill_title=skill_title, gap=gap, candidates=candidates
                ),
            },
            {"role": "user", "content": "请挑出有用的资料。"},
        ]
        logger.info("searcher._select() calling provider=%s candidates=%d", self._provider.name, len(hits))
        raw = complete_with_json_retry(self._provider, messages)
        try:
            picks = json.loads(raw)["picks"]
            if not isinstance(picks, list):
                raise TypeError("picks is not a list")
        except (json.JSONDecodeError, KeyError, TypeError):
            logger.warning("searcher returned unusable picks", exc_info=True)
            return []

        items: list[SearchPlanItem] = []
        seen: set[int] = set()
        for pick in picks:
            try:
                index = int(pick["index"])
            except (KeyError, TypeError, ValueError):
                continue
            if not 0 <= index < len(hits) or index in seen:
                logger.warning("searcher picked an out-of-range or duplicate index=%s", index)
                continue
            seen.add(index)
            hit = hits[index]
            items.append(
                # title/url/snippet 全部来自 hit，模型只贡献 reason —— 这是那条
                # "URL 绝不由模型生成"的硬约束在代码里的落点。
                SearchPlanItem(title=hit.title, url=hit.url, snippet=hit.snippet, reason=str(pick.get("reason", "")).strip())
            )
        return items[:4]
