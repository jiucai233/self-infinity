"""课纲甄别：找一份真实课程大纲当编排参考。

最重要的性质是**宁可判定没找到**。编造一个来源比没有来源糟糕得多——用户会去核对，
一旦发现引用的课程里根本没有那节课，整个系统的可信度就没了。
"""

from unittest.mock import patch

from sqlmodel import Session, select

from app.agents.syllabus import SyllabusFinder
from app.llm.mock import MockProvider
from app.models import CourseSource
from app.search.base import SearchHit


class _FakeSearch:
    name = "fake"

    def __init__(self, hits: list[SearchHit] | None = None, fail: bool = False):
        self._hits = hits or []
        self._fail = fail
        self.queries: list[str] = []

    def search(self, query: str, limit: int = 5) -> list[SearchHit]:
        self.queries.append(query)
        if self._fail:
            raise RuntimeError("search down")
        return self._hits


def _course_hits() -> list[SearchHit]:
    return [
        SearchHit(
            title="UC Berkeley CS285: Deep Reinforcement Learning",
            url="https://real.invalid/cs285",
            snippet="Lecture topics: MDPs, policy gradients, actor-critic, model-based RL.",
        )
    ]


def _blog_hits() -> list[SearchHit]:
    return [
        SearchHit(
            title="强化学习入门指南：从零开始",
            url="https://blog.invalid/rl",
            snippet="这篇文章带你了解强化学习的基本概念。",
        )
    ]


def test_a_real_course_is_accepted():
    ref = SyllabusFinder(MockProvider(), _FakeSearch(_course_hits())).find("强化学习")

    assert ref is not None
    assert ref.url == "https://real.invalid/cs285"
    assert ref.outline


def test_a_blog_post_is_not_a_syllabus():
    """没有机构 + 课程编号就不算 —— 这是那条"宁可没有"的底线。"""
    assert SyllabusFinder(MockProvider(), _FakeSearch(_blog_hits())).find("强化学习") is None


def test_no_search_results_means_no_reference():
    assert SyllabusFinder(MockProvider(), _FakeSearch([])).find("强化学习") is None


def test_search_failure_degrades_quietly():
    """检索挂了只是拿不到参考，不该抛出来打断整次编排。"""
    assert SyllabusFinder(MockProvider(), _FakeSearch(fail=True)).find("强化学习") is None


def test_it_searches_in_both_chinese_and_english():
    """权威课程基本只出现在英文结果里，中文结果又几乎不重叠，所以两边都要搜。"""
    search = _FakeSearch(_course_hits())
    SyllabusFinder(MockProvider(), search).find("强化学习")

    assert len(search.queries) == 2
    assert any("syllabus" in q for q in search.queries)
    assert any("课程大纲" in q for q in search.queries)


def test_url_comes_from_the_search_result_not_the_model():
    class ForgingProvider(MockProvider):
        def complete(self, messages):
            system = next((m["content"] for m in messages if m["role"] == "system"), "")
            if "课纲甄别官" in system:
                return (
                    '{"found": true, "index": 0, "course": "CS285", '
                    '"outline": ["a"], "url": "https://forged.invalid/evil"}'
                )
            return super().complete(messages)

    ref = SyllabusFinder(ForgingProvider(), _FakeSearch(_course_hits())).find("强化学习")

    assert ref is not None
    assert ref.url == "https://real.invalid/cs285"


def test_an_out_of_range_pick_is_rejected():
    class BadIndexProvider(MockProvider):
        def complete(self, messages):
            system = next((m["content"] for m in messages if m["role"] == "system"), "")
            if "课纲甄别官" in system:
                return '{"found": true, "index": 99, "course": "CS285", "outline": ["a"]}'
            return super().complete(messages)

    assert SyllabusFinder(BadIndexProvider(), _FakeSearch(_course_hits())).find("强化学习") is None


def test_a_reference_without_topics_is_useless():
    class EmptyOutlineProvider(MockProvider):
        def complete(self, messages):
            system = next((m["content"] for m in messages if m["role"] == "system"), "")
            if "课纲甄别官" in system:
                return '{"found": true, "index": 0, "course": "CS285", "outline": []}'
            return super().complete(messages)

    assert SyllabusFinder(EmptyOutlineProvider(), _FakeSearch(_course_hits())).find("强化学习") is None


# ---------- 接入 /api/skills/generate ----------


def test_generate_records_the_source_when_one_is_found(client, client_engine):
    with patch("app.routers.skills.get_search_provider", return_value=_FakeSearch(_course_hits())):
        body = client.post("/api/skills/generate", json={"topic": "强化学习"}).json()

    assert body["source"] is not None
    assert body["source"]["url"] == "https://real.invalid/cs285"

    with Session(client_engine) as session:
        assert len(session.exec(select(CourseSource)).all()) == 1


def test_generate_reports_no_source_rather_than_a_vague_one(client, client_engine):
    """没找到可信课纲时 source 是 null，界面据此什么都不显示。"""
    with patch("app.routers.skills.get_search_provider", return_value=_FakeSearch(_blog_hits())):
        body = client.post("/api/skills/generate", json={"topic": "强化学习"}).json()

    assert body["source"] is None
    assert body["nodes"]  # 树照常生成，只是没有外部参考

    with Session(client_engine) as session:
        assert session.exec(select(CourseSource)).all() == []


def test_syllabus_lookup_can_be_switched_off(client):
    search = _FakeSearch(_course_hits())
    with patch("app.routers.skills.get_search_provider", return_value=search):
        body = client.post(
            "/api/skills/generate", json={"topic": "强化学习", "search_syllabus": False}
        ).json()

    assert search.queries == []
    assert body["source"] is None


def test_a_broken_search_still_produces_a_tree(client):
    """检索是加分项，不是前置条件。"""
    with patch("app.routers.skills.get_search_provider", return_value=_FakeSearch(fail=True)):
        resp = client.post("/api/skills/generate", json={"topic": "强化学习"})

    assert resp.status_code == 200
    assert resp.json()["nodes"]
    assert resp.json()["source"] is None
