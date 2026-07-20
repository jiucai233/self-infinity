import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.agents.auditor import Auditor
from app.llm.base import LLMProvider, Message, complete_with_json_retry
from app.llm.mock import MockProvider
from app.models import NodeType

CALIBRATION_SET_PATH = Path(__file__).parent / "calibration_set.json"
# Must comfortably exceed settings.audit_max_turns (8) / task_max_turns (4) —
# the Auditor forces its own verdict at that point, so this is just a safety
# margin against the harness loop cutting a scenario off before the Auditor
# does, not a limit intended to bind in practice.
MAX_TURNS = 10

CONCEPT_OPENING_TEMPLATE = "假设我完全没听说过「{title}」，从零开始，讲给我听。"
TASK_OPENING_TEMPLATE = "「{title}」这一步，你打算具体怎么做？"

# See README.md "2026-07-20 Re-run" / root-cause note: replaying a fixed
# `student_turns` script and repeating the last line once it runs out made
# every concept "-pass" scenario fail, because a real model's follow-up
# chain (now dynamic-length, no fixed round quota — §4.2) runs deeper than
# the 3 scripted turns. This system prompt lets an LLM keep playing the same
# student persona once the script runs out, grounded in the scripted turns'
# tone/depth and the scenario's labeled understanding level, instead of
# stalling on a stale non-answer.
STUDENT_SYSTEM_PROMPT = """\
你在扮演一个正在接受费曼审计的学生角色，用来测试审计官的追问深度是否够用。

主题：{skill_title}（{skill_description}）

这个学生角色的真实理解水平判定为：{level_desc}
判定依据：{label_rationale}

这个学生已经这样回答过（保持同样的知识水平、语气、详略程度，不要突然变得
更懂或更不懂）：
{prior_turns}

审计官刚才继续追问了一个新问题。以这个学生的身份、这个理解水平自然作答：
- 如果这个学生本来就理解扎实，可以针对追问里的细节做进一步阐述/澄清，但不要
  凭空编出比上面已经展示的水平更高的新知识点；
- 如果这个学生本来就有理解缺口，继续用同样含糊、复述式的语气回答，不要因为
  被追问就突然讲清楚了。

只输出严格 JSON：{{"answer": "<这个学生会说的这句话，不包含任何角色说明或引号>"}}
不要输出 JSON 之外的任何文字。
"""


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


def build_student_answer(provider: LLMProvider, scenario: dict, history: list[Message]) -> str:
    level_desc = "扎实、经得起追问" if scenario["expected_passed"] else "有明确缺口，经不起追问"
    prior_turns = "\n".join(f"{i + 1}. {t}" for i, t in enumerate(scenario["student_turns"]))
    system = STUDENT_SYSTEM_PROMPT.format(
        skill_title=scenario["skill_title"],
        skill_description=scenario["skill_description"],
        level_desc=level_desc,
        label_rationale=scenario["label_rationale"],
        prior_turns=prior_turns,
    )
    last_question = next((m["content"] for m in reversed(history) if m["role"] == "assistant"), "")
    messages: list[Message] = [
        {"role": "system", "content": system},
        {"role": "user", "content": last_question},
    ]
    raw = complete_with_json_retry(provider, messages)
    try:
        return json.loads(raw)["answer"]
    except (json.JSONDecodeError, KeyError, TypeError):
        # One bad student turn shouldn't crash the whole calibration run —
        # fall back to repeating the last scripted line, same as the
        # non-adaptive path.
        return scenario["student_turns"][-1]


def run_scenario(auditor: Auditor, provider: LLMProvider, scenario: dict, adaptive_student: bool) -> bool:
    node_type = NodeType(scenario["node_type"])
    student_turns = scenario["student_turns"]

    template = CONCEPT_OPENING_TEMPLATE if node_type == NodeType.concept else TASK_OPENING_TEMPLATE
    opening = template.format(title=scenario["skill_title"])
    history: list[Message] = [{"role": "assistant", "content": opening}]

    for turn in range(MAX_TURNS):
        if turn < len(student_turns):
            answer = student_turns[turn]
        elif adaptive_student:
            answer = build_student_answer(provider, scenario, history)
        else:
            answer = student_turns[-1]
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
    # Defaults to on for real providers, off for mock (mock's Auditor never
    # asks beyond ~2 rounds, so the 3 scripted turns are always enough and
    # spending real API calls on a student for it would be pointless).
    parser.add_argument("--adaptive-student", action=argparse.BooleanOptionalAction, default=None)
    args = parser.parse_args()
    adaptive_student = args.adaptive_student
    if adaptive_student is None:
        adaptive_student = args.provider != "mock"

    scenarios = json.loads(CALIBRATION_SET_PATH.read_text())
    provider = build_provider(args.provider)
    auditor = Auditor(provider)

    results = []
    for scenario in scenarios:
        actual = run_scenario(auditor, provider, scenario, adaptive_student)
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
    print(f"adaptive_student: {adaptive_student}")
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
