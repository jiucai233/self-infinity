"""V1.5 incentive engine (whitepaper §4.4): deterministic arithmetic, no ML.

reward = base * difficulty * level_multiplier^k

There is no User table in this single-user app, so "level" (and thus k) is
derived from global state -- the count of currently-mastered SkillNodes --
rather than from a per-user account.
"""

from sqlmodel import Session, func, select

from app.models import NodeType, SkillNode, SkillStatus
from app.services.tree import node_depth

BASE_REWARD = 10  # fixed constant per whitepaper's "base" term
LEVEL_MULTIPLIER_BASE = 1.1  # compounding factor per level, per whitepaper wording
NODES_PER_LEVEL = 5  # every 5 mastered nodes bumps the global level by 1


def node_difficulty_score(session: Session, skill: SkillNode, depth: int | None = None) -> float:
    """Concept nodes survive the full Feynman protocol (harder) than task nodes,
    so they get a 2x base weight over 1x for tasks. Depth adds +0.5x per level,
    since a node reached via a longer contains chain is harder-won than a root.

    `depth` is the number of contains hops to the root along the main parent
    (see app/services/tree.py); pass it in when scoring many nodes at once.
    """
    type_weight = 2.0 if skill.node_type == NodeType.concept else 1.0
    if depth is None:
        depth = node_depth(session, skill)
    return type_weight * (1 + 0.5 * depth)


def mastered_count(session: Session) -> int:
    return session.exec(
        select(func.count()).select_from(SkillNode).where(SkillNode.status == SkillStatus.mastered)
    ).one()


def global_level(session: Session) -> int:
    """Global "level" derived from total mastered nodes so far (this app has no
    per-user accounts). Every NODES_PER_LEVEL masteries bumps the level by 1,
    starting at level 1.
    """
    return mastered_count(session) // NODES_PER_LEVEL + 1


def compute_reward(session: Session, skill: SkillNode) -> tuple[int, float]:
    """Compute (amount, multiplier) for passing an audit on `skill`.

    Call this AFTER `skill.status` has been flipped to mastered (and flushed),
    so the pass that reaches a new level threshold is itself rewarded at the
    new, higher level -- consistent with "compounding reward for the same
    task at higher levels" from the whitepaper.
    """
    difficulty = node_difficulty_score(session, skill)
    level = global_level(session)
    multiplier = LEVEL_MULTIPLIER_BASE**level
    amount = round(BASE_REWARD * difficulty * multiplier)
    return amount, multiplier
