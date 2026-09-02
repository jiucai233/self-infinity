"""确定性搜索替身：让离线演示和整个测试套件在检索路径上不断。

和 app/llm/mock.py 是同一个思路——没有它，任何碰到检索的测试都会变成需要网络和
真实 key 才能跑，CI 直接失效。
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
                title=f"关于「{query}」的资料 {i + 1}",
                url=f"https://example.invalid/{i + 1}",
                snippet=f"这是第 {i + 1} 条与「{query}」相关的模拟摘要，用于离线演示。",
            )
            for i in range(min(limit, 3))
        ]
