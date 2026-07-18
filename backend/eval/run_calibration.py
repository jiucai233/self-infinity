import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.agents.auditor import Auditor
from app.llm.base import Message
from app.llm.mock import MockProvider
from app.models import NodeType

CALIBRATION_SET_PATH = Path(__file__).parent / "calibration_set.json"
MAX_TURNS = 6

CONCEPT_OPENING_TEMPLATE = "假设我完全没听说过「{title}」，从零开始，讲给我听。"
TASK_OPENING_TEMPLATE = "「{title}」这一步，你打算具体怎么做？"


def build_provider(name: str):
    if name == "mock":
        return MockProvider()
    if name == "gemini":
        from app.llm.gemini import GeminiProvider

        return GeminiProvider()
    if name == "deepseek":
        from app.llm.deepseek import DeepSeekProvider

        return DeepSeekProvider()
    raise ValueError(f"unknown provider: {name}")


def run_scenario(auditor: Auditor, scenario: dict) -> bool:
    node_type = NodeType(scenario["node_type"])
    student_turns = scenario["student_turns"]

    template = CONCEPT_OPENING_TEMPLATE if node_type == NodeType.concept else TASK_OPENING_TEMPLATE
    opening = template.format(title=scenario["skill_title"])
    history: list[Message] = [{"role": "assistant", "content": opening}]

    for turn in range(MAX_TURNS):
        answer = student_turns[turn] if turn < len(student_turns) else student_turns[-1]
        history.append({"role": "user", "content": answer})

        result = auditor.next_turn(
            scenario["skill_title"], scenario["skill_description"], history, node_type
        )
        if result.is_verdict:
            return result.passed

        history.append({"role": "assistant", "content": result.question})

    return False


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", choices=["mock", "gemini", "deepseek"], default="mock")
    args = parser.parse_args()

    scenarios = json.loads(CALIBRATION_SET_PATH.read_text())
    provider = build_provider(args.provider)
    auditor = Auditor(provider)

    results = []
    for scenario in scenarios:
        actual = run_scenario(auditor, scenario)
        expected = scenario["expected_passed"]
        match = actual == expected
        results.append({**scenario, "actual_passed": actual, "match": match})
        mark = "✓" if match else "✗"
        print(
            f"{scenario['id']:<32} node_type={scenario['node_type']:<7} "
            f"expected={expected!s:<5} actual={actual!s:<5} {mark}"
        )

    total = len(results)
    correct = sum(1 for r in results if r["match"])
    accuracy = correct / total * 100 if total else 0.0

    should_fail = [r for r in results if not r["expected_passed"]]
    false_pass = [r for r in should_fail if r["actual_passed"]]
    leniency = len(false_pass) / len(should_fail) * 100 if should_fail else 0.0

    print("\n=== summary ===")
    print(f"provider: {args.provider}")
    print(f"accuracy: {correct}/{total} = {accuracy:.1f}%")
    print(f"leniency rate (false-pass among should-fail): {len(false_pass)}/{len(should_fail)} = {leniency:.1f}%")

    for node_type in ("concept", "task"):
        subset = [r for r in results if r["node_type"] == node_type]
        sub_correct = sum(1 for r in subset if r["match"])
        sub_accuracy = sub_correct / len(subset) * 100 if subset else 0.0

        sub_should_fail = [r for r in subset if not r["expected_passed"]]
        sub_false_pass = [r for r in sub_should_fail if r["actual_passed"]]
        sub_leniency = len(sub_false_pass) / len(sub_should_fail) * 100 if sub_should_fail else 0.0

        print(
            f"  [{node_type}] accuracy: {sub_correct}/{len(subset)} = {sub_accuracy:.1f}%  "
            f"leniency: {len(sub_false_pass)}/{len(sub_should_fail)} = {sub_leniency:.1f}%"
        )

    sys.exit(0)


if __name__ == "__main__":
    main()
