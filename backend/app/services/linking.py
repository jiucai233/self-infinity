from sqlmodel import Session, select

from app.agents.librarian import Librarian
from app.llm.base import LLMProvider
from app.models import LinkKind, LinkTargetKind, Principle, PrincipleLink, SkillNode


def link_principle(
    session: Session,
    provider: LLMProvider,
    principle: Principle,
    exclude_skill_id: int | None = None,
) -> None:
    """Runs the Librarian against every other principle + skill node and
    persists whatever it judges related/contradicting as PrincipleLink rows.

    `exclude_skill_id` leaves out the principle's own origin skill (already
    covered by the "origin" edge in /api/graph, so offering it back as a
    candidate would just be redundant). Best-effort: on any provider failure
    this quietly leaves the principle with no links rather than failing the
    caller — a missing "related" edge is a much smaller problem than a
    reflection submission (or a bulk relink) erroring out.
    """
    other_principles = [
        p for p in session.exec(select(Principle)).all() if p.id != principle.id
    ]
    skills = [s for s in session.exec(select(SkillNode)).all() if s.id != exclude_skill_id]

    candidates: list[tuple[str, int, str, str]] = [
        ("principle", p.id, p.title, p.body) for p in other_principles if p.id is not None
    ] + [("skill", s.id, s.title, s.description) for s in skills if s.id is not None]

    try:
        related, contradicts = Librarian(provider).link(principle.title, principle.body, candidates)
    except Exception:
        return

    for target_kind, target_id, reason in related:
        session.add(
            PrincipleLink(
                principle_id=principle.id,
                target_kind=LinkTargetKind(target_kind),
                target_id=target_id,
                kind=LinkKind.related,
                reason=reason,
            )
        )
    for other_principle_id, reason in contradicts:
        session.add(
            PrincipleLink(
                principle_id=principle.id,
                target_kind=LinkTargetKind.principle,
                target_id=other_principle_id,
                kind=LinkKind.contradicts,
                reason=reason,
            )
        )
    session.commit()
