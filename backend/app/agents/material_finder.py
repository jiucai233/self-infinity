"""Material Finder (plan 7.4): material for one specific gap, in two LLM steps.

Step 1 writes search queries, the web search runs, step 2 picks results by index. Both steps
share the agent name `material_finder` (the Mock tells them apart by the results block).
Hard rule (AD-5): title, url and snippet come from the search results, never from the model.
The entry point requires a gap or a misconception; it is not a general material search.
If the second step fails the result list is empty.
"""

import json
import logging
from dataclasses import dataclass

from app.llm.base import LLMProvider, Message, agent_tag, complete_with_json_retry, fill_template
from app.search.base import SearchHit, SearchProvider

logger = logging.getLogger(__name__)

MAX_ITEMS = 3
MIN_QUERIES, MAX_QUERIES = 2, 3

QUERY_PROMPT = (
    agent_tag("material_finder")
    + """
A learner failed to explain one point. Write web search queries that find
material explaining exactly that point.

Node: {title} — {description}
Gap: {gap}

Rules:
- 2 or 3 queries, in English.
- Target the gap, not the whole topic. "quadratic equations" is too broad;
  "discriminant negative complex roots meaning" is targeted.

Output only JSON:
{{"queries": ["..."]}}
"""
)

PICK_PROMPT = (
    agent_tag("material_finder")
    + """
A learner has this gap: {gap} (node: {title}).
Numbered search results (title, domain, excerpt):
<results>
{results}
</results>

Pick up to 3 results that directly explain the gap. Prefer explanations
and worked examples. Avoid general overviews, unanswered forum posts and
pages that only sell a course.

Rules:
- Never write a URL. Refer to results by index.
- reason: one sentence on which part of the gap the result addresses,
  in English.
- Picking fewer than 3, or none, is allowed.

Output only JSON:
{{"picks": [{{"index": 0, "reason": "..."}}]}}
"""
)


@dataclass
class MaterialItem:
    title: str
    url: str
    snippet: str
    reason: str


def _domain(url: str) -> str:
    return url.split("//", 1)[-1].split("/", 1)[0]


class MaterialFinder:
    def __init__(self, provider: LLMProvider, search: SearchProvider):
        self._provider = provider
        self._search = search

    def find(self, title: str, description: str, gap: str) -> tuple[list[str], list[MaterialItem]]:
        """Returns (queries, items). Raises if no query can be written (the caller answers 502)."""
        queries = self._write_queries(title, description, gap)
        hits = self._run_searches(queries)
        if not hits:
            return queries, []
        try:
            return queries, self._pick(title, gap, hits)
        except Exception:
            logger.warning("material finder pick step failed, returning no items", exc_info=True)
            return queries, []

    def _write_queries(self, title: str, description: str, gap: str) -> list[str]:
        messages: list[Message] = [
            {"role": "system", "content": fill_template(QUERY_PROMPT, title=title, description=description, gap=gap)},
            {"role": "user", "content": "Write the queries."},
        ]
        logger.info("material_finder step 1 calling provider=%s", self._provider.name)
        raw = complete_with_json_retry(self._provider, messages)
        data = json.loads(raw)["queries"]
        if not isinstance(data, list):
            raise TypeError("queries is not a list")
        queries = list(dict.fromkeys(q for q in (str(q).strip() for q in data) if q))[:MAX_QUERIES]
        if not queries:
            raise ValueError("no usable query")
        return queries

    def _run_searches(self, queries: list[str]) -> list[SearchHit]:
        hits: list[SearchHit] = []
        seen: set[str] = set()
        failures = 0
        for query in queries:
            try:
                results = self._search.search(query)
            except Exception:
                failures += 1
                logger.warning("search failed for query=%r", query, exc_info=True)
                continue
            for hit in results:
                if hit.url not in seen:
                    seen.add(hit.url)
                    hits.append(hit)
        if failures == len(queries):
            raise RuntimeError("every search failed")
        return hits

    def _pick(self, title: str, gap: str, hits: list[SearchHit]) -> list[MaterialItem]:
        results = "\n".join(
            f"[{i}] {hit.title} | {_domain(hit.url)} | {' '.join(hit.snippet.split())[:200]}"
            for i, hit in enumerate(hits)
        )
        messages: list[Message] = [
            {"role": "system", "content": fill_template(PICK_PROMPT, gap=gap, title=title, results=results)},
            {"role": "user", "content": "Pick the results."},
        ]
        logger.info("material_finder step 2 calling provider=%s results=%d", self._provider.name, len(hits))
        picks = json.loads(complete_with_json_retry(self._provider, messages))["picks"]
        if not isinstance(picks, list):
            raise TypeError("picks is not a list")

        items: list[MaterialItem] = []
        seen: set[int] = set()
        for pick in picks:
            try:
                index = pick["index"]
                if isinstance(index, bool):
                    continue
                index = int(index)
            except (KeyError, TypeError, ValueError):
                continue
            if not 0 <= index < len(hits) or index in seen:
                continue
            seen.add(index)
            hit = hits[index]
            items.append(
                MaterialItem(
                    title=hit.title, url=hit.url, snippet=hit.snippet, reason=str(pick.get("reason") or "").strip()
                )
            )
        return items[:MAX_ITEMS]
