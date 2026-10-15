"""Who the user explains to, and how deep she asks: chosen per audit by a linear Thompson
Sampling bandit (contract #49). No LLM.

An audit has a style: the listener (`expert`, `student`, `child`) and the depth of the
questions (0: what a part is and what it is for; 1: also the main way it works; 2: also how
that is carried out, one level down). The Feynman test is hardest told to a child, who needs
every term in everyday words, and easiest told to someone from the field, who needs none; a
deeper question is harder than a shallower one. A user in good shape (slept, not stressed,
passing lately) should be pushed toward the harder styles, one in bad shape toward the easier
ones (the owner's idea, 2026-10-15).

Nine arms, one per style. Each arm is a Bayesian linear regression of the reward on the
context, and a style is chosen by sampling every arm's weights from its posterior and taking
the best predicted reward [Agrawal & Goyal, ICML 2013]. One person's data is a few dozen
audits, so the model is linear and small, and its prior already holds the idea above: harder
styles predict more reward the better the shape the user is in. Data moves it from there.

The reward is the audit's progress (app/services/learner.py), and the learner model counts a
result under a harder style as harder (`difficulty_offset`). A pass under the easiest style was
expected and adds little, so the bandit cannot gain by choosing the easiest style every time.

Pure Python: six features, nine arms; numpy would be a dependency for a 6x6 solve.
"""

import json
import math
import random
from dataclasses import dataclass
from datetime import timedelta

from sqlmodel import Session, select

from app.models import AuditSession, AuditStatus, DailyCheckIn, SkillNode, StyleArm
from app.services import learner
from app.utils import local_today

AUDIENCES = ("expert", "student", "child")
DEPTHS = (0, 1, 2)
DEFAULT_STYLE = ("student", 1)

FEATURES = ("bias", "ability", "node_difficulty", "sleep", "stress", "pass_rate")
# How sure the prior is, as a count of audits' worth of evidence, and how widely a style's
# weights are sampled around their posterior mean (larger: more exploring).
PRIOR_PRECISION = 4.0
SAMPLE_SCALE = 0.25
# The reward every style is expected to bring before anything is known, and how much a
# harder style gains (or loses) per unit of the user's shape.
PRIOR_REWARD = 0.3
PRIOR_SHAPE_GAIN = 0.05
# How many recent finished audits the pass rate is read from.
RECENT_AUDITS = 10
# A step on either axis, on the learner model's difficulty scale.
OFFSET_STEP = 0.5


@dataclass(frozen=True)
class Style:
    audience: str
    depth: int

    @property
    def level(self) -> float:
        """-1 (expert, depth 0) to 1 (child, depth 2): how hard the style is."""
        return ((AUDIENCES.index(self.audience) - 1) + (self.depth - 1)) / 2


def styles() -> list[Style]:
    return [Style(a, d) for a in AUDIENCES for d in DEPTHS]


def difficulty_offset(audience: str | None, depth: int | None) -> float:
    """How much harder than the default a style makes what is asked, for the learner model."""
    a = AUDIENCES.index(audience) if audience in AUDIENCES else 1
    d = depth if depth in DEPTHS else 1
    return OFFSET_STEP * ((a - 1) + (d - 1))


# ---------------------------------------------------------------- the context


def _clip(value: float, bound: float) -> float:
    return max(-bound, min(bound, value))


def _recent_pass_rate(session: Session) -> float:
    rows = session.exec(
        select(AuditSession)
        .where(AuditSession.status != AuditStatus.active)
        .order_by(AuditSession.created_at.desc())
        .limit(RECENT_AUDITS)
    ).all()
    if not rows:
        return 0.5
    return sum(1 for r in rows if r.status == AuditStatus.passed) / len(rows)


def _check_in(session: Session) -> DailyCheckIn | None:
    """Today's check-in, or yesterday's: a morning audit before checking in still has last night."""
    today = local_today()
    for day in (today, today - timedelta(days=1)):
        row = session.exec(select(DailyCheckIn).where(DailyCheckIn.date == day)).first()
        if row is not None:
            return row
    return None


def context(session: Session, skill: SkillNode) -> list[float]:
    """The features, each centred so 0 means "as usual" or "not known": what is not known (no
    check-in, no history) leaves the prior to decide."""
    ability = learner.learner(session).ability
    node_difficulty = learner.node_difficulty(session, skill)
    check_in = _check_in(session)
    sleep = (check_in.sleep_hours - 7) / 2 if check_in and check_in.sleep_hours is not None else 0.0
    stress = (check_in.stress - 3) / 2 if check_in and check_in.stress is not None else 0.0
    pass_rate = (_recent_pass_rate(session) - 0.5) * 2
    return [1.0, _clip(ability, 3), _clip(node_difficulty, 3), _clip(sleep, 2), _clip(stress, 2), pass_rate]


def prior_mean(style: Style) -> list[float]:
    """What a style is expected to bring before data: the same for all at "as usual", and the
    harder the style, the more it gains from good shape (sleep, low stress, passing, ability)
    and loses on a hard node."""
    g = PRIOR_SHAPE_GAIN * style.level
    return [PRIOR_REWARD, g, -g, g, -g, g]


# ---------------------------------------------------------------- linear algebra (6x6)


def _cholesky(a: list[list[float]]) -> list[list[float]]:
    n = len(a)
    low = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i + 1):
            s = a[i][j] - sum(low[i][k] * low[j][k] for k in range(j))
            low[i][j] = math.sqrt(max(s, 1e-12)) if i == j else s / low[j][j]
    return low


def _solve_lower(low: list[list[float]], b: list[float]) -> list[float]:
    y = []
    for i in range(len(b)):
        y.append((b[i] - sum(low[i][k] * y[k] for k in range(i))) / low[i][i])
    return y


def _solve_upper_t(low: list[list[float]], b: list[float]) -> list[float]:
    """Solves Lᵀ x = b."""
    n = len(b)
    x = [0.0] * n
    for i in reversed(range(n)):
        x[i] = (b[i] - sum(low[k][i] * x[k] for k in range(i + 1, n))) / low[i][i]
    return x


def _dot(u: list[float], v: list[float]) -> float:
    return sum(a * b for a, b in zip(u, v))


# ---------------------------------------------------------------- the arms


def arm(session: Session, style: Style) -> StyleArm:
    """The style's posterior, kept as precision A and vector b (mean A⁻¹b); a new one starts at
    the prior: A = λI, b = λ·prior mean."""
    row = session.exec(
        select(StyleArm).where(StyleArm.audience == style.audience, StyleArm.depth == style.depth)
    ).first()
    if row is None:
        n = len(FEATURES)
        precision = [[PRIOR_PRECISION if i == j else 0.0 for j in range(n)] for i in range(n)]
        row = StyleArm(
            audience=style.audience,
            depth=style.depth,
            a_json=json.dumps(precision),
            b_json=json.dumps([PRIOR_PRECISION * m for m in prior_mean(style)]),
        )
        session.add(row)
        session.flush()
    return row


def posterior_mean(row: StyleArm) -> list[float]:
    low = _cholesky(json.loads(row.a_json))
    return _solve_upper_t(low, _solve_lower(low, json.loads(row.b_json)))


def sample_weights(row: StyleArm, rng: random.Random) -> list[float]:
    """Weights drawn from N(mean, v²A⁻¹): the mean plus v·L⁻ᵀz, where A = LLᵀ."""
    low = _cholesky(json.loads(row.a_json))
    mean = _solve_upper_t(low, _solve_lower(low, json.loads(row.b_json)))
    noise = _solve_upper_t(low, [rng.gauss(0, 1) for _ in mean])
    return [m + SAMPLE_SCALE * z for m, z in zip(mean, noise)]


def choose(session: Session, x: list[float], rng: random.Random | None = None) -> Style:
    rng = rng or random.Random()
    best, best_score = Style(*DEFAULT_STYLE), -math.inf
    for style in styles():
        score = _dot(sample_weights(arm(session, style), rng), x)
        if score > best_score:
            best, best_score = style, score
    return best


def update(session: Session, audience: str, depth: int, x: list[float], reward: float, weight: float = 1.0) -> None:
    """One audit's reward, 0 to 1, for the style it was held in: A += w·xxᵀ, b += w·r·x."""
    if audience not in AUDIENCES or depth not in DEPTHS or len(x) != len(FEATURES):
        return
    row = arm(session, Style(audience, depth))
    a = json.loads(row.a_json)
    b = json.loads(row.b_json)
    reward = min(1.0, max(0.0, float(reward)))
    for i in range(len(x)):
        b[i] += weight * reward * x[i]
        for j in range(len(x)):
            a[i][j] += weight * x[i] * x[j]
    row.a_json, row.b_json = json.dumps(a), json.dumps(b)
    row.pulls += 1
    row.reward_sum += reward
    session.add(row)


def summary(session: Session) -> list[dict]:
    """Each style's audits and mean reward so far, for the developer panel."""
    rows = {(r.audience, r.depth): r for r in session.exec(select(StyleArm)).all()}
    out = []
    for style in styles():
        row = rows.get((style.audience, style.depth))
        pulls = row.pulls if row else 0
        out.append(
            {
                "audience": style.audience,
                "depth": style.depth,
                "audits": pulls,
                "mean_reward": round(row.reward_sum / pulls, 3) if row and pulls else None,
            }
        )
    return out
