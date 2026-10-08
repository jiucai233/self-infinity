"""Fact Keeper evaluation (contract #40, WHITEPAPER §8 memory consistency).

Each scenario in memory_set.json says a few things in order to an empty fact list, through the
same `keep_facts` the app runs (the Decisions gate first, then the keeper), and checks the list
after the last one. The kinds follow LongMemEval's abilities [Wu et al., 2025]:

- extract   a lasting fact is kept
- noise     one day's sleep, mood, meals or workout keeps nothing
- update    a changed fact holds in its new form; the old one is history
- end       a fact that stopped being true holds no more and is history
- keep      daily talk after a fact leaves it alone (no duplicate, no ending)
- no_guess  a condition the player did not name is never written down

Matching is by keywords (any of a group, case-insensitive), so a run is a check of behaviour,
not of wording.

    backend/.venv/bin/python backend/eval/run_memory.py                   # the app's model, gate on
    backend/.venv/bin/python backend/eval/run_memory.py --no-gate         # keeper on every message
    backend/.venv/bin/python backend/eval/run_memory.py --provider mock   # offline

The real run calls the keeper's model once per message the gate lets through (about 25 calls).
"""

import argparse
import json
import sys
import time
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlmodel import Session, SQLModel, create_engine
from sqlalchemy.pool import StaticPool

from app import models  # noqa: F401  (registers the tables)
from app.config import settings
from app.llm import decisions
from app.llm.mock import MockProvider
from app.services import facts

SET_PATH = Path(__file__).parent / "memory_set.json"


def build_provider(name: str):
    if name == "mock":
        return MockProvider()
    if name == "openai":
        from app.llm.openai import OpenAIProvider

        return OpenAIProvider(model=settings.model_name_for("fact_keeper") or None)
    raise ValueError(f"unknown provider: {name}")


def matches(texts: list[str], words: list[str]) -> bool:
    return any(w.casefold() in t.casefold() for t in texts for w in words)


def check(scenario: dict, current: list[str], past: list[str]) -> list[str]:
    """What went wrong, empty when the scenario passed."""
    problems = []
    for group in scenario.get("current_any", []):
        if not matches(current, group):
            problems.append(f"no current fact with {group}")
    for word in scenario.get("not_current", []):
        if matches(current, [word]):
            problems.append(f"a current fact still says {word!r}")
    for group in scenario.get("past_any", []):
        if not matches(past, group):
            problems.append(f"no past fact with {group}")
    if "current_count" in scenario and len(current) != scenario["current_count"]:
        problems.append(f"{len(current)} current facts, expected {scenario['current_count']}")
    if "past_count" in scenario and len(past) != scenario["past_count"]:
        problems.append(f"{len(past)} past facts, expected {scenario['past_count']}")
    return problems


class Counted:
    """Counts what the gate and the keeper did."""

    def __init__(self, provider, decide):
        self.provider, self._decide = provider, decide
        self.name = provider.name
        self.keeper_calls = 0
        self.gate_calls = 0
        self.gate_skips = 0

    def complete(self, messages):
        self.keeper_calls += 1
        return self.provider.complete(messages)

    def decide(self, input_text, questions):
        self.gate_calls += 1
        answers = self._decide(input_text, questions)
        answer, confidence = answers["lasting"]
        if answer == "no" and confidence >= facts.CONFIDENT:
            self.gate_skips += 1
        return answers


def run(scenario: dict, counted: Counted, gate: bool) -> tuple[list[str], list[str]]:
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        for said in scenario["turns"]:
            facts.keep_facts(session, said, counted, decide=counted.decide if gate else None)
        current = [f.text for f in facts.current_facts(session)]
        past = [f.text for f in facts.past_facts(session)]
    return current, past


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", choices=["openai", "mock"], default="openai")
    parser.add_argument("--gate", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--only", help="run one scenario id")
    args = parser.parse_args()

    gate = args.gate and args.provider != "mock" and decisions.available()
    counted = Counted(build_provider(args.provider), decisions.decide)
    scenarios = [s for s in json.loads(SET_PATH.read_text()) if not args.only or s["id"] == args.only]

    by_kind: dict[str, list[bool]] = defaultdict(list)
    start = time.perf_counter()
    for scenario in scenarios:
        current, past = run(scenario, counted, gate)
        problems = check(scenario, current, past)
        by_kind[scenario["kind"]].append(not problems)
        mark = "PASS" if not problems else "FAIL"
        print(f"{mark}  {scenario['id']:<20} current={current} past={past}")
        for p in problems:
            print(f"      - {p}")
    elapsed = time.perf_counter() - start

    total = sum(len(v) for v in by_kind.values())
    passed = sum(sum(v) for v in by_kind.values())
    print()
    for kind, results in by_kind.items():
        print(f"{kind:<10} {sum(results)}/{len(results)}")
    print(f"overall    {passed}/{total} ({passed / total:.0%})")
    messages = sum(len(s["turns"]) for s in scenarios)
    print(
        f"messages {messages}, keeper calls {counted.keeper_calls}, "
        f"gate {'on' if gate else 'off'}: {counted.gate_calls} asked, {counted.gate_skips} skipped; {elapsed:.1f} s"
    )


if __name__ == "__main__":
    main()
