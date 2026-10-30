# Auditor calibration harness

Offline evaluation of `Auditor.next_turn` judgment quality against a hand-labeled
30-scenario calibration set (`calibration_set.json`), per docs/WHITEPAPER.md §8: accuracy ≥ 80%, leniency ≤ 10%.

## Running

```
backend/.venv/bin/python backend/eval/run_calibration.py                         # OpenAI, the Auditor's model
backend/.venv/bin/python backend/eval/run_calibration.py --out transcripts.json  # and keep every transcript
backend/.venv/bin/python backend/eval/run_calibration.py --provider mock         # offline
```

`--provider openai` (default) needs `OPENAI_API_KEY` in `backend/.env` and makes
real API calls for every scenario (about 150 calls, a few cents on `gpt-6-luna`); it uses the
Auditor's model (`LLM_MODEL_OVERRIDES`, then `LLM_MODEL`, then `gpt-6-luna`), the one the app
runs. `--provider mock` runs offline with no key, using the deterministic `MockProvider`
heuristic. The DeepSeek runs below are history from before the app moved to OpenAI.

Since 2026-10-13 a scenario runs the way production runs an audit
(`app/services/audit_flow.py`): the student opening, her turns fed back whole (feedback, then
question), a pass reviewed once by the Challenger and the answer to its question getting the
verdict. One run reports both arms: the verdict before the Challenger and the final one.

## What it measures

For each scenario, the script replays `student_turns` into a simulated audit
conversation (opening question, then probes) up to a safety cap of 10 rounds,
and compares the verdict's `passed` against the scenario's
`expected_passed` ground truth. It reports, before the Challenger and after it:

- overall accuracy (% of scenarios where actual verdict matches expected)
- leniency rate (放水率): among scenarios that SHOULD fail, the % that the
  Auditor incorrectly passed — this is the false-pass / grade-inflation risk
- both metrics broken down by `node_type` (concept vs task)

## Labels changed on 2026-10-15

The owner's decision: nobody recites commands, so an action said roughly counts as known even
when the exact command, option or amount is not remembered. Six task scenarios whose students
name the actions but not the details are now labelled pass (`python-venv-setup-fail`,
`mapo-tofu-blanch-tofu-fail`, `home-wifi-setup-fail`, `change-flat-tire-fail`,
`pour-over-coffee-ratio-fail`, `assemble-bookshelf-fail`; the ids keep their old names). Two stay
fail: `nginx-reverse-proxy-fail` and `crontab-backup-job-fail` name no action at all. The set
is now 21 pass / 9 fail.

| Auditor | accuracy | false pass | false fail |
|---|---|---|---|
| 2026-10-14 rules, four earlier runs rescored with the new labels | 24, 24, 22, 25 /30 | 0, 1, 1, 0 /9 | 6, 5, 7, 5 /21 |
| with the rule written in (a rough action is known), one run | 27/30 | 1/9 | 2/21 |

The rescored runs fail the relabelled scenarios; written into the task rule, they pass. The run
with the rule missed two concept passes and passed `nginx-reverse-proxy-fail`.

## Rules of 2026-10-30 (`gpt-6-luna`)

Three changes, `JUDGE_VERSION` 2026-10-30:

- **A "not given" gap needs the words that asked for it.** Production audit 36 (a Transformer
  node) was failed for "how the decoder uses the encoder's output" after the only question near
  it was "what do the encoder and the decoder each do, and what does the mask limit?", which the
  user answered right. The verdict called it `not_given` and cited that question. Now a
  `not_given` gap must also quote (`named`) the words of the question that name the missing
  thing; the code checks they are in that question and drops the gap otherwise, and the rule
  says a question on what each part does names nothing inside or between them. That audit
  judged again: the gap came back 5 of 12 times before (4 with the old notes, 4 more with
  them, 4 without), 0 of 8 after (4 and 4). Judging an audit again also no longer shows the old
  verdict's own notes as "what was wrong last time" (`app/services/rejudge.py`).
- **Depth 0 holds.** A hash-table node told to the expert at depth 0 was asked how collisions
  are handled (3 of 3 trials) and why a lookup is O(1) on average (2 of 3), and failed on it
  (2 of 3). The depth-0 rule now comes before the questioning rules, the expert no longer
  "listens for how it works", a depth-0 leaf is judged on what each part is and is for, and a
  gap about how a part works inside is kind `detail` (dropped by the code). After, 3 trials
  each: (expert, 0) asked what a collision is and what "on average" means, never how; 3 of 3
  passed. (student, 1) asked what happens when two keys share a bucket and why lookup is fast.
  (child, 2) also went one level down (how a key becomes a number, why the bucket's list is
  short).
- The calibration run after both:

| run | accuracy | false pass | false fail |
|---|---|---|---|
| 2026-10-30, one run | 28/30 | 1/9 (`nginx-reverse-proxy-fail`) | 1/21 (`mutex-deadlock-pass`) |

## A judge from another model family (2026-10-30)

The verdict is voted three times by one model (`audit_flow._voted`). To see whether another
family would add independent signal, the final verdict of each transcript of the run above was
judged again, on the same transcript: twice by `gpt-6-luna`, once by `deepseek-chat` (the
Gemini key was not set, so Gemini was not measured).

| judge | right | false pass | false fail |
|---|---|---|---|
| the run's own verdict (luna) | 28/30 | nginx | mutex-deadlock |
| luna again, 1 | 27/30 | nginx, crontab | mutex-deadlock |
| luna again, 2 | 26/30 | nginx, crontab | recursion, mutex-deadlock |
| deepseek-chat | 26/30 | none | hash-table, dynamic-programming, consistent-hashing, change-flat-tire |
| majority, luna x3 | 27/30 | 2/9 | 1/21 |
| majority, luna x2 + deepseek | 28/30 | 1/9 | 1/21 |

Every mistake of the run's verdict came back in both of luna's other judgements; deepseek's four
share none with any of luna's (it is stricter: no false pass, four false fails). One vote from
another family is therefore `AUDITOR_SECOND_PROVIDER` (empty by default: no change). One run of
30 items: the majority gained one item, read it as "the errors do not overlap", not as a size.

## Runs of 2026-10-13 (`gpt-6-luna`, the student Auditor)

| Auditor | run | accuracy before / after the Challenger | leniency before / after | false fail |
|---|---|---|---|---|
| before the gap rule changed | 1 | 27/30 / 28/30 | 2/15 / 1/15 | 1/15 |
| after | 1 | 30/30 / 30/30 | 0/15 / 0/15 | 0/15 |
| after | 2 | 29/30 / 29/30 | 0/15 / 0/15 | 1/15 |
| after | 3 | 26/30 / 26/30 | 3/15 / 3/15 | 1/15 |

After the change, over three runs: accuracy 85/90 = 94.4%, leniency 3/45 = 6.7%. **One run moves
between 87% and 100%, so this set does not tell the two Auditors apart.** Read a single run as
"within the bar or not", not as a number to compare. Where the movement comes from:

- The student's later answers are written by an LLM. Asked a follow-up, a "should fail" student
  sometimes produces a workable order of steps (make the environment, activate it, install,
  check for errors) while still saying it does not remember the commands.
- That is a pass by the Auditor's rule (a command one would look up is not required) and a fail
  by the labels of July (`python-venv-setup-fail`, `mapo-tofu-blanch-tofu-fail`,
  `assemble-bookshelf-fail`). The three labels need a decision: relabel, or make the scripted
  turns say they do not know the *actions*.
- The scripted second and third turns were written for the July question order and often do
  not answer what she asks now (`tcp-handshake-pass` failed once on exactly that).

What did tell the two apart: the 19 finished audits of one production account, each given to
the Auditor again four times for its verdict. Pass judgements 14/76 before, 18/76 after; the
audit that had passed at 95 on "I already did all of it" is asked what was done (4/4) instead of
passing (4/4); two claims that were right and had been held against the user no longer appear
in `gaps`. The cost: audits whose four verdicts disagree went from 1 to 5 of 19, all near the
line. That replay is not in this folder (it reads one user's data).

## Interpreting mock vs real results

`MockProvider` is a simple keyword/length heuristic (see `app/llm/mock.py`),
not real language understanding — it exists for fast offline tests, not for
judging genuine comprehension. Its accuracy on this calibration set is
**not** the M2 acceptance bar; it will misjudge scenarios whose surface
wording happens to trip its keyword checks in either direction.

The M2 bar (accuracy ≥ 80%, leniency ≤ 10%) applies to a real provider
(`--provider openai`). Run it that way to get the
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

## Adaptive student (2026-07-20, fixes the concept under-scripting root cause)

Implemented the fix flagged above: once a scenario's scripted `student_turns`
run out, `run_calibration.py` now hands the conversation to an LLM playing
the same student persona (`build_student_answer` / `STUDENT_SYSTEM_PROMPT`),
grounded in the scripted turns' tone/depth and the scenario's
`expected_passed` + `label_rationale`, instead of repeating a stale line.
On by default for real providers (`--no-adaptive-student` to disable,
`--adaptive-student` to force it on for `mock`). MAX_TURNS raised 6 → 10 to
comfortably clear `audit_max_turns=8`.

Two consecutive runs, `--provider deepseek`, same calibration set:

```
run 1: accuracy 24/30 = 80.0%   leniency 3/15 = 20.0%
  [concept] accuracy 12/15 = 80.0%  leniency 0/7  =  0.0%
  [task]    accuracy 12/15 = 80.0%  leniency 3/8  = 37.5%

run 2: accuracy 25/30 = 83.3%   leniency 2/15 = 13.3%
  [concept] accuracy 11/15 = 73.3%  leniency 1/7  = 14.3%
  [task]    accuracy 14/15 = 93.3%  leniency 1/8  = 12.5%
```

**The concept-side fix worked**: concept accuracy jumped from a stuck 46.7%
(both prior runs, all 8 `-pass` scenarios failing) to 73–80%, with most
`-pass` scenarios now correctly passing once the student can actually
answer follow-ups instead of stalling. This confirms the harness diagnosis
was right — it really was the scripted replay, not the Auditor.

**That surfaced a real leniency problem on the task side that the old
harness was masking.** Task leniency is now 37.5% and 12.5% across the two
runs (vs. 12.5%/0.0% under the stale, under-scripted harness) — both traced
to `-fail` task scenarios where the adaptive student, asked a genuine
follow-up, gave an answer that's imprecise-but-plausible enough (e.g.
"应该是192.168点什么的，具体记不清了" for a router admin address) that the
task protocol's intentionally-lenient rubric (§4.2: "回答具体、不是空话套话
…就通过") accepted it. Traced one instance (`home-wifi-setup-fail`) with a
one-off script outside the harness and got a *correct* fail on that trace —
so this reads as genuine run-to-run variance from two compounding stochastic
LLM calls (Auditor + student, both temperature > 0) landing right at a
judgment boundary, not a broken harness or a systematic Auditor bug. Prior
runs never exposed this because the old harness force-failed most concept
scenarios and only ever exercised 1-2 scripted task turns — it had no
opportunity to surface task-side leniency variance at all.

**Net read**: accuracy now clears the ≥80% bar on average across the two
runs (~81.7%), which the harness could never produce before this fix no
matter how good the Auditor was. Leniency is where the real signal now
is — averaging ~16.7%, above the ≤10% bar in both runs, concentrated in
task `-fail` scenarios with follow-up questions. This is the first
calibration run that can be trusted as actually representative of live
Auditor behavior rather than an artifact of the test harness; the concrete
next step is tightening the task protocol's leniency rule for
follow-up-round answers (or accepting more runs / an averaged multi-run
metric to separate genuine leniency from single-run variance) before
claiming M2 passing — not yet done, flagging as the next actionable item.

# Fact Keeper evaluation (memory consistency)

`run_memory.py` checks the lasting-fact list (contract #40) on the 16 scenarios in
`memory_set.json`, grouped like LongMemEval's abilities: extract, noise, update, end, keep
(daily talk leaves a fact alone) and no_guess (a condition the player did not name is never
written). Each scenario starts from an empty list and goes through the same `keep_facts` the app
runs: the Decisions gate, then the keeper. Matching is by keywords, so it checks behaviour, not
wording.

```
backend/.venv/bin/python backend/eval/run_memory.py                   # the app's model, gate on
backend/.venv/bin/python backend/eval/run_memory.py --no-gate         # keeper on every message
backend/.venv/bin/python backend/eval/run_memory.py --only update-knee
backend/.venv/bin/python backend/eval/run_memory.py --provider mock   # offline (keyword heuristic)
```

The real run makes about 22 Decisions calls and 17 keeper calls (a few cents). 2026-10-08,
gpt-6-luna with the gate: 16/16; the gate skipped 5 of 22 messages; ~42 s in all. The mock is a
regex heuristic for tests, not a score.
