"""The learner model, and what a verdict is worth as evidence (contract #48). No LLM.

Three things are estimated, each from its own signal:

- **The judge.** The Auditor's verdict is the reward everything else learns from, and it is
  noisy. Its two error rates (passes what should fail, fails what should pass) start from a
  measurement against reference labels and move with what the account says about its own
  verdicts. A result then counts as the probability that it is true given the verdict and
  those rates [Dawid & Skene, 1979], as a noisy reward is corrected before it is learnt from
  [Wang et al., 2020]; a verdict whose votes disagreed counts for less.
- **The learner and the points.** One ability for the account, one difficulty for each
  knowledge point; the chance of explaining a point right is the logistic of their difference,
  moved after every result (the Elo update, as in Math Garden [Klinkenberg et al., 2011]). A
  dozen results are enough to place both roughly, which is the amount of data one person has.
- **Progress.** What the bandit is rewarded with: how far a result went beyond what was
  expected of it. A point they were sure to get right adds almost nothing, one far out of reach
  is not got right; the reward is highest in between [Clement et al., 2015].
"""

import math

from sqlmodel import Session, col, select

from app.models import AuditSession, AuditStatus, Learner, LearnerPoint, LearnerStep, SkillNode, utcnow

# The chance of explaining a point right that recommendations aim at.
TARGET_CHANCE = 0.75
# How far one result moves the ability and the difficulty.
STEP = 0.4
# A verdict whose votes disagreed moves them this much of a step.
SPLIT_WEIGHT = 0.5
# "Too hard", said by the user: the points of that audit get this much harder at once.
TOO_HARD_STEP = 0.5
TIER_DIFFICULTY = {"easy": -0.6, "medium": 0.0, "hard": 0.6}

# The judge measured on 2026-10-13: 13 real audits with a firm reference label, each judged
# four times. It failed 6 of 20 that should pass and passed 0 of 32 that should fail. Kept
# as weak counts, so an account's own word moves them.
PRIOR_FALSE_FAIL = (3.0, 7.0)  # wrong, right: among verdicts that should pass
PRIOR_FALSE_PASS = (0.5, 9.5)  # among verdicts that should fail


def judge_rates(session: Session) -> tuple[float, float]:
    """(false pass rate, false fail rate) of the Auditor for this account: the measured prior
    plus the verdicts the account spoke about. A fail called too strict, or resting on words
    the user did not say, is a false fail; a fail called right is a correct one. A pass called
    too lenient is a false pass."""
    ff_wrong, ff_right = PRIOR_FALSE_FAIL
    fp_wrong, fp_right = PRIOR_FALSE_PASS
    for audit in session.exec(select(AuditSession).where(col(AuditSession.status) != AuditStatus.active)).all():
        failed = audit.status == AuditStatus.failed
        if failed and (audit.review == "too_strict" or audit.disputed):
            ff_wrong += 1
        elif failed and audit.review == "right":
            fp_right += 1
        elif not failed and audit.review == "too_lenient":
            fp_wrong += 1
        elif not failed and audit.review == "right":
            ff_right += 1
    return fp_wrong / (fp_wrong + fp_right), ff_wrong / (ff_wrong + ff_right)


def corrected(result: bool, expected: float, false_pass: float, false_fail: float) -> float:
    """What a judged result is worth: the probability that the explanation really was right,
    given the verdict, the judge's two error rates and what was expected beforehand (Bayes; the
    soft label of Dawid & Skene, 1979). A fail from a judge that fails a third of what should
    pass is not a zero, and it is less of one the more a pass was expected. With a judge that
    never errs it is the result itself."""
    expected = min(1.0, max(0.0, expected))
    right = expected * ((1 - false_fail) if result else false_fail)
    wrong = (1 - expected) * (false_pass if result else (1 - false_pass))
    if right + wrong <= 0:
        return float(result)
    return right / (right + wrong)


def chance(ability: float, difficulty: float) -> float:
    return 1 / (1 + math.exp(difficulty - ability))


def learner(session: Session) -> Learner:
    row = session.exec(select(Learner)).first()
    if row is None:
        row = Learner()
        session.add(row)
        session.flush()
    return row


def point(session: Session, skill: SkillNode, title: str, tier: str = "medium") -> LearnerPoint:
    """The point's row; a new one starts at the difficulty of the node's tier."""
    row = session.exec(
        select(LearnerPoint).where(LearnerPoint.skill_id == skill.id, LearnerPoint.title == title)
    ).first()
    if row is None:
        row = LearnerPoint(skill_id=skill.id, title=title, difficulty=TIER_DIFFICULTY.get(tier, 0.0))
        session.add(row)
        session.flush()
    return row


def open_titles(skill: SkillNode) -> list[str]:
    """What an audit of the node would ask about: its points not explained right yet, or the
    node as one thing when it has none."""
    titles = [p["title"] for p in skill.points if p["ok"] is not True]
    return titles or ([p["title"] for p in skill.points] if skill.points else [""])


def node_chance(session: Session, skill: SkillNode, tier: str = "medium") -> float:
    """The chance, as estimated now, of explaining right what an audit of this node asks."""
    ability = learner(session).ability
    known = {
        row.title: row.difficulty
        for row in session.exec(select(LearnerPoint).where(LearnerPoint.skill_id == skill.id)).all()
    }
    start = TIER_DIFFICULTY.get(tier, 0.0)
    titles = open_titles(skill)
    return sum(chance(ability, known.get(t, start)) for t in titles) / len(titles)


def node_difficulty(session: Session, skill: SkillNode, tier: str = "medium") -> float:
    """The mean difficulty of what an audit of this node would ask about."""
    known = {
        row.title: row.difficulty
        for row in session.exec(select(LearnerPoint).where(LearnerPoint.skill_id == skill.id)).all()
    }
    start = TIER_DIFFICULTY.get(tier, 0.0)
    titles = open_titles(skill)
    return sum(known.get(t, start) for t in titles) / len(titles)


def results_of(passed: bool, points: list[dict] | None) -> list[tuple[str, bool]]:
    """The results an audit gives: one for each point it settled, or the node's own."""
    settled = [(p["title"], p["ok"]) for p in points or [] if isinstance(p.get("ok"), bool)]
    return settled or ([] if points else [("", passed)])


def record(
    session: Session,
    skill: SkillNode,
    passed: bool,
    points: list[dict] | None,
    agreement: float | None,
    tier: str = "medium",
    audit_id: int | None = None,
    offset: float = 0.0,
) -> float | None:
    """Moves the ability and the difficulties by an audit's results and returns its progress,
    0 to 1: how far the results went beyond what was expected. None: nothing was settled.
    `offset`: how much harder the audit's style made it (app/services/audit_style.py): a point
    explained to a child counts as harder than the same point explained to a colleague."""
    results = results_of(passed, points)
    if not results:
        return None
    false_pass, false_fail = judge_rates(session)
    weight = 1.0 if agreement is None or agreement >= 1 else SPLIT_WEIGHT
    me = learner(session)
    ability = me.ability
    progress = 0.0
    for title, ok in results:
        row = point(session, skill, title, tier)
        expected = chance(ability, row.difficulty + offset)
        worth = corrected(ok, expected, false_pass, false_fail)
        progress += worth * (1 - expected)
        move = STEP * weight * (worth - expected)
        me.ability += move / len(results)  # one audit moves the ability about one step in all
        row.difficulty -= move
        row.attempts += 1
        session.add(row)
    me.updated_at = utcnow()
    session.add(me)
    progress /= len(results)
    if audit_id is not None:
        session.add(LearnerStep(session_id=audit_id, ability=me.ability, progress=progress))
    return progress


def history(session: Session) -> list[tuple[LearnerStep, AuditSession, SkillNode]]:
    """The ability after each audit, oldest first, with the audit and its node."""
    return session.exec(
        select(LearnerStep, AuditSession, SkillNode)
        .join(AuditSession, AuditSession.id == LearnerStep.session_id)
        .join(SkillNode, SkillNode.id == AuditSession.skill_id)
        .order_by(col(LearnerStep.id))
    ).all()


def too_hard(session: Session, audit: AuditSession, skill: SkillNode) -> None:
    """The user's word that this audit was beyond them: the points it did not pass get harder at
    once, without waiting for more results. A point they explained right is left as it is."""
    titles = [p["title"] for p in audit.points if p.get("ok") is not True] or [""]
    for title in titles:
        row = point(session, skill, title)
        row.difficulty += TOO_HARD_STEP
        session.add(row)
