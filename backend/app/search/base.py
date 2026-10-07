"""搜索能力的抽象。

**这一层刻意和 app/llm/ 平级、互不依赖。** 搜索是 harness 自己的能力，不是某个模型
提供商的附属功能：换成 DeepSeek、ChatGPT 还是 Kimi 都不该影响能不能联网，反过来换
搜索服务也不该动到裁决模型。

不走 Gemini 的 Google Search grounding 正是这个原因——那会把联网能力焊死在一个具体
provider 上，而项目的裁决基准（M2 校准）是在 DeepSeek 上跑出来的，为了搜索去换裁决
模型等于让校准数据作废。
"""

from dataclasses import dataclass
from typing import Protocol


@dataclass
class SearchHit:
    title: str
    url: str
    snippet: str
    # The page's text, only when asked for with `pages=True` (and the service could read it).
    content: str = ""


class SearchProvider(Protocol):
    name: str

    def search(self, query: str, limit: int = 5, *, pages: bool = False) -> list[SearchHit]:
        """返回搜索结果。失败时抛异常，由调用方决定降级策略。

        `pages=True` also fetches each result's page text (`SearchHit.content`), for callers
        that must read more than a snippet — a syllabus's topic list rarely fits in one.
        """
        ...
