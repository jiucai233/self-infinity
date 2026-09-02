"""Tavily 搜索实现。

选 Tavily 是因为它是面向 LLM 的检索服务，直接返回带摘要的结构化结果，不需要自己抓
网页正文。要换成 Serper / Brave 只需在这个目录下再加一个实现，调用方（searcher agent）
不用改——那正是 SearchProvider 这层抽象存在的意义。
"""

import logging
import time

import httpx

from app.config import settings
from app.search.base import SearchHit

logger = logging.getLogger(__name__)

_API_URL = "https://api.tavily.com/search"


class TavilyAPIError(RuntimeError):
    """Tavily 接口返回了非 2xx 状态码。"""


class TavilySearchProvider:
    name = "tavily"

    def __init__(self) -> None:
        self._client = httpx.Client()

    def search(self, query: str, limit: int = 5) -> list[SearchHit]:
        start = time.perf_counter()
        logger.info("tavily search() start query=%r limit=%d", query, limit)
        try:
            response = self._client.post(
                _API_URL,
                json={"query": query, "max_results": limit, "search_depth": "basic"},
                headers={"Authorization": f"Bearer {settings.tavily_api_key}"},
                timeout=settings.search_timeout_seconds,
            )
        except Exception:
            elapsed_ms = (time.perf_counter() - start) * 1000
            logger.warning("tavily search() failed after %.0fms", elapsed_ms, exc_info=True)
            raise

        elapsed_ms = (time.perf_counter() - start) * 1000
        if response.status_code < 200 or response.status_code >= 300:
            logger.warning("tavily search() got status=%d after %.0fms", response.status_code, elapsed_ms)
            raise TavilyAPIError(f"Tavily 调用失败 status={response.status_code} body={response.text[:500]}")

        results = response.json().get("results") or []
        hits = [
            SearchHit(
                title=str(item.get("title", "")).strip(),
                url=str(item.get("url", "")).strip(),
                snippet=str(item.get("content", "")).strip(),
            )
            for item in results
        ]
        # 没有 URL 的结果没有意义——检索的全部价值就是给出可追溯的出处。
        hits = [h for h in hits if h.url]
        logger.info("tavily search() success hits=%d elapsed_ms=%.0f", len(hits), elapsed_ms)
        return hits
