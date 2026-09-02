"""Searcher：缺口驱动的资料检索。

两条最重要的性质：
- **URL 只能来自搜索结果**。模型编链接是必然的，一个假链接比没有链接糟糕得多。
- **入口必须带缺口上下文**。这是防止系统退化成资料推荐器的那道闸。
"""

import json

from sqlmodel import Session, select

from app.agents.searcher import Searcher
from app.llm.mock import MockProvider
from app.models import AuditSession, AuditStatus, Principle, SearchPlan, SkillNode
from app.search.base import SearchHit
from app.search.mock import MockSearchProvider

GAP = "说不清为什么需要 base case"


class _FixedSearch:
    """返回固定结果的搜索替身，让下标断言可预测。"""

    name = "fixed"

    def __init__(self, hits: list[SearchHit] | None = None, fail: bool = False):
        self._hits = hits if hits is not None else [
            SearchHit(title=f"资料{i}", url=f"https://real.invalid/{i}", snippet=f"摘要{i}")
            for i in range(3)
        ]
        self._fail = fail
        self.queries: list[str] = []

    def search(self, query: str, limit: int = 5) -> list[SearchHit]:
        self.queries.append(query)
        if self._fail:
            raise RuntimeError("search down")
        return self._hits


class _PickProvider(MockProvider):
    """筛选阶段返回指定 payload，其余角色沿用 MockProvider。"""

    def __init__(self, picks_payload: str):
        self._picks_payload = picks_payload

    def complete(self, messages):
        system = next((m["content"] for m in messages if m["role"] == "system"), "")
        if "资料筛选官" in system:
            return self._picks_payload
        return super().complete(messages)


def _searcher(search, provider=None) -> Searcher:
    return Searcher(provider or MockProvider(), search)


def test_urls_always_come_from_search_results_never_from_the_model():
    """模型即使输出了 url/title，也一律被丢弃，用真实结果里的。"""
    forged = json.dumps(
        {"picks": [{"index": 0, "reason": "有用", "url": "https://forged.invalid/evil", "title": "伪造标题"}]}
    )
    search = _FixedSearch()

    _queries, items = _searcher(search, _PickProvider(forged)).plan("递归", "函数调用自身", GAP)

    assert len(items) == 1
    assert items[0].url == "https://real.invalid/0"
    assert items[0].title == "资料0"
    assert "forged" not in items[0].url


def test_out_of_range_indices_are_dropped():
    payload = json.dumps({"picks": [{"index": 0, "reason": "ok"}, {"index": 99, "reason": "编造的"}]})

    _queries, items = _searcher(_FixedSearch(), _PickProvider(payload)).plan("递归", "描述", GAP)

    assert len(items) == 1


def test_duplicate_indices_are_dropped():
    payload = json.dumps({"picks": [{"index": 1, "reason": "a"}, {"index": 1, "reason": "b"}]})

    _queries, items = _searcher(_FixedSearch(), _PickProvider(payload)).plan("递归", "描述", GAP)

    assert len(items) == 1


def test_picks_are_capped_at_four():
    hits = [SearchHit(title=f"t{i}", url=f"https://real.invalid/{i}", snippet="s") for i in range(8)]
    payload = json.dumps({"picks": [{"index": i, "reason": "r"} for i in range(8)]})

    _queries, items = _searcher(_FixedSearch(hits), _PickProvider(payload)).plan("递归", "描述", GAP)

    assert len(items) == 4


def test_empty_picks_is_a_valid_answer():
    """挑不出合适的就该返回空，不该凑数。"""
    _queries, items = _searcher(_FixedSearch(), _PickProvider('{"picks": []}')).plan("递归", "描述", GAP)

    assert items == []


def test_unusable_pick_output_yields_no_items_rather_than_an_error():
    _queries, items = _searcher(_FixedSearch(), _PickProvider("不是 JSON")).plan("递归", "描述", GAP)

    assert items == []


def test_results_are_deduplicated_by_url():
    """两条检索词搜到同一个 URL 时只保留一条。"""
    dup = [SearchHit(title="同一篇", url="https://real.invalid/same", snippet="s")]
    payload = json.dumps({"picks": [{"index": 0, "reason": "r"}, {"index": 1, "reason": "r"}]})

    _queries, items = _searcher(_FixedSearch(dup), _PickProvider(payload)).plan("递归", "描述", GAP)

    assert len(items) == 1


def test_search_failure_yields_no_items_but_does_not_raise():
    """检索服务挂了不该让整个补救流程炸掉。"""
    queries, items = _searcher(_FixedSearch(fail=True)).plan("递归", "描述", GAP)

    assert queries
    assert items == []


def test_queries_fall_back_when_the_model_cannot_produce_them():
    class BadQueryProvider(MockProvider):
        def complete(self, messages):
            system = next((m["content"] for m in messages if m["role"] == "system"), "")
            if "检索规划官" in system:
                return "不是 JSON"
            return super().complete(messages)

    search = _FixedSearch()
    queries, _items = _searcher(search, BadQueryProvider()).plan("递归", "描述", GAP)

    assert len(queries) == 1
    assert "递归" in queries[0]
    assert search.queries  # 兜底检索词确实被拿去搜了


def test_mock_search_provider_returns_deterministic_hits():
    hits = MockSearchProvider().search("递归", limit=2)

    assert len(hits) == 2
    assert all(h.url for h in hits)


# ---------- API 层：入口的上下文强制 ----------


def _root_skill_id(client) -> int:
    return next(s["id"] for s in client.get("/api/skills").json() if s["slug"] == "big-o")


def test_search_plan_requires_a_gap_or_misconception(client):
    resp = client.post(f"/api/skills/{_root_skill_id(client)}/search-plan", json={})

    assert resp.status_code == 400


def test_blank_gap_is_also_rejected(client):
    resp = client.post(f"/api/skills/{_root_skill_id(client)}/search-plan", json={"gap": "   "})

    assert resp.status_code == 400


def test_search_plan_404s_for_an_unknown_skill(client):
    assert client.post("/api/skills/9999/search-plan", json={"gap": GAP}).status_code == 404


def test_search_plan_with_a_gap_persists_and_returns_items(client, client_engine):
    resp = client.post(f"/api/skills/{_root_skill_id(client)}/search-plan", json={"gap": GAP})

    assert resp.status_code == 200
    body = resp.json()
    assert body["gap"] == GAP
    assert body["queries"]
    assert body["items"]
    assert all(item["url"] for item in body["items"])

    with Session(client_engine) as session:
        assert len(session.exec(select(SearchPlan)).all()) == 1


def test_search_plan_can_be_driven_by_a_stored_misconception(client, client_engine):
    misconception = "以为记住结论就等于理解了机制"
    with Session(client_engine) as session:
        skill = session.exec(select(SkillNode)).first()
        audit = AuditSession(skill_id=skill.id, status=AuditStatus.failed)
        session.add(audit)
        session.flush()
        principle = Principle(
            title="原则", body="…", misconception=misconception, source_session_id=audit.id
        )
        session.add(principle)
        session.commit()
        principle_id = principle.id

    body = client.post(
        f"/api/skills/{_root_skill_id(client)}/search-plan", json={"misconception_id": principle_id}
    ).json()

    assert body["gap"] == misconception


def test_unknown_misconception_id_404s(client):
    resp = client.post(
        f"/api/skills/{_root_skill_id(client)}/search-plan", json={"misconception_id": 9999}
    )

    assert resp.status_code == 404
