"""原则检索：审计开始时，把该用户历史上在类似技能点栽过的原则找出来。

白皮书 §4.3 把这一步的终态描述为"原则库向量化 + 语义检索"（V2）。这个项目里没有任何
向量数据库或 embedding 基础设施，为此专门引入一套是本任务范围之外的过度工程。这里先做一版
诚实的 V1：不用向量，用关键词/字符重叠的启发式匹配，效果覆盖不了语义相近但用词完全不同的
情况，但对"同一个技能点/同一批常见术语反复出现"这种最常见的场景已经够用，而且容易测试、
容易解释。等真的需要语义检索时再替换掉这个函数即可，调用方不需要跟着变。

匹配思路：
1. 中文没有天然的分词空白，粗暴按空白 split 基本无效，所以对全文做「字符 2-gram」重叠比较，
   这对中文短文本是一种廉价但相当有效的相似度信号。
2. 英文/数字词（比如 "BFS"、"Big-O"）单独按词提取出来做精确词匹配，权重更高——这类词一旦
   重合，几乎可以确定主题相关。
3. 两者的重叠计数相加作为总分，过滤掉 0 分（完全不沾边）的原则，按分数降序取前 limit 条。
"""

import re
from collections import Counter

from sqlmodel import Session, select

from app.models import Principle, SkillNode

_WORD_RE = re.compile(r"[A-Za-z0-9]+")


def _char_bigrams(text: str) -> Counter:
    # 去掉空白后再取 2-gram，避免因为格式化差异（换行、多余空格）产生假的错位。
    stripped = re.sub(r"\s+", "", text)
    return Counter(stripped[i : i + 2] for i in range(len(stripped) - 1))


def _words(text: str) -> set[str]:
    return {w.lower() for w in _WORD_RE.findall(text) if len(w) >= 2}


def relevance_score(text_a: str, text_b: str) -> int:
    """Generic pairwise overlap score — despite the parameter names used
    below (principle/skill), this compares any two text blobs and is also
    reused by app/routers/graph.py to score principle<->skill "related"
    edges for the knowledge graph, not just the audit-time retrieval this
    module was originally written for."""
    bigrams_a = _char_bigrams(text_a)
    bigrams_b = _char_bigrams(text_b)
    bigram_overlap = sum((bigrams_a & bigrams_b).values())

    words_a = _words(text_a)
    words_b = _words(text_b)
    word_overlap = len(words_a & words_b)

    return bigram_overlap + word_overlap * 2


def find_relevant_principles(session: Session, skill: SkillNode, limit: int = 3) -> list[Principle]:
    """返回和 skill 最相关的历史原则，最相关的排最前面；找不到相关的就返回空列表。

    单用户小应用的原则表数据量很小，这里直接全表扫描打分，不做任何索引/分页优化。
    """
    skill_text = f"{skill.title} {skill.description}"
    principles = session.exec(select(Principle)).all()

    scored = [
        (principle, relevance_score(f"{principle.title} {principle.body}", skill_text))
        for principle in principles
    ]
    relevant = [(p, score) for p, score in scored if score > 0]
    relevant.sort(key=lambda item: item[1], reverse=True)
    return [p for p, _score in relevant[:limit]]
