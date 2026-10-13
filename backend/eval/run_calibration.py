import argparse
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.agents.auditor import Auditor
from app.agents.challenger import Challenger
from app.llm.base import LLMProvider, Message, complete_with_json_retry
from app.llm.mock import MockProvider
from app.config import settings
from app.i18n import quote, t, use_language
from app.models import NodeType

CALIBRATION_SET_PATH = Path(__file__).parent / "calibration_set.json"
# Must comfortably exceed settings.audit_max_turns (8) / task_max_turns (4) —
# the Auditor forces its own verdict at that point, so this is just a safety
# margin against the harness loop cutting a scenario off before the Auditor
# does, not a limit intended to bind in practice.
MAX_TURNS = 10

# The scenarios are in Chinese; the opening is the one production says (app/i18n.py).
LANGUAGE = "zh"

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
    if name == "openai":
        from app.llm.openai import OpenAIProvider

        # The Auditor's model (LLM_MODEL_OVERRIDES / LLM_MODEL / gpt-6-luna), so the
        # number is for the model the app actually runs.
        return OpenAIProvider(model=settings.model_name_for("auditor") or None)
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


def said(feedback: str | None, question: str) -> str:
    """Her turn as production feeds it back to her (audit_flow.submit_turn): feedback, then question."""
    return f"{feedback}\n\n{question}" if feedback else question


def run_scenario(build, scenario: dict, adaptive_student: bool) -> dict:
    """One scenario the way production runs an audit (app/services/audit_flow.py): the student
    opening, her turns fed back whole, a pass reviewed once by the Challenger and the answer to
    its question getting the verdict. Returns both arms: `first` is the verdict before the
    Challenger (the no-challenger arm), `final` the one after it.

    The Challenger gets no misconceptions: offline there is no "this user's history", and the
    only thing like one in a scenario (label_rationale / expected_passed) is the ground truth.
    """
    provider = build()
    auditor, challenger = Auditor(provider), Challenger(provider)
    node_type = NodeType(scenario["node_type"])
    scripted = scenario["student_turns"]
    out = {"id": scenario["id"], "node_type": scenario["node_type"], "expected": scenario["expected_passed"]}
    with use_language(LANGUAGE):
        key = "opening_leaf" if node_type == NodeType.concept else "opening_task"
        history: list[Message] = [{"role": "assistant", "content": t(key, title=quote(scenario["skill_title"]))}]
        challenged = False
        first = final = None
        for turn in range(MAX_TURNS):
            if turn < len(scripted):
                answer = scripted[turn]
            elif adaptive_student:
                answer = build_student_answer(provider, scenario, history)
            else:
                answer = scripted[-1]
            history.append({"role": "user", "content": answer})
            result = auditor.next_turn(
                scenario["skill_title"],
                scenario["skill_description"],
                history,
                node_type,
                after_challenge=challenged,
            )
            if not result.is_verdict:
                history.append({"role": "assistant", "content": said(result.feedback, result.question)})
                continue
            verdict = {"passed": result.passed, "score": result.score, "gaps": result.gaps, "comment": result.comment}
            first = first or verdict
            if result.passed and not challenged:
                try:
                    review = challenger.review(scenario["skill_title"], scenario["skill_description"], history, [])
                except Exception:  # production upholds the pass when the Challenger fails
                    review = None
                if review is not None and review.overturned:
                    challenged = True
                    out["challenge"] = {"question": review.question, "reason": review.reason}
                    history.append({"role": "assistant", "content": said(result.feedback, review.question)})
                    continue
            final = verdict
            break
    # No verdict within the safety cap counts as not passed.
    unsettled = {"passed": False, "score": None, "gaps": [], "comment": "no verdict"}
    out.update(first=first or unsettled, final=final or unsettled, challenged=challenged, history=history)
    return out


def summary(results: list[dict], arm: str) -> str:
    right = sum(1 for r in results if r[arm]["passed"] == r["expected"])
    should_fail = [r for r in results if not r["expected"]]
    should_pass = [r for r in results if r["expected"]]
    false_pass = sum(1 for r in should_fail if r[arm]["passed"])
    false_fail = sum(1 for r in should_pass if not r[arm]["passed"])
    total = len(results)
    return (
        f"accuracy {right}/{total} = {right / total * 100:.1f}%, "
        f"leniency (false pass among should-fail) {false_pass}/{len(should_fail)} = "
        f"{false_pass / len(should_fail) * 100:.1f}%, "
        f"false fail {false_fail}/{len(should_pass)}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", choices=["openai", "mock"], default="openai")
    # Defaults to on for real providers, off for mock (mock's Auditor never
    # asks beyond ~2 rounds, so the 3 scripted turns are always enough and
    # spending real API calls on a student for it would be pointless).
    parser.add_argument("--adaptive-student", action=argparse.BooleanOptionalAction, default=None)
    parser.add_argument("--workers", type=int, default=6, help="scenarios run at the same time")
    parser.add_argument("--out", type=Path, help="write every transcript and verdict here (JSON)")
    args = parser.parse_args()
    adaptive_student = args.adaptive_student
    if adaptive_student is None:
        adaptive_student = args.provider != "mock"

    scenarios = json.loads(CALIBRATION_SET_PATH.read_text())
    with ThreadPoolExecutor(max(1, args.workers)) as pool:
        results = list(pool.map(lambda s: run_scenario(lambda: build_provider(args.provider), s, adaptive_student), scenarios))
    if args.out:
        args.out.write_text(json.dumps(results, ensure_ascii=False, indent=1))

    for r in results:
        mark = "✓" if r["final"]["passed"] == r["expected"] else "✗"
        print(
            f"{r['id']:<32} node_type={r['node_type']:<7} expected={r['expected']!s:<5} "
            f"before_challenger={r['first']['passed']!s:<5} final={r['final']['passed']!s:<5} {mark}"
        )

    print("\n=== summary ===")
    model = f" ({build_provider(args.provider).model})" if args.provider == "openai" else ""
    print(f"provider: {args.provider}{model}")
    print(f"adaptive_student: {adaptive_student}")
    print(f"challenged: {sum(1 for r in results if r['challenged'])}")
    # One run gives both arms of the ablation (whitepaper §8): the difference is the Challenger's.
    print(f"before the Challenger: {summary(results, 'first')}")
    print(f"final:                 {summary(results, 'final')}")
    for node_type in ("concept", "task"):
        subset = [r for r in results if r["node_type"] == node_type]
        print(f"  [{node_type}] {summary(subset, 'final')}")

    sys.exit(0)


if __name__ == "__main__":
    main()
