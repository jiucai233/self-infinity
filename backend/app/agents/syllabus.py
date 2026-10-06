"""Syllabus Finder：找一份真实存在的课程大纲当编排参考。

动机：模型凭记忆拆解一个领域，拆出来的东西未必是这个领域真的会那样教。一门被实际
讲授过的课，它的主题序列是经过多轮教学检验的顺序，比凭空回忆可靠。

**只提取结构，不复制内容。** 抄的是"这门课依次讲了哪些主题"——那是事实，也正是有价值
的那部分；讲义原文一概不碰。同时把来源记下来并显示给用户，既经得起追问，本身也是这套
检索有效的证据。

**URL 由代码从搜索结果里取，绝不让模型写**（AD-5）：模型会编出看起来合理却不存在的链接，
所以它只返回结果的编号。

**宁可判定没找到。** 编造一个来源比没有来源糟糕得多：用户会去核对。搜不到可信的就走
Planner 自己的知识，那条路本来也不差。
"""

import json
import logging
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from urllib.parse import urlparse

from app.llm.base import LLMProvider, Message, agent_tag, complete_with_json_retry
from app.search.base import SearchHit, SearchProvider

logger = logging.getLogger(__name__)

MIN_OUTLINE_ITEMS = 3
MAX_OUTLINE_ITEMS = 30
EXCERPT_CHARS = 300

SYSTEM_PROMPT = (
    agent_tag("syllabus_finder")
    + """
You receive a topic and numbered web search results. Find one result that
is a real course syllabus for this topic.

Topic: {topic}
Results:
{numbered_results}

A result qualifies only if all three are visible in its title, domain
or excerpt:
1. an identifiable institution (university, school, or official
   curriculum body);
2. a course name or course code;
3. a list of topics covered.

Rules:
- Choose at most one result. If none qualifies, report not found.
  Not finding one is a normal outcome.
- Never write a URL. Refer to the result only by its index.
- outline: the topics in the syllabus order, as short phrases, copied or
  lightly shortened from the result, written in English.

Output only JSON, one of:
{{"found": true, "index": 0, "course": "institution + course name or code", "outline": ["..."]}}
{{"found": false}}
"""
)


@dataclass
class SyllabusReference:
    course: str
    url: str
    outline: list[str]


class SyllabusFinder:
    def __init__(self, provider: LLMProvider, search_provider: SearchProvider):
        self._provider = provider
        self._search = search_provider

    def find(self, topic: str) -> SyllabusReference | None:
        hits = self._collect(topic)
        if not hits:
            return None
        return self._judge(topic, hits)

    def _collect(self, topic: str) -> list[SearchHit]:
        # 两次搜索（课纲 / syllabus 两种说法）互不依赖，
        # 并行跑；结果按查询顺序合并，与谁先返回无关。
        subject = (topic.strip().splitlines() or [""])[0].strip()
        queries = [f"{subject} syllabus", f"{subject} course syllabus"]
        with ThreadPoolExecutor(max_workers=len(queries)) as pool:
            batches = list(pool.map(self._search_one, queries))

        seen: set[str] = set()
        hits: list[SearchHit] = []
        for batch in batches:
            for hit in batch:
                if hit.url in seen:
                    continue
                seen.add(hit.url)
                hits.append(hit)
        return hits

    def _search_one(self, query: str) -> list[SearchHit]:
        try:
            return self._search.search(query)
        except Exception:
            logger.warning("syllabus search failed for query=%r", query, exc_info=True)
            return []

    def _judge(self, topic: str, hits: list[SearchHit]) -> SyllabusReference | None:
        numbered = "\n".join(
            f"[{i}] {hit.title} | {urlparse(hit.url).netloc} | {' '.join(hit.snippet.split())[:EXCERPT_CHARS]}"
            for i, hit in enumerate(hits)
        )
        messages: list[Message] = [
            {"role": "system", "content": SYSTEM_PROMPT.format(topic=topic.strip(), numbered_results=numbered)},
            {"role": "user", "content": "Decide."},
        ]
        logger.info("syllabus._judge() calling provider=%s candidates=%d", self._provider.name, len(hits))
        raw = complete_with_json_retry(self._provider, messages)

        try:
            data = json.loads(raw)
        except (json.JSONDecodeError, TypeError):
            logger.warning("syllabus finder returned unusable output", exc_info=True)
            return None
        if not isinstance(data, dict) or not data.get("found"):
            return None

        try:
            index = int(data["index"])
        except (KeyError, TypeError, ValueError):
            return None
        if not 0 <= index < len(hits):
            logger.warning("syllabus finder picked an out-of-range index=%s", index)
            return None

        raw_outline = data.get("outline")
        outline = [str(t).strip() for t in raw_outline if str(t).strip()] if isinstance(raw_outline, list) else []
        course = str(data.get("course") or "").strip()
        # 没有主题序列的"课纲"没有参考价值；没有可署的来源则无法向用户交代。
        if not course or not MIN_OUTLINE_ITEMS <= len(outline) <= MAX_OUTLINE_ITEMS:
            return None

        # url 取自检索结果，不用模型输出的。
        return SyllabusReference(course=course, url=hits[index].url, outline=outline)
