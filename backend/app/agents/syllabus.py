"""课纲甄别官（SyllabusFinder）：找一份真实存在的课程大纲当编排参考。

动机：模型凭记忆拆解一个领域，拆出来的东西未必是这个领域真的会那样教。一门被实际
讲授过的课（CS285、CS231n、6.006 这类）的主题序列，是经过多轮教学检验的顺序，
比凭空回忆可靠。

**只提取结构，不复制内容。** 抄的是"这门课依次讲了哪些主题"——那是事实，不受版权
保护，也正是有价值的那部分；讲义原文一概不碰。同时把来源记下来并显示给用户，
既经得起追问，本身也是这套检索有效的证据。

**宁可判定没找到。** 判定标准卡得很死（必须能识别出机构 + 课程编号/正式课名），
因为编造一个来源比没有来源糟糕得多：用户会去核对，一旦发现"CS285 里根本没这节"，
整个系统的可信度就没了。搜不到可信的就走 Planner 自己的记忆，那条路本来也不差。
"""

import json
import logging
from dataclasses import dataclass

from app.llm.base import LLMProvider, Message, complete_with_json_retry
from app.search.base import SearchHit, SearchProvider

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """\
你是课纲甄别官。用户想学「{topic}」。下面是检索到的候选网页：

{candidates}

判断其中有没有**真实存在的正式课程大纲**；如果有，提取它的主题序列。

判定标准（必须**同时**满足，否则一律判定为没有）：
1. 能明确识别出**开课机构**（大学、研究所等）；
2. 能明确识别出**课程编号或正式课程名**（例如 CS285、6.006、CS231n、
   "Deep Reinforcement Learning"）；
3. 候选内容里能看出这门课**实际讲了哪些主题**，而不只是一句课程简介。

以下一律不算，宁可判定为没有：
- 博客文章、"XX 入门指南"、学习路线图、培训机构的营销页；
- 你自己知道但**候选里没出现**的课程——不能凭记忆补一个来源出来；
- 只有课程名、看不出讲了什么内容的页面。

**编造一个来源比没有来源糟糕得多**：用户会去核对。

只输出严格 JSON，二选一：
{{"found": false}}
{{"found": true, "index": <候选编号>, "course": "<机构 + 课程编号或课程名>",
  "outline": ["<主题1>", "<主题2>", ...]}}
不要输出 JSON 之外的任何文字。
"""


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
        # 中英各一条：中文课程大纲和英文 syllabus 的检索结果几乎不重叠，而权威课程
        # （CS285 这类）基本只在英文结果里。
        queries = [f"{topic} 课程大纲 讲义目录", f"{topic} course syllabus lecture topics"]
        seen: set[str] = set()
        hits: list[SearchHit] = []
        for query in queries:
            try:
                results = self._search.search(query)
            except Exception:
                logger.warning("syllabus search failed for query=%r", query, exc_info=True)
                continue
            for hit in results:
                if hit.url in seen:
                    continue
                seen.add(hit.url)
                hits.append(hit)
        return hits

    def _judge(self, topic: str, hits: list[SearchHit]) -> SyllabusReference | None:
        candidates = "\n".join(f"[{i}] {h.title} —— {h.snippet[:300]}" for i, h in enumerate(hits))
        messages: list[Message] = [
            {"role": "system", "content": SYSTEM_PROMPT.format(topic=topic, candidates=candidates)},
            {"role": "user", "content": "请判断。"},
        ]
        logger.info("syllabus._judge() calling provider=%s candidates=%d", self._provider.name, len(hits))
        raw = complete_with_json_retry(self._provider, messages)

        try:
            data = json.loads(raw)
        except (json.JSONDecodeError, TypeError):
            logger.warning("syllabus finder returned unusable output", exc_info=True)
            return None

        if not data.get("found"):
            return None

        try:
            index = int(data["index"])
        except (KeyError, TypeError, ValueError):
            return None
        if not 0 <= index < len(hits):
            logger.warning("syllabus finder picked an out-of-range index=%s", index)
            return None

        outline = [str(t).strip() for t in (data.get("outline") or []) if str(t).strip()]
        course = str(data.get("course", "")).strip()
        # 没有主题序列的"课纲"没有参考价值；没有可署的来源则无法向用户交代。
        if not outline or not course:
            return None

        # url 取自检索结果，不用模型输出的——同 searcher 的那条硬约束。
        return SyllabusReference(course=course, url=hits[index].url, outline=outline)
