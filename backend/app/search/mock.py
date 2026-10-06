"""确定性搜索替身：让离线演示和整个测试套件在检索路径上不断。

和 app/llm/mock.py 是同一个思路——没有它，任何碰到检索的测试都会变成需要网络和
真实 key 才能跑，CI 直接失效。

契约第 4.2 节：找到课纲时 source_url 就是"第一条模拟搜索结果的 URL"，所以这里的
URL 必须稳定。.invalid 是保留顶级域名，永远解析不了，不会误打到真实站点。
"""

import logging

from app.search.base import SearchHit

logger = logging.getLogger(__name__)


class MockSearchProvider:
    name = "mock"

    def search(self, query: str, limit: int = 5) -> list[SearchHit]:
        logger.info("mock search() query=%r limit=%d", query, limit)
        return [
            SearchHit(
                title=f"“{query}” — resource {i}",
                url=f"https://example.invalid/{i}",
                snippet=f"Mock search result {i} for “{query}”. Offline demo text.",
            )
            for i in range(1, min(limit, 3) + 1)
        ]
