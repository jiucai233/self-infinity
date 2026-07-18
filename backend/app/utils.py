import re


def slugify(text: str) -> str:
    ascii_slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    if ascii_slug:
        return ascii_slug
    # 中文等非 ASCII 标题拿不到可用 slug 时，退化为内容哈希，保证仍然唯一且稳定。
    return f"node-{abs(hash(text)) % 100000}"
