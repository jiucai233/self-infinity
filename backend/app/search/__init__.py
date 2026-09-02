from app.config import settings
from app.search.base import SearchHit, SearchProvider
from app.search.mock import MockSearchProvider

__all__ = ["SearchHit", "SearchProvider", "get_search_provider"]


def get_search_provider() -> SearchProvider:
    """按配置选择搜索实现，没有 key 就用离线替身。

    和 app/llm/__init__.py 的 get_provider() 同款写法：没有配置任何 key 时整个系统
    仍然完全可跑，只是检索结果是模拟的。这是这个项目一贯的约定——离线永远能演示。
    """
    if settings.tavily_api_key:
        from app.search.tavily import TavilySearchProvider

        return TavilySearchProvider()
    return MockSearchProvider()
