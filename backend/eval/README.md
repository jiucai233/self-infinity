# Auditor calibration harness

Offline evaluation of `Auditor.next_turn` judgment quality against a hand-labeled
30-scenario calibration set (`calibration_set.json`), per WHITEPAPER.md §9 M2:
"接入 Gemini + 校准集 | 30 条校准集裁决准确率 ≥ 80%，放水率 ≤ 10%".

## Running

```
backend/.venv/bin/python backend/eval/run_calibration.py --provider mock
backend/.venv/bin/python backend/eval/run_calibration.py --provider gemini
backend/.venv/bin/python backend/eval/run_calibration.py --provider deepseek
```

`--provider mock` (default) runs offline with no API key, using the deterministic
`MockProvider` heuristic. `--provider gemini`/`--provider deepseek` require the
matching API key set in `backend/.env` (see `app/config.py`), since they make
real API calls for every scenario.

## What it measures

For each scenario, the script replays `student_turns` into a simulated audit
conversation (opening question, then probes) up to a safety cap of 6 rounds,
and compares the final verdict's `passed` against the scenario's
`expected_passed` ground truth. It reports:

- overall accuracy (% of scenarios where actual verdict matches expected)
- leniency rate (放水率): among scenarios that SHOULD fail, the % that the
  Auditor incorrectly passed — this is the false-pass / grade-inflation risk
- both metrics broken down by `node_type` (concept vs task)

## Interpreting mock vs gemini results

`MockProvider` is a simple keyword/length heuristic (see `app/llm/mock.py`),
not real language understanding — it exists for fast offline tests, not for
judging genuine comprehension. Its accuracy on this calibration set is
**not** the M2 acceptance bar; it will misjudge scenarios whose surface
wording happens to trip its keyword checks in either direction.

The M2 bar (accuracy ≥ 80%, leniency ≤ 10%) applies to a real provider
(`--provider gemini` or `--provider deepseek`). Run it that way to get the
number that actually gates the milestone.

## Real run (2026-07-19, `--provider deepseek`, model `deepseek-chat`)

```
accuracy: 21/30 = 70.0%
leniency rate (false-pass among should-fail): 1/15 = 6.7%
  [concept] accuracy: 7/15 = 46.7%  leniency: 0/7 = 0.0%
  [task] accuracy: 14/15 = 93.3%  leniency: 1/8 = 12.5%
```

Leniency (6.7%) clears the ≤10% bar. Accuracy (70.0%) misses the ≥80% bar,
but it's driven almost entirely by concept-node false *negatives* (real
model marked a genuinely good explanation as failed), not the grade-inflation
failure mode the bar exists to catch — all 8 concept `-pass` scenarios failed,
0 concept `-fail` scenarios leaked through, task accuracy is 93.3%.

**Root cause, confirmed by tracing a full transcript** (`recursion-pass`):
this harness replays each scenario's fixed `student_turns` list, reusing the
*last* scripted turn verbatim for any round beyond what's scripted
(`run_scenario()` in `run_calibration.py`). `MockProvider` never asks more
than ~2 rounds, so the calibration set was written with 1-2 scripted answers
per scenario. A real reasoning model asks 3-4 substantively different
follow-ups per the concept protocol (§4.2's mandated deliberate-error
injection + first-principles probing). Once the script runs out of scripted
turns, it repeats a stale answer against a brand-new question — e.g. DeepSeek
asked why Fibonacci's naive recursion is exponential despite shrinking inputs,
and the "student" repeated its earlier answer about base cases verbatim,
which doesn't address the question. The Auditor correctly hits its forced-
convergence fallback (`达到最大追问轮次，系统强制裁决为未通过`) and fails
the scenario — this is the harness under-scripting a strong model's actual
follow-up depth, not the Auditor being wrong.

Task scenarios are unaffected (93.3% accuracy) because the task protocol caps
at 2 rounds (`task_max_turns=2`), matching the scripted depth.

**This is not yet a passing M2 result.** Fixing it requires either scripting
enough turns per concept scenario to survive a real model's full follow-up
depth (tedious, and still brittle against prompt/model changes), or replacing
canned `student_turns` with an LLM-played adaptive student — out of scope for
this pass. Flagging as the concrete next step before M2 can be marked
accepted rather than "code-ready."

**2026-07-19 update — that run is now stale**, superseded by the re-run below.
`app/agents/auditor.py`'s `CONCEPT_SYSTEM_PROMPT` was substantially rewritten
after the run above: the deliberate-error-injection rule (§4.2's "故意提出
一个看似合理但含有细微错误的理解") was removed entirely per user feedback
that it made the Auditor behave like a leading expert instead of a naive
Feynman-style listener, and the fixed per-mode turn cap told to the model was
removed in favor of the model deciding convergence itself (config's
`audit_max_turns`/`task_max_turns` are now a generous safety ceiling only,
not a quota stated in the prompt).

## Re-run (2026-07-20, `--provider deepseek`, naive-beginner + dynamic-turns prompt)

```
accuracy: 22/30 = 73.3%
leniency rate (false-pass among should-fail): 0/15 = 0.0%
  [concept] accuracy: 7/15 = 46.7%  leniency: 0/7 = 0.0%
  [task] accuracy: 15/15 = 100.0%  leniency: 0/8 = 0.0%
```

Leniency dropped to **0%** (from 6.7%) and task accuracy is now **100%**
(from 93.3%) — the naive-beginner rewrite made the Auditor stricter, not more
lenient, which is the direction that actually matters for "宁 fail 不放水".

Overall accuracy (73.3%) still misses the ≥80% bar, and concept accuracy
(46.7%) is numerically identical to the stale run — same root cause, entirely
unaffected by the prompt rewrite: **all 8 `-pass` concept scenarios still
fail**, for the exact reason diagnosed above (harness replays a scenario's
fixed `student_turns` list and repeats the *last* scripted answer verbatim
once it runs out; a real model's concept follow-ups still run longer than
what's scripted, so the harness feeds a stale answer against a fresh
question and the Auditor correctly hits forced-convergence-fail). The
dynamic-turns change if anything makes this worse to fix by re-scripting,
since there's no longer a fixed per-mode round count to script against —
the model decides its own depth per scenario.

**Still not a passing M2 result, and the blocker is unchanged from the
stale run**: the calibration harness's canned `student_turns`, not the
Auditor. Confirms the diagnosis rather than changing it — re-scripting more
turns per concept scenario (tedious, brittle) or an LLM-played adaptive
student (real fix, out of scope for this pass) remains the concrete next
step. What this re-run *does* establish: the prompt rewrite didn't
regress task-side behavior (perfect scores there) and got strictly stricter
on leniency, which was the one metric that already passed the M2 bar before
and still does, more comfortably now.
