"""Focus-score heuristic derived from audit engagement timing.

The whitepaper's original focus_score came from desktop screen-capture
monitoring, which is out of scope (ADR-2). The only engagement signal we
actually have is the timestamps of AuditTurn rows within a session, which
alternate auditor <-> user. The gap between consecutive turns approximates
how long the user spent reading a question and composing an answer.

Heuristic (0-100), tuned by hand, not learned -- keep it simple:
- avg gap in the 5s-30s "sweet spot": full engagement, score 100.
- avg gap < 5s: answers came unusually fast on every turn; this looks more
  like paste-in than genuine engagement, so the score tapers down toward 20
  as the gap shrinks to 0. If the audit also FAILED, halve the score again --
  fast-and-wrong is a much stronger copy/guess signal than fast-and-right.
- avg gap > 30s: taper down toward a floor of 10 as the idle gap grows,
  since long pauses between turns suggest the user drifted away.
- Fewer than 2 turns: not enough signal, return a neutral 50.
"""

from datetime import datetime

SWEET_SPOT_LO = 5.0
SWEET_SPOT_HI = 30.0
OVERSHOOT_DECAY_PER_SEC = 1.5
FLOOR = 10
FAST_FAIL_PENALTY = 0.5


def compute_focus_score(turn_timestamps: list[datetime], passed: bool) -> int:
    if len(turn_timestamps) < 2:
        return 50

    # sqlite round-trips datetimes as naive, but freshly-created rows in the
    # same request may still carry tzinfo; normalize to naive before sorting.
    ts = sorted(t.replace(tzinfo=None) for t in turn_timestamps)
    gaps = [(ts[i + 1] - ts[i]).total_seconds() for i in range(len(ts) - 1)]
    avg_gap = sum(gaps) / len(gaps)

    if avg_gap < SWEET_SPOT_LO:
        score = 20 + (avg_gap / SWEET_SPOT_LO) * 80  # 0s -> 20, 5s -> 100
        if not passed:
            score *= FAST_FAIL_PENALTY
    elif avg_gap <= SWEET_SPOT_HI:
        score = 100.0
    else:
        overshoot = avg_gap - SWEET_SPOT_HI
        score = max(FLOOR, 100 - overshoot * OVERSHOOT_DECAY_PER_SEC)

    return int(max(0, min(100, round(score))))
