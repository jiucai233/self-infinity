"""How a course stands to the player's other courses: the same one asked for again, a part of
another, or holding another (contract #2, #44).

Two steps, because neither alone is enough:

1. **Recall by embedding.** Titles are embedded (OpenAI `text-embedding-3-small`) and the nearest
   ones become candidates. Similarity alone cannot decide: "Linear Regression" and "Logistic
   Regression" score 0.70, higher than "Computer Vision" and "计算机视觉（感知）" (0.62) or "TCP"
   and "Transmission Control Protocol" (0.56). Without an OpenAI key, a character-overlap score
   recalls instead (app/services/text_overlap.py).
2. **Judge with the Decisions API.** The candidates are the choices of one question; a model picks
   one (or none) with a confidence, in about 0.3 s. Only a confident answer acts.

Without the Decisions API nothing is judged: only exact titles match (`course_edit.auto_link`).
Every step that fails leaves things as they were: a course is still built, just not matched.
"""

import logging
import math
from collections.abc import Callable

import httpx
from sqlmodel import Session, col, select

from app.config import settings
from app.llm import decisions
from app.models import AuditSession, Course, EdgeKind, SkillEdge, SkillNode, SkillStatus
from app.services.course_edit import can_link, course_root, courses_inside, doomed, sync_links, title_key
from app.services.courses import purge_nodes
from app.services.text_overlap import relevance_score
from app.services.tree import contains_children, contains_parents, descendant_ids, open_next
from app.utils import slugify

logger = logging.getLogger(__name__)

EMBED_URL = "https://api.openai.com/v1/embeddings"
EMBED_MODEL = "text-embedding-3-small"
EMBED_TIMEOUT = 10.0

Embed = Callable[[list[str]], list[list[float]]]
Decide = Callable[[str, list[dict]], dict[str, tuple[str, float]]]

# A judged answer acts only at this confidence or above.
CONFIDENT = 0.6
# How many candidates the judge sees, and how near one must be to be shown at all.
CANDIDATES = 6
RECALL_FLOOR = 0.3
# Two titles in one course this near are the same node (a plural, a hyphen): the new one is
# left out without asking. Different things score up to about 0.7 (see above).
SAME_TITLE = 0.9

_cache: dict[str, list[float]] = {}
_CACHE_MAX = 20_000
_client = httpx.Client()


def openai_embed(texts: list[str]) -> list[list[float]]:
    """Embeddings for `texts`, cached by text for the process. Raises on failure."""
    missing = list(dict.fromkeys(t for t in texts if t not in _cache))
    for start in range(0, len(missing), 1000):
        batch = missing[start : start + 1000]
        response = _client.post(
            EMBED_URL,
            json={"model": EMBED_MODEL, "input": batch},
            headers={"Authorization": f"Bearer {settings.openai_api_key}"},
            timeout=EMBED_TIMEOUT,
        )
        response.raise_for_status()
        for text, item in zip(batch, response.json()["data"], strict=True):
            if len(_cache) >= _CACHE_MAX:
                _cache.clear()
            _cache[text] = item["embedding"]
    return [_cache[t] for t in texts]


def default_embed() -> Embed | None:
    return openai_embed if settings.openai_api_key else None


def default_decide() -> Decide | None:
    return decisions.decide if decisions.available() else None


def _cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b, strict=False))
    norm = math.sqrt(sum(x * x for x in a) * sum(y * y for y in b))
    return dot / norm if norm else 0.0


def similarities(query: str, texts: list[str], embed: Embed | None) -> list[float]:
    """How near each of `texts` is to `query`, 0..1: cosine of embeddings, or without them (or
    when the call fails) the character overlap scaled by the query's own."""
    if not texts:
        return []
    if embed is not None:
        try:
            vectors = embed([query, *texts])
            return [_cosine(vectors[0], v) for v in vectors[1:]]
        except Exception:
            logger.warning("embedding failed, recalling by overlap", exc_info=True)
    own = max(1, relevance_score(query, query))
    return [min(1.0, relevance_score(query, t) / own) for t in texts]


def _judge(decide: Decide, text: str, questions: list[dict]) -> dict[str, tuple[str, float]] | None:
    try:
        return decide(text, questions)
    except Exception:
        logger.warning("the course matcher's judge failed", exc_info=True)
        return None


def _live_roots(session: Session) -> list[tuple[Course, SkillNode]]:
    out = []
    for course in session.exec(select(Course).where(col(Course.archived_at).is_(None)).order_by(Course.id)).all():
        root = course_root(session, course.id)
        if root is not None:
            out.append((course, root))
    return out


# ---------------------------------------------------------------- the same course asked for again


def same_course(
    session: Session, topic: str, *, embed: Embed | None = None, decide: Decide | None = None
) -> Course | None:
    """The player's course that `topic` asks for again, or None. An exact title (or topic) is it
    without asking; otherwise the nearest courses are judged."""
    subject = (topic.strip().splitlines() or [""])[0].strip()
    roots = _live_roots(session)
    key = title_key(subject)
    for course, root in roots:
        if key and key in (title_key(root.title), title_key(course.topic.splitlines()[0])):
            return course
    if decide is None or not roots:
        return None
    labels = [f"{root.title} ({course.topic.splitlines()[0]})" for course, root in roots]
    scores = similarities(subject, labels, embed)
    ranked = sorted(zip(scores, roots, labels, strict=True), key=lambda x: -x[0])
    shown = [(c, label) for score, (c, _), label in ranked[:3] if score >= RECALL_FLOOR]
    if not shown:
        return None
    question = decisions.choice(
        "same",
        "The player asks for a new course on the subject in the input. Is it one of the courses "
        "they already have: the same subject, under any name or in any language? A broader or a "
        "narrower subject is not the same course.",
        [(f"c{c.id}", label) for c, label in shown] + [("none", "None of these: a new course")],
    )
    answer = _judge(decide, f"Requested course: {subject}", [question])
    choice, confidence = (answer or {}).get("same", ("none", 0.0))
    if choice == "none" or confidence < CONFIDENT:
        return None
    return next((c for c, _ in shown if f"c{c.id}" == choice), None)


# ---------------------------------------------------------------- a course inside another


def _path(session: Session, node: SkillNode) -> str:
    titles, current, seen = [node.title], node, {node.id}
    while True:
        parents = contains_parents(session, current.id)
        if not parents or parents[0].id in seen:
            return " > ".join(reversed(titles))
        current = parents[0]
        seen.add(current.id)
        titles.append(current.title)


def _untouched(session: Session, node: SkillNode) -> bool:
    """Nothing under `node` was learned: no node mastered, no audit taken."""
    ids = descendant_ids(session, node.id)
    if not ids:
        return True
    if session.exec(select(SkillNode.id).where(col(SkillNode.id).in_(ids), SkillNode.status == SkillStatus.mastered)).first():
        return False
    return session.exec(select(AuditSession.id).where(col(AuditSession.skill_id).in_(ids))).first() is None


def _linked(session: Session, course_id: int) -> bool:
    return session.exec(select(SkillNode.id).where(SkillNode.linked_course_id == course_id)).first() is not None


def place_course(
    session: Session,
    course_id: int,
    hosts: list[int] | None = None,
    *,
    embed: Embed | None = None,
    decide: Decide | None = None,
) -> SkillNode | None:
    """Finds where course `course_id` belongs among the nodes of the courses `hosts` (all its
    other live courses by default) and links it there: to a node that is it (whose parts, if
    none was learned yet, give way to the course), or to a new node under the area it belongs
    to. A course already inside another stays where it is. Returns the linked node, or None.
    Does not commit."""
    if decide is None or _linked(session, course_id):
        return None
    root = course_root(session, course_id)
    if root is None:
        return None
    host_ids = [c for c in (hosts if hosts is not None else [c.id for c, _ in _live_roots(session)]) if c != course_id]
    if not host_ids:
        return None
    names = {c.id: r.title for c, r in _live_roots(session)}
    nodes = [
        n
        for n in session.exec(select(SkillNode).where(col(SkillNode.course_id).in_(host_ids))).all()
        if n.linked_course_id is None and n.course_id in names
    ]
    if not nodes:
        return None
    labels = [f"{n.title} (in {names[n.course_id]})" for n in nodes]
    scores = similarities(root.title, labels, embed)
    ranked = sorted(zip(scores, nodes, strict=True), key=lambda x: -x[0])
    shown = [n for score, n in ranked[:CANDIDATES] if score >= RECALL_FLOOR]
    if not shown:
        return None
    parts = ", ".join(c.title for c in contains_children(session, root.id)[:8]) or "not broken down yet"
    questions = [
        decisions.choice(
            "where",
            "The input is one of the player's courses. Which of these nodes of their other courses "
            "is where it belongs: the node that is the same subject, or the area it is one part of? "
            "None if it belongs to none of them.",
            [(f"n{n.id}", _path(session, n)) for n in shown] + [("none", "None of these")],
        ),
        decisions.choice(
            "how",
            "How does the course stand to the node chosen above?",
            [("same", "The node is the same subject as the course"), ("part", "The course is one part of the node")],
        ),
    ]
    answer = _judge(decide, f"Course: {root.title}. It covers: {root.description} Its parts: {parts}.", questions)
    if answer is None:
        return None
    where, confidence = answer.get("where", ("none", 0.0))
    how, _ = answer.get("how", ("part", 0.0))
    node = next((n for n in shown if f"n{n.id}" == where), None)
    if node is None or confidence < CONFIDENT:
        return None
    # The two would hold each other: checked before anything changes.
    if node.course_id in courses_inside(session, course_id):
        return None
    if how == "same" and contains_parents(session, node.id):
        if contains_children(session, node.id):
            if not _untouched(session, node):
                return None  # it was learned in place: left as it is
            purge_nodes(session, [i for i in doomed(session, node) if i != node.id])
            session.flush()
        target = node
    else:
        target = _new_part(session, node, root)
    problem = can_link(session, target, course_id)
    if problem:
        logger.warning("course %s not placed at node %s: %s", course_id, target.id, problem)
        if target is not node:
            purge_nodes(session, [target.id])
            session.flush()
        return None
    target.linked_course_id = course_id
    target.unexpanded = False
    session.add(target)
    session.flush()
    open_next(session, target.course_id)
    sync_links(session)
    logger.info("course %s placed at node %s (%s, %.2f)", course_id, target.id, how, confidence)
    return target


def _new_part(session: Session, parent: SkillNode, root: SkillNode) -> SkillNode:
    taken = set(session.exec(select(SkillNode.slug).where(SkillNode.course_id == parent.course_id)).all())
    base = slugify(root.title) or "course"
    slug, n = base, 2
    while slug in taken:
        slug, n = f"{base}-{n}", n + 1
    part = SkillNode(
        course_id=parent.course_id,
        slug=slug,
        title=root.title,
        description=root.description,
        status=SkillStatus.locked,
        node_type=root.node_type,
    )
    session.add(part)
    session.flush()
    session.add(SkillEdge(from_id=parent.id, to_id=part.id, kind=EdgeKind.contains, is_primary=True))
    session.flush()
    return part


def place_around(
    session: Session, course_id: int, *, embed: Embed | None = None, decide: Decide | None = None
) -> list[SkillNode]:
    """After `course_id` was built or grew: it may belong inside another course, and the courses
    not inside any yet may belong inside it. Returns the nodes linked. Does not commit."""
    if decide is None:
        return []
    placed = []
    found = place_course(session, course_id, embed=embed, decide=decide)
    if found is not None:
        placed.append(found)
    for course, _ in _live_roots(session):
        if course.id == course_id:
            continue
        found = place_course(session, course.id, [course_id], embed=embed, decide=decide)
        if found is not None:
            placed.append(found)
    return placed


# ---------------------------------------------------------------- one course: the same node twice


def near_titles(new: list[str], have: list[str], embed: Embed | None) -> set[str]:
    """The titles of `new` that one of `have` already is (a plural, a hyphen, a casing): exact
    after normalising, or with embeddings at SAME_TITLE or above."""
    keys = {title_key(h) for h in have}
    out = {t for t in new if title_key(t) in keys}
    rest = [t for t in new if t not in out]
    if embed is None or not rest or not have:
        return out
    try:
        vectors = embed([*rest, *have])
    except Exception:
        logger.warning("embedding failed, matching titles exactly", exc_info=True)
        return out
    for i, title in enumerate(rest):
        if any(_cosine(vectors[i], vectors[len(rest) + j]) >= SAME_TITLE for j in range(len(have))):
            out.add(title)
    return out
