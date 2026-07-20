"""V1.5 incentive engine (whitepaper §4.4): deterministic arithmetic, no ML.

reward = base * difficulty * level_multiplier^k

There is no User table in this single-user app, so "level" (and thus k) is
derived from global state -- the count of currently-mastered SkillNodes --
rather than from a per-user account.
"""

from sqlmodel import Session, func, select

from app.models import NodeType, SkillNode, SkillStatus

BASE_REWARD = 10  # fixed constant per whitepaper's "base" term
LEVEL_MULTIPLIER_BASE = 1.1  # compounding factor per level, per whitepaper wording
NODES_PER_LEVEL = 5  # every 5 mastered nodes bumps the global level by 1


def _node_depth(session: Session, node: SkillNode) -> int:
    """Count parent_id hops to the tree root. Root nodes have depth 0."""
    depth = 0
    current = node
    while current.parent_id is not None:
        current = session.get(SkillNode, current.parent_id)
        depth += 1
    return depth


def node_difficulty_score(session: Session, skill: SkillNode) -> float:
    """Concept nodes survive the full Feynman protocol (harder) than task nodes,
    so they get a 2x base weight over 1x for tasks. Depth adds +0.5x per level,
    since a node reached via a longer parent chain is harder-won than a root.
    """
    type_weight = 2.0 if skill.node_type == NodeType.concept else 1.0
    depth = _node_depth(session, skill)
    return type_weight * (1 + 0.5 * depth)


def _global_level(session: Session) -> int:
    """Global "level" derived from total mastered nodes so far (this app has no
    per-user accounts). Every NODES_PER_LEVEL masteries bumps the level by 1,
    starting at level 1.
    """
    mastered_count = session.exec(
        select(func.count()).select_from(SkillNode).where(SkillNode.status == SkillStatus.mastered)
    ).one()
    return mastered_count // NODES_PER_LEVEL + 1


def compute_reward(session: Session, skill: SkillNode) -> tuple[int, float]:
    """Compute (amount, multiplier) for passing an audit on `skill`.

    Call this AFTER `skill.status` has been flipped to mastered (and flushed),
    so the pass that reaches a new level threshold is itself rewarded at the
    new, higher level -- consistent with "compounding reward for the same
    task at higher levels" from the whitepaper.
    """
    difficulty = node_difficulty_score(session, skill)
    level = _global_level(session)
    multiplier = LEVEL_MULTIPLIER_BASE**level
    amount = round(BASE_REWARD * difficulty * multiplier)
    return amount, multiplier
