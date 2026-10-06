# English strings (binding, 2026-10-02)

> **Languages (2026-10-06).** English is the default and the source; the app also speaks Chinese
> and Korean, picked in the ◎ menu or on the front page. Client strings live in
> `app/lib/l10n/app_{en,zh,ko}.arb` (the English ones are the strings below); the backend's fixed
> texts and reflection prompts in `backend/app/i18n.py`; LLM output follows the request's
> `Accept-Language` (api-contract §1). In Chinese, titles are quoted `「X」`; in Korean `“X”`, with
> sentences written so no particle follows a title. The Mock / Fake demo script stays English.

The whole product is English by default: client UI, backend replies, the Mock / Fake demo script, LLM output. Backend and client must use **exactly** these strings where listed; anything not listed is translated in the same voice.

**Voice**: short, warm, plain English, second person, no exclamation spam (one `!` at most per screen). Sentence case for labels and buttons. Quote titles with curly quotes `“X”` (replaces Korean `「X」`). Numbers as digits.

**Speech**: STT and TTS locale follow the app language: `en-US`, `zh-CN`, `ko-KR`.

---

## 1. Agents (display names, `ChatMessage.agent` → label)

| agent | label |
|---|---|
| front_desk | Guide |
| narrator | Narrator |
| recommender | Recommender |
| clarifier | Clarifier |
| planner | Planner |
| syllabus_finder | Syllabus Finder |
| material_finder | Material Finder |
| auditor | Auditor |
| challenger | Challenger |
| recorder | Recorder |
| linker | Linker |
| checkin_converter | Check-in |
| (user) | You |

## 2. Client UI

| where | string |
|---|---|
| Left panel title | `My character` |
| Level bar | `Lv {level} · {n}/5` |
| Cleared bar | `Cleared {mastered}/{total}` |
| Condition bar | `Condition: Good` · `Condition: Low` · `Condition: No record` |
| Today section | `Today` — rows `Sleep` (`{h} h`), `Meals`, `Journal`; empty value `—` |
| Settings tooltip | `Settings (coming soon)` |
| Chat panel title | `Chat` |
| Scene 4 panel title | `Attempts` |
| Scene 4-1 panel title | `Audit log` |
| Node status chips | `Locked` · `Ready` · `Cleared` · `Failed` |
| Audit result chips | `Passed` · `Failed` |
| Scene 1 greeting | no course: `What shall we learn today?` · with a course: `Continue with “{root title}”?` |
| Scene 1 subtitle | `Tap the crystal ball to open your life tree.` |
| Input placeholders | scene 1/5 `Message…` · scene 2 `Search nodes…` · scene 4 `Ask about this node…` · scene 4-1 `Explain it in your own words…` · reflection `What did you get wrong?…` |
| Voice status | `Listening…` · `Thinking…` · `Speaking…` |
| Scene 2 hint (avatar) | `Tap a node to take it on.` |
| Scene 2 title | the root node title |
| Legend | `Ready` · `Cleared` · `Failed` · `Locked` |
| Scene 4 contents | section labels `About` and `Resources`; source row prefix `Source:` |
| Scene 4 avatar | available/mastered: `Ready to try?` · locked: `Still locked. Clear “{parent}” first.` |
| Audit thinking | (shimmer, no text) |
| Audit fail bubble | `Not quite. {comment}` |
| Recorder question | `What did you misunderstand?` |
| After reflection | `Lesson card created.`; card labels `Lesson card`, `Misconception` |
| Pass bubble | `Cleared! {score} pts · +{xp} XP` |
| Celebration card | `Cleared!` · `{score} pts` · `+{xp} XP` · `Lv {a} → {b}` · `New nodes unlocked` · buttons `Close`, `Back to node` |
| Course action button | `Open life tree` |
| Upload chip / errors | `Uploading…` · `Only PDF, TXT or MD files up to 4 MB.` · `Couldn't read any text from this file.` |
| Generic errors | network: `Can't reach the server. Check your connection.` · 502: `Something went wrong on our side. Please try again.` · unknown: `Something went wrong.` · retry button `Try again` |
| Closed audit | `This audit has already ended.` + button `Back to map` |
| Not found page | `Page not found` + button `Go home` |
| Empty map | `No quest line yet` + hint `Tell the Guide what you want to learn.` |
| Dates in chat | `Oct 2, 2026`; times `11:04` (24 h, local time) |

## 3. Backend: suggestions (endpoint 20)

| rule | label | message |
|---|---|---|
| no check-in today | `How was your day?` | `Let me log my day` |
| continue (latest audit's node not mastered) | `Continue “{title}”` | same as label |
| start (lowest-id available node) | `Start with “{title}”` | same as label |
| no course | `Tell me what you want to learn` | `""` |

## 4. Backend: chat replies (endpoint 18)

| intent / event | message |
|---|---|
| none | `Sure. What would you like to do today?` |
| generate_course (front desk) | `I'll build a world for “{topic}”.` |
| generate_course empty topic | `What topic should I build?` |
| course created (planner) | `Your world “{root title}” is ready — {n} nodes.` |
| course failed | `I couldn't build that world. Please try again in a moment.` |
| open_skill | `Taking you to “{title}”.` |
| open_skill not found | `Which node do you mean? Tell me its name.` |
| checkin (front desk) | `Got it, logging that.` |
| checkin result | `Logged: sleep {h} h · exercise {yes/no} · meals {note} · focus {n}/5 · stress {n}/5` (only the fields found, joined by ` · `); nothing found: `I couldn't find anything to log. Tell me about sleep, exercise or meals.` |
| plan (front desk) | `Let me pick today's quests.` |
| plan result | `Today's quests: “A”, “B”, “C”.` |
| plan, no available node | `No node is ready yet. Make a world first.` |
| plan failed | `I couldn't pick today's quests. Please try again.` |
| briefing (front desk) | `Let me sum up where you are.` |
| briefing failed | `I couldn't put your status together. Please try again.` |
| open_map | `Opening your life tree.` |

## 5. Backend: audit (endpoint 7 opening questions, by position)

- leaf: `Explain “{title}” from scratch to someone who has never heard of it.`
- branch: `“{title}” covers {children}. Why do these belong together, and when do you use which?` — `{children}` joined by `, `
- root: `Which problems call for “{title}”, and which don't? How do you decide?`
- task: `How exactly will you do “{title}”?`

## 6. Mock / Fake demo script (contract §4, English version)

**Clarifier**: topic containing `statistics` (or `통계`) → one question `Do you mean high-school probability and statistics, or university-level statistics?`

**Course for a topic containing `math` (case-insensitive; `수학` still accepted)**:

| # | slug | title |
|---|---|---|
| 1 | high-school-math | High School Math |
| 2 | algebra | Algebra |
| 3 | functions | Functions |
| 4 | calculus | Calculus |
| 5 | quadratic-equation | Quadratic Equations |
| 6 | discriminant | Discriminant |
| 7 | root-coefficient | Roots and Coefficients |
| 8 | sequences | Sequences |
| 9 | linear-function | Linear Functions |
| 10 | quadratic-function | Quadratic Functions |
| 11 | sequence-limit | Limits of Sequences |
| 12 | derivative | Derivatives |

Structure unchanged. Requires reasons: 5→10 `The x-intercepts of a quadratic function are the roots of a quadratic equation.`; 9→10 `You need the graph of a linear function first.`; 11→12 `The derivative is defined as a limit.` Syllabus source `High School Mathematics Curriculum (Ministry of Education)`. Descriptions: one plain English sentence each.

Generic course: root = topic (first line, at most 48 chars, cut at a word boundary); branches `Core Concepts`, `Key Methods`, `Applications`; leaves `Core Concepts 1`, `Core Concepts 2`, …; requires `Core Concepts 1 → Key Methods 1`, `Key Methods 1 → Applications 1`.

**Audit**: first user turn → probe `Pick the most important term in your explanation and tell me what it means and why it matters.` With a retrieved lesson: `You once thought “{misconception}”. How is this explanation different?` Later turns → verdict: pass if `n ≥ 80` characters and the latest answer does not contain `don't know` / `not sure` (or Korean `모르`); pass comment `You explained the core idea and why it holds.`; fail score 45, gaps `You stated the definition but not why it works.`, `You didn't cover the exceptions.`, comment `The answer stops at the conclusion and lacks reasons.` Challenger overturn (n < 160): `Before I pass this: give one case where this idea does not hold, and explain why.`

**Recorder**: title `Revisit “{title}”` (cut to 40), body `When I explain “{title}”, I give the reason before the conclusion.` (cut to 120), misconception = the reflection (cut to 60). **Linker** reason `Same concept, similar misconception`.

**Check-in Converter (English parsing)**: `sleep_hours` = a number (digits or `one`…`twelve`) followed by `hour(s)`/`h` near `sleep`/`slept`; `exercised` false for `didn't exercise|no exercise|skipped (the )?gym|didn't work out`, true for `exercised|worked out|went to the gym|went for a run`; `diet_note` = `(breakfast|lunch|dinner)` + the food words after `had|ate` (e.g. `had ramen for lunch` → `lunch: ramen`); `focus` 4 for `focused well`, 2 for `couldn't focus`; `stress` 4 for `stressed|a lot of stress`, 2 for `relaxed|no stress`. Nothing else inferred (`tired` sets nothing). Korean rules may stay as a fallback.

**Front desk (Mock)**, first match wins:
- a node title contained in the message (case-insensitive) **and** `challenge|audit|try|open|continue|start` → `open_skill` (longest matching title wins)
- `sleep|slept|tired|exercise|worked out|ate|had .* for (breakfast|lunch|dinner)|log my day|my day` → `checkin`
- `learn|study|build|make|create|teach me` → `generate_course`; topic = the message minus a leading `I want to learn|I'd like to learn|I want to study|teach me|build me a world (for|about)|make a world (for|about)` and trailing punctuation; with uploads, `this|this file|these` count as no topic
- `quest|what should i|recommend` → `plan`
- `status|report|how am i doing` → `briefing`
- `map|world` → `open_map`
- else `none`

**Narrator**: `You've cleared {mastered} of {total} nodes.` + per cluster `The misconception “{label}” showed up {n} time(s) in {skills}.` (`1 time` / `{n} times`) + `Average sleep over the last day: {h} h.` / `… over the last {n} days: {h} h.` when known.
**Recommender**: rationale `Prerequisites checked — you can take this on now.`; focus hint `Explain the why before the definition.`
**Material Finder**: queries `["{skill title} {gap first 30 chars}", "{skill title} explained"]`; reason `Covers this gap directly.`
**Mock search** result titles in English (e.g. `“{query}” — resource 1`).

## 7. LLM prompts

Every agent prompt asks for **English** output (remove "Korean", "해요체", Korean examples). Prompt instructions stay as they are otherwise; the `[agent: name]` tag stays first.
