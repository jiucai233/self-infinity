# Auditor calibration harness

Offline evaluation of `Auditor.next_turn` judgment quality against a hand-labeled
30-scenario calibration set (`calibration_set.json`), per WHITEPAPER.md §9 M2:
"接入 Gemini + 校准集 | 30 条校准集裁决准确率 ≥ 80%，放水率 ≤ 10%".

## Running

```
backend/.venv/bin/python backend/eval/run_calibration.py --provider mock
backend/.venv/bin/python backend/eval/run_calibration.py --provider gemini
```

`--provider mock` (default) runs offline with no API key, using the deterministic
`MockProvider` heuristic. `--provider gemini` requires `GEMINI_API_KEY` set in
`backend/.env` (see `app/config.py`), since it instantiates `GeminiProvider`
and makes real API calls for every scenario.

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

The M2 bar (accuracy ≥ 80%, leniency ≤ 10%) applies to `--provider gemini`
once a real `GEMINI_API_KEY` is configured. Run it that way to get the
number that actually gates the milestone.
