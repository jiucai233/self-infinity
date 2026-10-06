"""字符 2-gram + 英文词重叠的文本相似度，没有任何 embedding 基础设施时的诚实 V1。

用于给 misconception 聚类（app/services/profile.py）。中文、韩文没有天然的分词空白，粗暴按
空白 split 基本无效，所以对全文做"字符 2-gram"重叠比较——对短文本是一种廉价但相当有效的
相似度信号；英文/数字词单独按词精确匹配，权重更高，因为这类词一旦重合几乎可以确定主题
相关。覆盖不了语义相近但用词完全不同的情况，等真的需要时替换这个函数即可。
"""

import re
from collections import Counter

_WORD_RE = re.compile(r"[A-Za-z0-9]+")


def _char_bigrams(text: str) -> Counter:
    # 去掉空白后再取 2-gram，避免因为格式化差异（换行、多余空格）产生假的错位。
    stripped = re.sub(r"\s+", "", text)
    return Counter(stripped[i : i + 2] for i in range(len(stripped) - 1))


def _words(text: str) -> set[str]:
    return {w.lower() for w in _WORD_RE.findall(text) if len(w) >= 2}


def relevance_score(text_a: str, text_b: str) -> int:
    """Pairwise overlap score between any two text blobs; 0 means nothing in common."""
    bigram_overlap = sum((_char_bigrams(text_a) & _char_bigrams(text_b)).values())
    word_overlap = len(_words(text_a) & _words(text_b))
    return bigram_overlap + word_overlap * 2
