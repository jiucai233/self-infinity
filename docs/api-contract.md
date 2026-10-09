# API Contract

The single source of truth for the backend (FastAPI) and the client (Flutter).
It expands Section 6 of the development plan into exact JSON shapes. Where Section 6 is silent, the shape below is binding.
Fields marked **(added)** are additive to Section 6 and exist because a screen cannot work without them.

Related plan sections: 4 (course structure), 5 (schema), 6 (API), 7.4 (agents), 8 (boundaries), 17.2–17.3 (templates, messages).

---

## 1. Conventions

- Base path: `/api`. Local base URL: `http://127.0.0.1:8000/api`.
- Bodies are JSON, UTF-8.
- **GET endpoints never call the LLM** (AD-1). Every POST that calls the LLM persists its result before responding.
- Datetimes: ISO 8601 in UTC **with an explicit offset**, e.g. `"2026-10-05T03:12:45Z"` or `"2026-10-05T03:12:45+00:00"`. Clients convert to KST (`Asia/Seoul`) for display.
- Dates: `"YYYY-MM-DD"`. `DailyCheckIn.date` is the KST calendar date.
- Errors: status code + body `{"detail": "<message>"}`. Messages are listed in Section 6 below.
  422 uses FastAPI's default body (`detail` is a list); clients show a generic message for 422.
- CORS: any `http://localhost:*` and `http://127.0.0.1:*` origin is allowed (Flutter web dev server).
- Enum values are lower-case strings exactly as written here.
- **Language.** The client sends `Accept-Language: en | zh | ko` (its UI language) on every request. The backend writes its fixed texts (chat replies, suggestions, audit opening questions, reflection prompts) and asks every agent for learner-facing text in that language; ids, slugs and enum values stay English. Missing or unknown → English. Stored content (course titles, lessons) keeps the language it was made in. Error `detail` messages are always English; clients translate the known ones. A journal entry answers a reflection window whichever language its prompt was in.

---

## 2. Shared types

### Course
```json
{"id": 1, "topic": "Math", "source_course": null, "source_url": null, "created_at": "2026-10-05T03:00:00Z"}
```
`topic` is the text sent to `/skills/generate`, including clarification answers (Section 5.1). Clients display only its first line.
`source_course` / `source_url` are both null or both set, except for a course made from an uploaded file: `source_course` = file name, `source_url` = null. `created_at` **(added)**.

### SkillNode
```json
{"id": 5, "course_id": 1, "slug": "quadratic-equation", "title": "Quadratic Equations",
 "description": "...", "status": "available", "node_type": "concept", "mastery_score": null,
 "unexpanded": false, "tested_out": false, "linked_course_id": null}
```
- `status`: `locked` | `available` | `mastered`
- `node_type`: `concept` | `task`
- `mastery_score`: integer 0–100 or null; written when an audit passes.
- `unexpanded` **(added 2026-10-08)**: a category whose parts are not all listed yet: the Planner left it to break down later (no children), or a syllabus (endpoint 45) or the player (endpoint 43) added only some of them **(2026-10-09)**. Break it down with endpoint 38 (it adds the rest), or challenge it as a whole (endpoint 7, `test_out`). It cannot be audited on its own.
- `tested_out` **(added 2026-10-08)**: mastered by passing a challenge on a node above it, not by its own audit.
- `linked_course_id` **(added 2026-10-09)**: this node is another of the player's courses (“Computer Vision” inside a CS course), or null. Its parts are that course's tree, so it has no children of its own and is not broken down (38) or audited (7: 400 `This node is another course: learn it there.`); it is mastered with that course (endpoint 44).

### SkillEdge
```json
{"from_id": 2, "to_id": 5, "kind": "contains", "is_primary": true, "reason": null}
```
- `kind: "contains"` — `from_id` is the parent, `to_id` the child. `is_primary` is `true` for the main parent, `false` for the others. `reason` is null.
- `kind: "requires"` — `from_id` is learned first, `to_id` after. `is_primary` is null. `reason` is a sentence or null.

**Node position** (computed by clients from contains edges, and by the backend at audit start):
no contains parent → `root`; contains parent but no contains child → `leaf`; otherwise `branch`.

### AuditSession
```json
{"id": 31, "skill_id": 5, "node_position": "leaf", "status": "active", "score": null,
 "gaps": [], "comment": null,
 "turns": [{"role": "auditor", "content": "Explain “Quadratic Equations” from scratch to someone who has never heard of it."}],
 "test_out": false}
```
- `test_out` **(added 2026-10-08)**: a challenge on a whole branch (endpoint 7).
- `node_position`: `root` | `branch` | `leaf`. (The example copies plan 6.3, where Quadratic Equations is a leaf. In the Section 4.2 demo course it has children, so there it is a `branch` and gets the branch opening question.)
- `status`: `active` | `passed` | `failed`
- `turns[].role`: `user` | `auditor`. The opening question is the first auditor turn.

### TurnResult — exactly one of two shapes
Probe:
```json
{"type": "probe", "question": "What is the discriminant, and why does a negative one mean no real solutions?"}
```
Verdict:
```json
{"type": "verdict", "passed": false, "score": 45, "gaps": ["..."], "comment": "...",
 "unlocked_skill_ids": [], "reward_amount": null, "reward_multiplier": null}
```
- A Challenger overturn is returned as a **probe** whose `question` is the Challenger's question.
- On a pass: `unlocked_skill_ids` lists nodes that changed from locked to available; `reward_amount` (int) and `reward_multiplier` (float) are set. On a fail both reward fields are null and `unlocked_skill_ids` is `[]`.
- A probe response contains only `type` and `question`.

### Principle
```json
{"id": 7, "title": "State the number set first",
 "body": "When I state a solution to an equation, I first say which number set it is over.",
 "misconception": "Thought no real roots meant no solutions at all",
 "source_session_id": 31, "skill_id": 5, "skill_title": "Quadratic Equations",
 "created_at": "2026-10-05T03:20:00Z"}
```
`skill_id`, `skill_title`, `created_at` **(added)**: the node the source audit was about. Limits: title ≤40, body ≤120, misconception ≤60 characters.

### DailyCheckIn
```json
{"date": "2026-10-05", "sleep_hours": 6, "exercised": false, "diet_note": "lunch: ramen",
 "focus": null, "stress": null, "transcript": "I slept about six hours last night ...", "source": "voice",
 "sleep_quality": null, "exercise_minutes": null, "weight_kg": null}
```
Ranges: `sleep_hours` 0–14, `focus` 1–5, `stress` 1–5; each may be null. `source`: `voice` | `manual`.
`sleep_quality` (1–5), `exercise_minutes` (0–600), `weight_kg` (20–400, one decimal) **(added 2026-10-08)**: kept for trends (endpoint 39) when said or typed, never asked for, so they are never in `missing_fields`. Minutes of exercise mean `exercised: true`. No calories, no meals counted: `diet_note` stays a note.

### ProfileFacts
```json
{
  "nodes": {"total": 12, "mastered": 4, "available": 3, "locked": 5},
  "audits": {"total": 6, "passed": 4, "failed": 2},
  "misconception_clusters": [
    {"label": "No real roots means no solutions", "occurrences": 2,
     "skills": ["Quadratic Equations", "Quadratic Functions"], "cross_skill": true, "principle_ids": [7, 9]}
  ],
  "condition": {"days": 3, "avg_sleep_hours": 5.3, "avg_stress": null, "flag": "low"}
}
```
- `audits` and `principle_ids` **(added)**.
- `condition` uses the last 3 check-ins. `flag`: `low` if average sleep < 6 h, average stress ≥ 4 or average focus ≤ 2 (focus **added 2026-10-08**); `unknown` with no check-ins; else `normal`. `days` = number of check-ins used (0–3).

### Briefing
```json
{"facts": { ...ProfileFacts... }, "narrative": "You've cleared 4 of 12 nodes. ...",
 "narrative_generated_at": "2026-10-05T03:30:00Z"}
```
`narrative` and `narrative_generated_at` are null until the first narration.

### StudyPlan
```json
{"id": 3, "suggested_tier": "medium", "context_bucket": "mid", "created_at": "2026-10-05T03:31:00Z",
 "steps": [{"skill_id": 9, "course_id": 1, "skill_title": "Quadratic Functions", "node_type": "concept",
            "rationale": "...", "focus_hint": "..."}]}
```
3–5 steps, in study order. `steps[].course_id` **(added)**.

### SearchPlan
```json
{"id": 2, "skill_id": 5, "gap": "Could not explain the solutions when the discriminant is negative",
 "queries": ["discriminant negative complex roots", "quadratic negative discriminant complex roots"],
 "items": [{"title": "...", "url": "https://...", "snippet": "...", "reason": "..."}],
 "created_at": "2026-10-05T03:40:00Z"}
```
At most 3 items. Every `url` comes from a search result, never from the model (AD-5).

### Graph
```json
{"nodes": [{"id": "skill:5", "kind": "skill", "title": "Quadratic Equations", "status": "mastered",
            "node_type": "concept", "course_id": 1},
           {"id": "principle:7", "kind": "principle", "title": "State the number set first",
            "status": null, "node_type": null, "course_id": null}],
 "edges": [{"source": "skill:2", "target": "skill:5", "kind": "contains", "reason": null},
           {"source": "skill:5", "target": "skill:10", "kind": "requires", "reason": "..."},
           {"source": "principle:7", "target": "skill:5", "kind": "origin", "reason": null},
           {"source": "principle:9", "target": "principle:7", "kind": "related", "reason": "..."},
           {"source": "principle:9", "target": "principle:4", "kind": "contradicts", "reason": "..."}]}
```
Edge directions: contains parent→child; requires first→after; origin principle→skill it arose on; related principle→principle or skill; contradicts principle→principle.

---

## 3. Endpoints

| # | Method | Path | LLM |
|---|---|---|---|
| 1 | POST | `/api/skills/clarify` | Yes |
| 2 | POST | `/api/skills/generate` | Yes |
| 3 | GET | `/api/courses` | No |
| 4 | GET | `/api/courses/{id}/map` | No |
| 5 | GET | `/api/skills?course_id=` | No |
| 6 | GET | `/api/skills/recommendation` | No |
| 7 | POST | `/api/skills/{id}/audits` | No |
| 8 | POST | `/api/audits/{id}/turns` | Yes |
| 9 | POST | `/api/audits/{id}/reflection` | Yes |
| 10 | GET | `/api/principles` | No |
| 11 | GET | `/api/graph` | No |
| 12 | POST | `/api/checkins` | Voice only |
| 13 | GET | `/api/narrator/briefing` | No |
| 14 | POST | `/api/narrator/narrate` | Yes |
| 15 | POST | `/api/plan/generate` | Yes |
| 16 | GET | `/api/plan/current` | No |
| 17 | POST | `/api/skills/{id}/search-plan` | Yes |

No other endpoint is part of the contract. `/api/graph/relink`, `/api/vitality` and `/api/focus/latest` are removed.

### 1. `POST /api/skills/clarify`
Request `{"topic": "Statistics"}` — topic not blank (422).
Response `{"needs_clarification": true, "questions": ["Do you mean high-school probability and statistics, or university-level statistics?"]}` — at most 2 questions.
Failure of the Clarifier is not an error: respond `{"needs_clarification": false, "questions": []}`.

**Client rule — passing answers to generation.** The client appends answers to the topic it sends to `/skills/generate`:
```
{topic}

Q: {question 1}
A: {answer 1}
```
(one `Q:`/`A:` pair per answered question). Unanswered questions are omitted.

### 2. `POST /api/skills/generate`
Request:
```json
{"topic": "Math", "difficulty": "standard", "search_syllabus": true}
```
Validation (422): topic not blank; `difficulty` `intro`|`standard`|`deep` (default `standard`); `search_syllabus` bool (default true). `node_count` / `max_depth` **(removed 2026-10-08)** are ignored if sent: a course is as big as its topic.
**Size and layers**: there is no limit on the number of nodes or levels, only on the smallest unit: a leaf is one model, method, algorithm, theorem or technique (“Quadratic Functions”, “CNN”, “Soft Actor-Critic”), in the humanities one concept. **With a syllabus** **(2026-10-09)** — one found (`search_syllabus`) or a file uploaded through the chat — its items are already the nodes a real course defined, so they are the first level as they are: one node per item, in its order, titled as the item (shortened only to fit). The Planner leaves out only what is not a topic (introduction, review, exam, project) and joins an item given in parts (I, II); it merges, splits, renames and adds nothing on that level. When a found syllabus's item is missing from the first level (a first-level title holds fewer than half of its words), the Planner is asked once more, naming the items; its second answer is kept either way. An introductory syllabus thus gives a course of mid-level nodes, each broken down later if wanted. Without one, one Planner call writes at most 30 nodes, level by level: the root and every main area, and a deeper level only when all of it fits; a category it cannot break down within that budget is saved with `unexpanded: true` and broken down later (endpoint 38, up to 40 nodes a call). Every answer keeps whole levels only: below the first level holding an `unexpanded` category nothing is kept, and every category on that level is saved `unexpanded` (a model tends to put a few sample leaves under some categories, and a category with children counts as finished). A safety stop keeps a course under 500 nodes.
Response: `{"course": Course, "nodes": SkillNode[], "edges": SkillEdge[]}`. **Unlocking**: the root's children are chapters, and the player picks the chapter. Each chapter has one `available` node, the first of it in the learning order that is not mastered (a chapter not broken down yet is its own first node); the root opens once every chapter is mastered; everything else is `locked`. The learning order lays a list over the tree: what a node contains comes before it (so the root comes last), a requires edge puts its prerequisite first, and otherwise the planner's order decides.
**The same course asked for again** **(2026-10-09)**: before anything is planned, the topic is matched against the player's courses: an exact title or topic (case, punctuation and bracketed asides aside) is that course; otherwise the three nearest by embedding (`text-embedding-3-small`) are put to the Decisions API (“is it one of these, under any name or language? a broader or narrower subject is not”), and a choice at confidence ≥ 0.6 is that course. Then nothing new is built: with a reference (a syllabus found, or a file) what it adds goes into that course as endpoint 45 does; without one the course answers unchanged. The response then has `merged: true` and `added` (nodes added); otherwise `merged: false`, `added: 0`. Without an OpenAI key only the exact match applies.
Errors: 502 `Course generation failed. Please try again.`

### 3. `GET /api/courses`
Response: `Course[]`, newest first.

### 4. `GET /api/courses/{id}/map`
Response: `{"course": Course, "nodes": SkillNode[], "edges": SkillEdge[]}` — all nodes of the course ordered by id, all edges of both kinds.
Errors: 404 `course not found`.

### 5. `GET /api/skills?course_id={id}`
Response: `SkillNode[]` ordered by id. Without `course_id`: all nodes of all courses.

### 6. `GET /api/skills/recommendation`
Response:
```json
{"context_bucket": "mid", "suggested_tier": "medium", "skill_tiers": {"1": "easy", "5": "medium"}}
```
`context_bucket`: `low`|`mid`|`high`. Tiers: `easy`|`medium`|`hard`. `skill_tiers` has one entry per skill node; keys are skill ids as strings.

### 7. `POST /api/skills/{id}/audits`
Request `{"mode": "day", "test_out": false}` — `mode` `day`|`night`, default `day` (422 otherwise).
**`test_out: true` — a challenge** **(added 2026-10-08)**: on a branch, a root or an unexpanded node, the player says they already know the whole area. The Auditor samples three of the smallest units under it (up to 12 are listed to it; for an unexpanded node, its description) and asks one per question, then how two relate; one part not known fails it. Opening: `So you already know “{title}”. Prove it, one part at a time. Start with “{first part}”: how does it work?`, or, with no parts yet, `So you already know “{title}”. Prove it: what are its main parts, and how does the most important one work?`. It always gets a concept's turn limit. Allowed on locked nodes (that is what it is for), not on a leaf (400 `Only a branch or a whole course can be challenged.`) or a mastered node (400 `skill is already mastered`). A pass masters the node (`mastery_score`) and every node under it not yet mastered (`tested_out: true`), then unlocks as usual; a fail changes nothing.
Response `{"session": AuditSession, "opening_question": "..."}`.
- Opening question by position (Section 17.2), in English:
  - leaf: `Explain “{title}” from scratch to someone who has never heard of it.`
  - branch: `“{title}” covers {children}. Why do these belong together, and when do you use which?` — `{children}` = contains-children titles joined by `, `
  - root: `Which problems call for “{title}”, and which don't? How do you decide?`
  - task node (any position): `How exactly will you do “{title}”?`
- Turn limit: concept 8, task 4; `night` doubles it. Stored in `max_turns`, never shown to the model.
- Allowed on `available` and `mastered` nodes, even with unmet requires; not on an `unexpanded` node (400 `Break this node down first, or challenge it as a whole.`).

Errors: 404 `skill not found`; 400 `skill is locked`.

### 8. `POST /api/audits/{id}/turns`
Request `{"content": "..."}` — not blank (422).
Response: `TurnResult`. Behavior follows Section 6.6 and 8.4:
- The user turn is saved before the Auditor is called (kept even if the Auditor fails). If the last saved turn is a user turn with no reply after it (the previous attempt failed, or the client stopped waiting), the new content **replaces** it instead of adding a second user turn, so a resend never uses up the turn limit.
- Memory Retriever passes ≤3 lessons to the Auditor.
- Pass + Challenger enabled + not yet challenged → Challenger. Overturn → `challenged = true`, its question saved as an auditor turn and returned as a probe. Uphold or Challenger error → final pass.
- Final pass: session `passed`, `score` saved, node `mastered` with `mastery_score`, the next node of its chapter in the learning order that is not mastered → `available` (one open node per chapter, endpoint 2), reward recorded.
- Fail: session `failed`, gaps and comment saved; node status unchanged.
- **Final turns** — the turn limit is reached, or this answer replies to the Challenger's question: the Auditor's prompt gets the line `This is the final turn: give the verdict now, do not ask another question.` (only on these turns; the limit itself is still never shown). If it probes anyway → forced verdict `passed=false`, `score=0` (comment names the limit, or the follow-up question after a challenge). If its output is unusable (not JSON or the wrong shape after the JSON retry) → 502, nothing is decided, and the user resends.
- Finalizing closes the session with one conditional update (`WHERE status = 'active'`): of two concurrent requests only one finalizes; the other gets 400 `audit session is already closed`, so rewards and bandit updates are never recorded twice.
- `score` is 0–100 (how much of the node the explanation got right). It is shown to the user; it does not decide `passed`.

Errors: 404 `audit session not found`; 400 `audit session is already closed` (also when another request finalized it first); 502 `The auditor is temporarily unavailable. Please try again.`

### 9. `POST /api/audits/{id}/reflection`
Request `{"reflection": "..."}` — not blank (422).
Response: `Principle`. The Recorder runs, the principle is saved, the response is sent, and **then** the Linker runs in the background.
Errors: 404 `audit session not found`; 400 `reflection is only accepted for a failed audit` (session not failed); 400 `reflection already submitted for this audit` (a principle already exists for the session); 502 `Principle extraction failed. Please try again.`

### 10. `GET /api/principles`
Response: `Principle[]`, newest first.

### 11. `GET /api/graph`
Response: `Graph` (all courses).

### 12. `POST /api/checkins`
Request — **one of**:
- Voice: `{"transcript": "I slept about six hours last night and didn't exercise. I had ramen for lunch and I'm a bit tired."}` → Check-in Converter (LLM), `source: "voice"`.
- Manual: any subset of `{"sleep_hours": 6, "exercised": false, "diet_note": "lunch: ramen", "focus": 3, "stress": 2, "sleep_quality": 4, "exercise_minutes": 30, "weight_kg": 71.5}` → no LLM, `source: "manual"`.

Validation (422): transcript, if present, not blank; numeric ranges as in DailyCheckIn; a body with neither a transcript nor any field.
If `transcript` is present, the structured fields are ignored.
Response:
```json
{"checkin": DailyCheckIn, "missing_fields": ["focus", "stress"]}
```
`missing_fields` = the null fields, in the order `sleep_hours, exercised, diet_note, focus, stress`.
One record per KST day. A said check-in (`transcript`, chat, the voice Guide) **fills in** the day: the fields it found overwrite, the others stay, and its words are added to the day's `transcript` (a re-sent transcript that starts with the day's is kept once). A manual check-in (structured fields) **replaces** the day's record. Fields are never copied from earlier days. The converter counts bed and wake times as said ("slept from 11 to 7" is 8 hours).

**Client rule — follow-up.** When `missing_fields` is not empty after a voice check-in, the client asks one follow-up question, then re-posts `{"transcript": "{previous transcript}\n{answer}"}`. The replaced record is final; no second follow-up.

Converter failure is not an error: all fields null, transcript kept, `missing_fields` lists all five.

### 13. `GET /api/narrator/briefing`
Response: `Briefing`. Facts are always computed fresh; the narrative is the cached latest one.

### 14. `POST /api/narrator/narrate`
Response: `Briefing` with a new narrative (≤400 characters).
Errors: 502 `Briefing generation failed. Please try again.`

### 15. `POST /api/plan/generate`
Response: `StudyPlan`.
Errors: 400 `No node is available yet. Generate a course or pass an existing node first.`; 502 `Plan generation failed. Please try again.`

### 16. `GET /api/plan/current`
Response: the latest `StudyPlan`, or `null`.

### 17. `POST /api/skills/{id}/search-plan`
Request: `{"gap": "..."}` or `{"misconception_id": 7}`.
Response: `SearchPlan`.
Errors: 400 `A gap or misconception id is required. Search targets a specific gap only.`; 404 `skill not found`; 404 `misconception not found` (principle missing or its misconception empty); 502 `Material search failed. Please try again.`

---

## 4. Offline demo behavior (Mock LLM + Mock Search)

Both the backend Mock providers and the Flutter `FakeApiClient` follow this script, so the acceptance scenario (plan Section 1.3) runs offline and the UI behaves the same with or without the backend.

### 4.1 Clarifier
- Topic containing `statistics` (case-insensitive; the Korean `통계` is still accepted) → one question: `Do you mean high-school probability and statistics, or university-level statistics?`
- Any other topic → no clarification.

### 4.2 Course for a topic containing `math` (12 nodes, any settings)

Case-insensitive; the Korean `수학` is still accepted.

| # | slug | title | contains parents (first = main) | type |
|---|---|---|---|---|
| 1 | high-school-math | High School Math | — (root) | concept |
| 2 | algebra | Algebra | 1 | concept |
| 3 | functions | Functions | 1 | concept |
| 4 | calculus | Calculus | 1 | concept |
| 5 | quadratic-equation | Quadratic Equations | 2 | concept |
| 6 | discriminant | Discriminant | 5 | concept |
| 7 | root-coefficient | Roots and Coefficients | 5 | concept |
| 8 | sequences | Sequences | 2 | concept |
| 9 | linear-function | Linear Functions | 3 | concept |
| 10 | quadratic-function | Quadratic Functions | 3 | concept |
| 11 | sequence-limit | Limits of Sequences | 4, 8 | concept |
| 12 | derivative | Derivatives | 4 | concept |

requires edges: 5 → 10 `The x-intercepts of a quadratic function are the roots of a quadratic equation.`; 9 → 10 `You need the graph of a linear function first.`; 11 → 12 `The derivative is defined as a limit.`.
Positions: root 1; branches 2, 3, 4, 5, 8; leaves 6, 7, 9, 10, 11, 12. Node 11 has two parents.
With `search_syllabus: true` the syllabus is found: `source_course` = `High School Mathematics Curriculum (Ministry of Education)`, `source_url` = the first mock search result URL.

Any other topic → a generic course: root = topic (first line, through the Planner's title cap: at most 48 characters, cut at a word boundary); branches `Core Concepts`, `Key Methods`, `Applications`; two leaves each (`Core Concepts 1`, `Core Concepts 2`, …); requires `Core Concepts 1 → Key Methods 1`, `Key Methods 1 → Applications 1`; not found as a syllabus.

### 4.3 Audit
Let `answers` = all user turns of the session joined together, `n` = its character count.
- **First user turn** → probe. If the Memory Retriever returned lessons, the probe refers to the most recent one:
  `You once thought “{misconception}”. How is this explanation different?`
  Otherwise: `Pick the most important term in your explanation and tell me what it means and why it matters.`
- **Later turns** → verdict. Pass if `n ≥ 80` and the latest answer does not contain `don't know` / `not sure` (case-insensitive; the Korean `모르` is still accepted); otherwise fail.
  - pass: `score = min(95, 70 + n // 10)`, `gaps = []`, `comment = "You explained the core idea and why it holds."`
  - fail: `score = 45`, `gaps = ["You stated the definition but not why it works.", "You didn't cover the exceptions."]`, `comment = "The answer stops at the conclusion and lacks reasons."`
- **Challenger**: overturn if `n < 160` (and not yet challenged) with `Before I pass this: give one case where this idea does not hold, and explain why.`; otherwise uphold.

So: a short answer fails; a medium answer is challenged once and then passes; a long answer passes at once.

### 4.4 Recorder and Linker
- Recorder: `title` = `Revisit “{skill title}”` cut to 40; `body` = `When I explain “{skill title}”, I give the reason before the conclusion.` cut to 120; `misconception` = the reflection cut to 60.
- Linker: one `related` link to the most recent other principle, if any, reason `Same concept, similar misconception`.

### 4.5 Check-in Converter
- `sleep_hours`: a number (digits, or the words `one` … `twelve`) followed by `hour` / `hours` / `hr` / `hrs` / `h`, in a sentence that mentions `sleep` / `slept` (e.g. `slept about six hours`).
- `exercised`: false for `didn't exercise` / `did not exercise` / `no exercise` / `skipped (the) gym` / `didn't work out` / `did not work out`; true for `exercised` / `worked out` / `went to the gym` / `went for a run`.
- `diet_note`: `(breakfast|lunch|dinner)` + the food words after `had` / `ate` → e.g. `had ramen for lunch` → `lunch: ramen` (also `for lunch I had ramen`).
- `focus`: `focused well` → 4; `couldn't focus` → 2. `stress`: `stressed` / `a lot of stress` → 4; `relaxed` / `no stress` / `not stressed` → 2.
- Nothing else is inferred (`tired` sets nothing).
- The original Korean rules (`시간`, `운동`, `집중`, `스트레스`, …) are kept as a fallback for any field the English rules left empty.

### 4.6 Narrator, Recommender, Material Finder
- Narrator: `You've cleared {mastered} of {total} nodes.` + one sentence per cluster (`The misconception “{label}” showed up {occurrences} times in {skills joined by ', '}.`) + `Average sleep over the last {days} days: {avg_sleep_hours} h.` when known. Cut to 400.
- Recommender: the first 3–5 available nodes by id (leaves first when the condition flag is `low`); rationale `Prerequisites checked — you can take this on now.`; focus_hint `Explain the why before the definition.`
- Material Finder: queries `["{skill title} {gap first 30 chars}", "{skill title} explained"]`; the first 3 mock search results, reason `Covers this gap directly.`

---

## 5. Stage UI additions (endpoints 18–23, added 2026-10-01, not in plan §6 yet)

The client is a three-column "stage" (`docs/ux-chat.md`): left = character stats + today's summary, middle = avatar + current scene, right = history. These endpoints feed it. **AD-7 still holds**: the front desk agent only classifies a chat message; code runs the existing pipelines. **Audits never start from chat** — they start from a node (endpoint 7).

### ProfileFacts — `xp` (added)
```json
"xp": {"total": 220, "level": 2, "level_progress": 0.4}
```
`total` = sum of all rewards. `level` = mastered nodes // 5 + 1 (the same level the incentive engine uses; starts at 1). `level_progress` = (mastered nodes % 5) / 5.

### ChatMessage
```json
{"id": 12, "role": "assistant", "content": "...", "agent": "front_desk",
 "action": null, "created_at": "2026-10-05T03:00:00Z"}
```
- `role`: `user` | `assistant`. `agent` is null for user messages.
- `agent` (assistant): `front_desk` | `narrator` | `recommender` | `planner` | `checkin_converter`. The client picks the avatar by this name.
- `action`: null or one of:
  - `{"type": "course", "course": Course, "node_count": 12}`
  - `{"type": "checkin", "result": CheckInResult}` (the response body of endpoint 12)
  - `{"type": "plan", "plan": StudyPlan}`
  - `{"type": "briefing", "briefing": Briefing}`
  - `{"type": "navigate", "scene": "map" | "skill", "skill_id": 5}` — `skill_id` only for `skill`.

### 18. `POST /api/chat`  (LLM: front desk, plus whatever the intent runs)
Request `{"message": "I want to learn Math", "upload_ids": [3]}` — `message` not blank (422); `upload_ids` optional, each must exist (404 `upload not found`).
**With `course_topic`** (the first-run tutorial): `{"message": "I want to learn Math", "course_topic": "Math"}` builds a course on that topic straight away and **does not call the front desk**, so the result never depends on how the message would be classified. Messages: user, `I'll build a world for “{topic}”.` (agent `front_desk`), then the `generate_course` result (or its failure message). `course_topic` (≤120 characters) may be blank only with `upload_ids` (the topic is then the first file's name); blank without uploads → 422 and nothing is saved.
**With uploads**: if the intent is `generate_course` or `none`, code generates a course from the uploaded file(s) instead (topic = `args.topic` or the first file's name without extension; the file text replaces the Syllabus Finder result). The course gets `source_course` = the file name(s), joined with `, `, and `source_url` = null. With intent `none` the front desk reply comes first, then the course message. A missing upload id → 404 and nothing is saved.
Response `{"messages": ChatMessage[]}` — the saved user message, then 1–2 assistant messages. All are persisted.
The front desk (`[agent: front_desk]`) returns `{"intent", "args", "reply"}`; `reply` becomes the first assistant message (agent `front_desk`). Code then runs:

| intent | args | code runs | second assistant message |
|---|---|---|---|
| `none` | — | nothing | — |
| `generate_course` | `topic` | generate with default settings (no Clarifier in chat; the full flow with questions stays at `/courses/new`) | agent `planner`, `{"type": "course", ...}`, content `Your world “{root title}” is ready — {n} nodes.` |
| `open_skill` | `skill` (title text) | resolve to a node by title (exact, then contains; newest course first) | none; the first message gets `{"type": "navigate", "scene": "skill", "skill_id": id}`. Not found → reply asks which node |
| `checkin` | — (the user's message is the transcript) | Check-in Converter | agent `checkin_converter`, `{"type": "checkin", ...}`, content lists what was recorded |
| `plan` | — | generate a study plan | agent `recommender`, `{"type": "plan", ...}` |
| `briefing` | — | narrate | agent `narrator`, `{"type": "briefing", ...}`, content = the narrative |
| `open_map` | — | nothing | none; the first message gets `{"type": "navigate", "scene": "map"}` |

**Fast path** (when `OPENAI_API_KEY` is set, whichever provider writes text): the front desk first asks the OpenAI Decisions API (`POST /v1/decisions`, gpt-6-luna, ~0.3 s) two choice questions: the intent (the seven above) and which node title the message names, if any. At confidence ≥ 0.75, `checkin` / `plan` / `briefing` / `open_map` reply with a fixed text (`Logging your day.` / `Let me pick today's quests.` / `Here is where you stand.` / `Here is your life tree.`, in the request language) and `open_skill` with a named node replies `Opening “{title}”.` with `args.skill` = that title, all without an LLM call. `generate_course` (the topic must be read out of the message), `none` (it needs a reply), lower confidence and any Decisions failure go to the LLM front desk as before.

If a pipeline fails (400/404/502), the second message explains it in English (agent `front_desk`, action null); the endpoint still returns 200. If the front desk itself fails: 502 `The assistant is temporarily unavailable. Please try again.` and the user message is still saved.
Audit answers go to endpoint 8, never here. Audit turns are not ChatMessages.

### 19. `GET /api/chat/history?limit=50`
Response: the last `limit` (1–200, default 50) `ChatMessage`s, oldest first.

### 20. `GET /api/chat/suggestions`
Response `{"suggestions": [{"label": "How was your day?", "message": "Let me log my day", "skill_id": null}]}` — **at most 2** items (the two kinds in the mockup), in this order:
1. no check-in today (KST) → `How was your day?` (message `Let me log my day`)
2. "continue learning":
   - the node of the most recent audit, if it is not mastered → `Continue “{title}”` (message = the same text), `skill_id` set
   - else the lowest-id available node of the newest course → `Start with “{title}”` (message = the same text), `skill_id` set
   - no course → `Tell me what you want to learn`, `message` = `""` (the client only focuses the input)

If the newest course has no available node, item 2 is the `Tell me what you want to learn` chip. "Most recent audit" means any status.

With `skill_id` set the client opens that node (scene 4) instead of sending `message`.

### 21. `GET /api/checkins/today`
Response: today's (KST) `DailyCheckIn`, or `null` (status 200) when there is none.

### 22. `GET /api/skills/{id}/overview`
Response:
```json
{"skill": SkillNode, "course": Course,
 "contains_parents": [SkillNode], "requires": [{"skill": SkillNode, "reason": "..."}],
 "audits": [AuditSummary], "materials": [SearchPlan]}
```
- `requires` = nodes this node requires (the sources of requires edges into it).
- `audits` = this node's audits, newest first. `materials` = its search plans, newest first.
Errors: 404 `skill not found`.

### AuditSummary
```json
{"id": 31, "skill_id": 5, "skill_title": "Quadratic Equations", "status": "failed", "score": 45,
 "created_at": "2026-10-05T03:20:00Z", "test_out": false}
```

### 23. `GET /api/audits?limit=20`
Response: `AuditSummary[]` of all courses, newest first; `limit` 1–100, default 20.

### Mock front desk (offline)
Keyword rules on the message (case-insensitive), first match wins:
- a node title contained in the message (the longest matching title wins) **and** `challenge|audit|try|open|continue|start` → `open_skill`
- `sleep|slept|tired|exercise|worked out|ate|had .* for (breakfast|lunch|dinner)|log my day|my day` → `checkin`
- `learn|study|build|make|create` → `generate_course`, topic = the message minus a leading `I want to learn|I'd like to learn|I want to study|teach me|build me a world (for|about)|make a world (for|about)` and trailing punctuation; an empty topic (or `this|this file|these`, which with uploads mean "use the file") → `none` asking for a topic
- `quest|what should i|recommend` → `plan`
- `status|report|how am i doing` → `briefing`
- `map|world` → `open_map`
- else `none`

Replies: `none` → `Sure. What would you like to do today?`; `generate_course` → `I'll build a world for “{topic}”.`; `generate_course` with an empty topic → `none` with `What topic should I build?`; `open_skill` → `Taking you to “{title}”.`; `checkin` → `Got it, logging that.`; `plan` → `Let me pick today's quests.`; `briefing` → `Let me sum up where you are.`; `open_map` → `Opening your life tree.`

Other chat messages written by code (agent `front_desk` unless noted): `open_skill` not found → `Which node do you mean? Tell me its name.`; check-in result (agent `checkin_converter`) → `Logged: sleep {h} h · exercise {yes/no} · meals {note}` (only the fields found, joined by ` · `; nothing found → `I couldn't find anything to log. Tell me about sleep, exercise or meals.`); plan result (agent `recommender`) → `Today's quests: “A”, “B”, “C”.`; no available node → `No node is ready yet. Make a world first.`; failures → `I couldn't build that world. Please try again in a moment.` / `I couldn't pick today's quests. Please try again.` / `I couldn't put your status together. Please try again.`

### 24. `POST /api/uploads`  (no LLM)
`multipart/form-data` with one `file` field. Accepted: `.pdf`, `.txt`, `.md`, at most 4 MB — Vercel caps a request body at 4.5 MB (else 400 `Only PDF, TXT or MD files up to 4 MB.`). Text is extracted (PDF via `pypdf`) and stored, cut to 100 000 characters; a file with no extractable text → 400 `No text could be read from this file.`
Response:
```json
{"id": 3, "filename": "Calculus syllabus.pdf", "chars": 18234, "created_at": "2026-10-05T03:00:00Z"}
```


## 6. Life-as-a-game layer (endpoints 25–31, added 2026-10-05)

Borrowed from Dan Koe's "life as a video game" framing: stakes (anti-vision), win condition (vision), an identity line, rules (constraints), one main quest, boss fights and daily quests, plus short reflection prompts during the day. See `docs/ux-chat.md` §6.

### Profile
```json
{"identity": "I am the type of person who explains things from first principles.",
 "vision": "...", "anti_vision": "...", "rules": ["No phone before the first audit", "..."],
 "updated_at": "2026-10-05T03:00:00Z"}
```
All text fields may be empty strings; `updated_at` is null until the first save. Limits: `identity`, `vision`, `anti_vision` ≤ 280 characters; `rules` ≤ 5 items, each ≤ 120 characters, blank items dropped.

### 25. `GET /api/profile`  (no LLM)
Response: `Profile` (a fresh database returns empty strings, `rules: []`, `updated_at: null`).

### 26. `PUT /api/profile`  (no LLM)
Request: any subset of `{"identity", "vision", "anti_vision", "rules"}`; omitted fields are kept. Over-limit values → 422. Response: the saved `Profile`.

### JournalEntry
```json
{"id": 4, "prompt": "What are you putting off right now?", "answer": "...", "created_at": "2026-10-05T02:10:00Z"}
```

### 27. `GET /api/journal?limit=20`  (no LLM)
Response: `JournalEntry[]`, newest first; `limit` 1–100.

### Suggestions (endpoint 20) — reflection item
Item 1 is the check-in chip when there is no check-in today; **otherwise it is the reflection prompt of the current KST time window**, as `{"label": <prompt>, "message": "", "skill_id": null, "reflection": true}`. All other items have `"reflection": false`. Item 2 (continue learning) is unchanged. Windows (KST):

| from | to | prompt |
|---|---|---|
| 03:00 | 10:59 | `Who are you becoming this week? One sentence.` |
| 11:00 | 13:29 | `What are you putting off right now?` |
| 13:30 | 15:14 | `Looking at the last two hours, what were you really after?` |
| 15:15 | 16:59 | `Is today pulling you toward your vision or your anti-vision?` |
| 17:00 | 19:29 | `What matters most that you've been ignoring?` |
| 19:30 | 20:59 | `Today, were you guarding an image of yourself or going after what you want?` |
| 21:00 | 02:59 | `When did you feel most alive today, and when least?` |

A window's prompt is offered only if there is no JournalEntry with that prompt today (KST); otherwise item 1 is omitted.

### Chat (endpoint 18) — answering a reflection
Request may carry `"reflection_prompt": "<the prompt>"` (must be one of the seven prompts, else 422). Then **no LLM runs**: code saves an assistant message (agent `front_desk`, content = the prompt), the user message, a `JournalEntry`, and an assistant message `Noted. It's in your journal.`; the response returns these three messages in that order (prompt, user, ack).

### Goal — a main quest (added 2026-10-05)
```json
{"id": 1, "title": "Teach calculus to a stranger", "course_ids": [1, 4], "created_at": "2026-10-05T03:00:00Z"}
```
A one-year goal. At most **3**; `title` is trimmed, 1–80 characters. A course is under **at most one** goal (`course_ids` in the order attached); a course under none is a **side quest**. No LLM anywhere below.

### 28. `GET /api/goals`
Response: `Goal[]`, oldest first.

### 29. `POST /api/goals`
Request `{"title"}`. Response: the new `Goal` (no courses). Blank or over 80 characters → 422; a fourth goal → 409 `at most 3 main quests`.

### 30. `PUT /api/goals/{id}`
Request: any subset of `{"title", "course_ids"}`; omitted fields are kept, an explicit `null` is a 422; duplicate ids collapse. Attaching a course detaches it from every other goal. Errors: 404 `goal not found`, 404 `course not found`. Response: the saved `Goal`.

### 31. `DELETE /api/goals/{id}`
204, no body; its courses become side quests. 404 `goal not found`.

### 31a. `POST /api/skills/scout`  (LLM: course scout, added 2026-10-06)
The tutorial's first course, read before anything is built. Request `{"answer": "idk, a lot of things"}` — not blank, at most 120 characters (422). The scout sees the answer with the main quests (endpoint 28) and the profile (endpoint 25).
- Clear answer: `{"kind": "clear", "topic": "SO-ARM101 robot arm", "question": "", "options": []}` — `topic` is the answer tidied (typos, shorthand); the client builds it with endpoint 18's `course_topic`.
- Vague answer: `{"kind": "choose", "topic": "", "question": "…", "options": [{"topic": "…", "why": "…"}]}` — at most 3 distinct options drawn from the main quest and win condition; the client shows them and builds the one picked.
- Never 502: a scout that fails answers `clear` with the answer as typed.
- Mock: an answer of 2 characters or less, or one with `idk`, `no idea`, `anything`, `a lot`, `不知道`, `随便`, `모르` and the like, is vague; the options are the main quests without a leading verb (`Complete SO-ARM101 project` → `SO-ARM101 project`), then `Python programming basics`, `Linear algebra`, `Clear technical writing`, three in all. Anything else is clear, unchanged.

### 33. `DELETE /api/courses/{id}?delete_nodes=false`  (no LLM, added 2026-10-06)
204, no body. 404 `course not found` for an unknown or already deleted course. Either way the course leaves every main quest's `course_ids` and the steps of every study plan.
- `delete_nodes=false` (default): the course is archived (`Course.archived_at`). It leaves endpoints 3, 4 (404), 5, 6, 11, 15, 20 and the front desk's node list, and can no longer be put under a quest (endpoint 30: 404). Its nodes, audits and lesson cards stay: endpoints 10 and 23 still list them; endpoint 11 keeps the lessons but drops the hidden nodes and every edge to them.
- `delete_nodes=true`: the course and its nodes, edges, audits (turns, rewards), the lesson cards those audits produced, every link to or from them and the nodes' search plans are deleted.
- Either way, nodes of other courses that were this course (`linked_course_id`) become plain nodes again **(2026-10-09)**.

### Life tree (client, built from endpoints 4, 10, 23, 25, 28)
You in the middle → main quests → the courses that serve them → each course's nodes (primary contains edges). Side-quest courses hang from you directly. Scene 2 shows it with progress over all courses (`Cleared` m / n, `Progress` %, `Ready`, `Audits`, `Lessons`); tapping a point shows its audit history (endpoint 22) and lesson cards (endpoint 10).

### Game framing (client labels, no API change)
- The main quests are the goals above (endpoints 28–31); scene 2 title `Life tree`.
- Root and branch nodes are **bosses** (`position` from contains edges): a `Boss` chip in scene 4, a double ring on the map, `Boss cleared!` in the celebration card.
- The current `StudyPlan` steps are the **daily quests** in the left panel (`GET /plan/current`); a step is done when its node is mastered or was audited today (KST).


## 7. Accounts (added 2026-10-05)

**Auth.** With `AUTH_MODE=supabase` every endpoint except `/api/health` needs `Authorization: Bearer <Supabase access token>`; missing, expired or invalid → **401** `not signed in` / `session expired or invalid`. Tokens are verified with the project's JWKS (`{SUPABASE_URL}/auth/v1/.well-known/jwks.json`), or with `SUPABASE_JWT_SECRET` for HS256 projects; audience `authenticated`. With `AUTH_MODE=dev` (the default) no header is needed and everything is one local user.

**Isolation.** Each account's data is in its own schema `u_<user id, no dashes>`; ids (courses, nodes, audits, …) start at 1 per account. Nothing in the contract above changes.

**Uploads.** At most 4 MB (Vercel caps a request body at 4.5 MB).

### Profile — `onboarded` (added)
`Profile` gains `"onboarded": false` until the first-run tutorial is finished or skipped. `PUT /api/profile` accepts `"onboarded": true` (done) or `false` (show it again); `null` is a 422.

### 32. `GET /api/me`  (no LLM)
Response: `{"id": "<user id>", "email": "...", "auth_mode": "supabase", "is_dev": false}`; in dev mode `{"id": "dev", "email": null, "auth_mode": "dev", "is_dev": true}`. `is_dev`: the account sees the developer panel (endpoint 34): every account in dev mode, the emails in `DEV_EMAILS` otherwise.

### 34. Developer panel  (no LLM, added 2026-10-08; developers only, 403 `developers only` otherwise)
- `GET /api/dev/audits?limit=50` (1–200) → `{"metrics": DevMetrics, "audits": DevAudit[]}`. `audits`: the newest finished audits, `{"id", "skill_id", "skill_title", "status", "score", "gaps", "comment", "turns": [{"role", "content"}], "review", "leaked", "created_at"}`.
- `PUT /api/dev/audits/{id}/review` `{"review": "right" | "too_strict" | "too_lenient" | null, "leaked": false}` → the DevAudit. A developer's review of the verdict: `too_strict` = failed but should have passed (only on a failed audit), `too_lenient` = passed but should have failed (only on a passed one), `leaked` = the Auditor gave the answer away; `null` clears both. 400 `audit is not finished` / `too_strict is for a failed audit` / `too_lenient is for a passed audit`; 404 `audit session not found`.
- `DevMetrics` over every finished audit (rates 0–1, null when there is nothing to divide by): `finished`, `pass_rate`, `avg_score`, `avg_gaps_when_failed`, `avg_answers`, `challenged_rate`; and over the reviewed ones: `reviewed`, `agreement` (share reviewed `right`), `kappa` (Cohen's kappa between the Auditor's verdict and the reviewer's), `too_strict`, `too_lenient`, `leaked` (counts).

### 35. Voice  (no LLM prompt, added 2026-10-08; needs `OPENAI_API_KEY` whatever `LLM_PROVIDER` is)
Speech through OpenAI. Without the key the app uses the browser's or the phone's own speech recognition and synthesis, and the phones always do. Where it is used:
- **Typing by voice** (the mic in the tutorial and on a node's page): the browser records an utterance and uploads it (`/transcribe`, `TRANSCRIBE_MODEL` [`gpt-transcribe`]).
- **The home page's Guide** (voice mode): by default GPT-Live over WebRTC (`/live/guide`, `LIVE_MODEL` [`gpt-live-1`]), a full-duplex voice that listens while it speaks and hands tool use to a text backend (`LIVE_BACKEND_MODEL` [`gpt-6-luna`], Responses delegation); with `GUIDE_VOICE=realtime`, or when a Live session cannot be opened, one speech-to-speech model (`/realtime/guide`, `REALTIME_MODEL` [`gpt-realtime-2.1`]) that hears the pause itself. Both can be interrupted and act through the same tools (#36). A Live session is billed every second it is open, so the browser closes it after 60 s without speech or work.
- **Audits** (voice mode): live transcription over WebRTC (`/realtime/transcribe`, `LIVE_TRANSCRIBE_MODEL` [`gpt-live-transcribe`]): the words appear while the learner speaks, a pause commits the turn and the Auditor judges it as typed text; its question is read aloud while it is made (`/speech/stream`).

Endpoints:
- `GET /api/voice` → `{"available": true, "guide": "live" | "realtime"}`; `available` is false without `OPENAI_API_KEY`; `guide` is the voice the home Guide opens first (`GUIDE_VOICE`).
- `POST /api/voice/transcribe` multipart `file` (WebM/Opus, MP4/AAC, M4A, MP3 or WAV; the format from its content type, else its file extension; at most 4 MB, about a minute) → `{"text": "..."}` (`""` for silence). Languages: the request's `Accept-Language`, plus English for the terms people mix in.
- `POST /api/voice/speech` `{"text": "..."}` (1–4096 characters) → `audio/mpeg` (`SPEECH_MODEL` [`gpt-4o-mini-tts`], `SPEECH_VOICE` [`marin`]).
- `POST /api/voice/speech/stream` `{"text": "..."}` → `audio/pcm;rate=24000`: raw 16-bit little-endian mono samples, streamed while they are made (the first in under a second).
- `POST /api/voice/live/guide`: the same handshake for GPT-Live (`POST /v1/live/sessions` with `transport: webrtc`): the voice gets the profile and the delegation policy (what the backend can do, when to hand over: a mention of the day's sleep, meals and the like goes to the check-in at once); the backend gets the tools, the rules for them, the nodes and the recent messages. Tool calls arrive on the data channel as `response.event` → `response.output_item.done` (`function_call`); the browser runs them on `/chat/act`, returns each as `response.item.create` (`function_call_output`) and sends `response.create` once the response has completed. Transcripts come as `session.input_transcript.delta` / `session.output_transcript.delta`; the browser groups them into turns for `/chat/log` (a turn ends when the user speaks after her reply, or on close) and leaves out words a tool call already saved. Closing sends `session.close` and waits for `session.closed` (its final `usage.seconds`).
- `POST /api/voice/realtime/guide` and `POST /api/voice/realtime/transcribe`, body: the browser's SDP offer (`application/sdp`, at most 64 KB) → 201 with OpenAI's SDP answer. The server adds the session (instructions, tools, models) and the key, so neither reaches the browser; audio and the `oai-events` data channel then run browser ↔ OpenAI directly. The Guide's session carries the profile, today's check-in, the nodes (newest course first) and the last 12 chat messages; its tools are `log_checkin {said}`, `build_course {topic}`, `open_node {node}`, `open_map`, `todays_plan`, `briefing`. The transcription session has no turn detection: the browser sends `input_audio_buffer.commit` on a pause.
- Errors: 503 `voice is not configured`; 400 `empty recording` / `recording too long` / `not an audio recording` / `nothing to say` / `an SDP offer is required` / `SDP offer too large`; 422 for a text outside 1–4096; 502 when OpenAI fails.

### 36. The realtime Guide's tools  (added 2026-10-08)
- `POST /api/chat/act` `{"intent": "checkin" | "generate_course" | "open_skill" | "open_map" | "plan" | "briefing", "args": {...}, "said": "..."}` → `{"messages": ChatMessage[]}`. Runs one front desk intent with no front desk call (the realtime model chose it): `[user?, result]`, where `said` (the user's words, as transcribed) is saved as their message when given. `args`: `{"topic"}` for `generate_course`, `{"skill": "<node title>"}` for `open_skill` (resolved like the front desk's), `{"said"}` for `checkin`: the Guide's summary of everything said about the day in the talk, read with the user's last words (`said`), so what came before the tool call is not lost. `open_skill` / `open_map` answer with a `navigate` action. 400 for a missing topic or check-in words; 422 for another intent.
- `POST /api/chat/log` `{"messages": [{"role": "user" | "assistant", "content": "..."}]}` (at most 20, each at most 4000 characters) → `{"messages": ChatMessage[]}`. Keeps a spoken exchange in the history; blank lines are skipped. No LLM in the response. The client sends only user lines no tool call has read, and after the response they go to the Fact Keeper (#40) and to a check-in backstop for what the Guide only talked about: the Decisions API asks whether they report the day (a confident no stops there), then the converter runs, and the day is filled in only when it finds a field. The Guide's lines (here and the navigation lines of `/act`) are `front_desk`'s.

### 37. What live voice costs  (no LLM, added 2026-10-08)
- `PUT /api/voice/sessions/{id}` `{"kind": "guide" | "transcribe", "model", "started_at", "seconds", "turns", "text_in", "text_in_cached", "audio_in", "audio_in_cached", "text_out", "audio_out", "transcribed_seconds"}` → 204. The browser's running totals for one live session (`id`: its own, 1–64 characters; each report replaces the last). Realtime: the `response.done` usage summed, the input transcription's seconds, and how long the session has been open. GPT-Live (`model: "gpt-live-1"`): `seconds` is the billed duration from `session.usage.updated` / `session.closed`, and the text fields are the backend's tokens from its nested `response.completed` usage. Sent after every turn, every 30 s while open, and on close.
- `GET /api/dev/voice?limit=50` (developers only, like #34) → `{"totals": {...}, "sessions": [{"id", "kind", "model", "started_at", "minutes", "turns", "audio_in", "audio_out", "cached_share", "cost", "backend_cost", "other_cost"}]}`. Dollars at list price (app/services/voice_usage.py): a GPT-Live Guide by its billed seconds ($0.05 a minute) plus its backend's tokens (`backend_cost`, gpt-6-luna $0.10 / $0.01 cached / $0.50 per million); a Realtime Guide by tokens (silence is free) plus its input transcription; an audit's live transcription by its open minutes ($0.017), an upper bound. `other_cost` is the same Guide session on the other voice: a GPT-Live one on Realtime at this account's own Realtime cost per minute (measured once it has a minute of Realtime sessions, $0.072 before that: one 2-minute test), a Realtime one on GPT-Live at $0.05 a minute (backend left out). Totals: `guide_sessions`, `guide_minutes`, `guide_cost`, `guide_cost_per_minute`, `guide_all_live`, `guide_all_realtime` (every Guide minute on one voice: what ran there as billed, the rest estimated), `realtime_per_minute`, `realtime_rate_measured`, `guide_cached_share` (Realtime sessions), `audit_sessions`, `audit_minutes`, `audit_cost`.

### 38. `POST /api/skills/{id}/expand`  (LLM: Planner, added 2026-10-08)
Breaks a node down into its parts (endpoint 2, **Size and layers**). No request body. **Filling in** **(2026-10-09)**: a node that has parts already (a branch, or an `unexpanded` node a syllabus or the player gave some parts) gets only the ones it is missing: the Planner is told its parts so far, and may answer none. A leaf is broken down further, as a category. The Planner gets the course topic, the node's title, description and path from the root, and the titles already in the course (not to repeat); its output hangs under the node: parts that name no known parent become its children, a part whose title the course already has (and that has no parts of its own) is dropped — the same title after normalising, or with an OpenAI key one 0.9 or nearer by embedding (a plural, a hyphen) — and a slug the course already uses gets `-2`, `-3`. Parts it cannot break down within its budget come back `unexpanded` themselves. An `unexpanded` node is claimed first in one statement, so two requests never both expand it. Any node may be expanded, locked or not: looking inside is free. Then unlocking runs again (the chapter's open node moves down to its first part: ties in the learning order go by place in the tree, so the parts stand where the node stood).
Response: the whole course map, as endpoint 4.
Errors: 404 `skill not found` (also for a node of a deleted course); 400 `This node is another course, or is being broken down already.`; 409 `This course has reached its size limit.` (500 nodes); 502 `Breaking this node down failed. Please try again.` (the node stays `unexpanded`).

### 39. Life: the player's own record  (added 2026-10-08)
How they live next to how they learn, kept in one place so the two can be compared rather than guessed at (proposal 1.1.2(1)). Not tracking: no calories, no meals counted, no devices.
- `GET /api/life?days=30` (7–365, no LLM) → `{"summary", "days", "patterns", "pattern_min_days": 5, "advice", "facts", "past_facts", "max_facts": 20}`.
  - `days`: every calendar day of the window (APP_TIMEZONE), oldest first: `{"date", "checked_in", "sleep_hours", "sleep_quality", "exercised", "exercise_minutes", "weight_kg", "diet_note", "focus", "stress", "audits", "passed"}` (the check-in's fields are null without one; `audits` / `passed` = finished audits started that day).
  - `summary` over the window: `days`, `days_logged`, `avg_sleep_hours`, `avg_sleep_quality`, `exercise_days`, `avg_exercise_minutes` (on days with minutes), `avg_focus`, `avg_stress`, `weight_first`, `weight_last` (the window's first and last weight), `audits`, `passed`. Averages one decimal, null without data.
  - `patterns`: the player's own days compared in two groups, over the whole history: `{"kind": "sleep" | "exercise" | "stress", "better": Group, "worse": Group}` — sleep 7 h or more vs under 6 h; exercised vs not; stress 1–2 vs 4–5. `Group` = `{"days", "audits", "pass_rate" (null without audits), "avg_focus"}`. A pattern is listed once both groups have `pattern_min_days` days. They are the player's own numbers on few days, shown as such, never as causes: a population result need not hold for one person (Fisher et al., 2018), which is why the record is personal.
  - `advice`: the latest Life Coach advice, or null.
  - `facts`: the lasting facts that hold now, newest first; `past_facts`: ended ones, most recently ended first (at most 50); `max_facts`: how many can hold at once (#40).
- `POST /api/life/advice` (LLM: Life Coach) → `{"items": [{"title", "body", "based_on"}], "generated_at"}` (three items; title ≤ 40, body ≤ 280, based_on ≤ 100 characters). The coach gets coarse facts of the last 14 days only — averages, exercise days, the weight change, finished and passed audits, the patterns with their day counts, nodes mastered, and the player's identity, win condition, stakes, rules and main quests — and the lasting facts that hold now (#40, as `lasting`: category, text and the month it began; it never advises against one); never a day's row or a meal. Each item names the fact it rests on; patterns come as something to try, never as a cause; no diagnosis, medication, calorie counts or diet plans; worrying numbers → see a professional. Saved (history kept; the facts it was given are stored with it). Errors: 502 `Advice is not available right now. Please try again.` (nothing saved).
- `PUT /api/checkins/{date}` (no LLM) → `DailyCheckIn`. Fixes or fills in one day: the fields sent replace that day's (`null` clears one), the others stay; a day without a check-in gets one (`source: "manual"`). Errors: 400 `That day has not come yet.`; 422 for out-of-range values.
- **The narrator** may state such a comparison when its facts include one, with its number of days, never as a cause (it still gives no advice; the coach does).
- **Privacy**: check-ins are stored in the app's database (Postgres on Supabase in the deployment, one schema per account); a voice check-in's transcript goes to the configured LLM provider to be converted; what the player says in check-ins and chat also goes to the Fact Keeper (#40), and only the short facts it keeps are stored; for advice, the coach gets only the coarse facts above.

### 40. Lasting facts  (added 2026-10-08)
Things about the player that hold for weeks and matter for how they live or study — an injury, night shifts, an exam period, something they cannot do for a while, a stable preference — kept short and few so they can go into the Life Coach's prompt without the daily record (proposal 1.1.2(2)). One day's sleep, mood, meals or workout is the check-in's, never a fact.

`LifeFact` = `{"id", "category": "health" | "schedule" | "constraint" | "preference" | "other", "text" (≤ 120), "source": "said" | "manual", "created_at", "ended_at" (null while it holds), "replaces_id" (the fact it replaced when it changed, or null)}`.

- **The Fact Keeper** (LLM, after the response as a background task, no added latency) reads what the player said in a check-in transcript (#12), a chat message the front desk routed to `checkin` or `none` without files (#18), a Guide `checkin` action and the user lines of a Guide voice log (#36). It sees the facts that hold now with their ids and answers with changes: `add` a new fact, `update` one that changed, `end` one that no longer holds; most messages change nothing. Code applies them: an update or end only sets `ended_at` on the old row (an update adds the new row with `replaces_id`), so history stays and a wrong change can be undone; an add that repeats a fact or would go past `max_facts` (20) is dropped; unknown ids are ignored. Notes are short, in the player's words, with relative spans turned into dates ("for six weeks" → "until 19 Nov"); a condition the player did not name is never written down. A failure changes nothing.
- **The gate**: with an OpenAI key, the Decisions API first answers one choice question — does the message say anything lasting, or change a listed fact? A confident `no` (≥ 0.75) skips the keeper; a failure or an unsure answer asks it.
- `POST /api/life/facts` `{"text", "category"?}` (no LLM) → `LifeFact` (`source: "manual"`). Errors: 409 `You can keep 20 lasting facts. End or delete one first.`; 422 for empty or too long text.
- `PATCH /api/life/facts/{id}` `{"text"?, "category"?, "ended"?}` (no LLM) → `LifeFact`. A wording or category fix is made in place (it was written wrong, it did not change); `ended: true` ends it now, `ended: false` brings an ended one back. Errors: 404 `fact not found`; 409 as above when bringing one back to a full list.
- `DELETE /api/life/facts/{id}` (no LLM) → 204; gone for good, and a fact that replaced it no longer points at it. Errors: 404 `fact not found`.
- Evaluation: `backend/eval/run_memory.py` (WHITEPAPER §8).

### 41–45. Editing a course by hand  (added 2026-10-09)
Every one answers the course map (as endpoint 4) of the node's course and runs unlocking again. 404 `skill not found` for an unknown node or one of a deleted course.
- **41. `PATCH /api/skills/{id}`** `{"title"?, "description"?}` (no LLM): renames a node or rewrites what it covers. 422 for a blank title, a title over 48 characters or a description over 400.
- **42. `DELETE /api/skills/{id}`** (no LLM): deletes the node and every node only under it, with their history as `delete_nodes=true` (endpoint 33) deletes it. A part that also has a parent outside stays; when it lost its main parent, its next parent becomes the main one. 400 `This is the course itself: delete the course instead.` for the root.
- **43. `POST /api/skills/{id}/children`** `{"title", "description"?}` (no LLM): adds a leaf under the node, slug from the title (`-2`, `-3` when taken). An `unexpanded` node stays so: it has a part now, not all of them. 400 `This node is another course: add parts in that course.`
- **44. `PUT /api/skills/{id}/link`** `{"course_id": int | null}` (no LLM): the node becomes another of the player's courses, or a plain node again with null. 400 with the reason when it makes no sense: `No such course.`, `A course cannot be inside itself.`, `This is a course's root: link one of its parts.`, `This node has parts of its own: delete them first, or link a node without parts.`, `That course already holds this one: the two would contain each other.` **Mastered together**: when that course's root is mastered the node is (same score); when the node is mastered from above (a challenge), that course is, all of it, as tested out. **Found by title**: when a course is built, grows (38) or takes a syllabus (45), a childless node not mastered titled like another course's root (case, punctuation and bracketed asides aside: `Computer Vision (Perception)` = `Computer vision`) becomes that course, both ways. **Found by a judge** **(2026-10-09)**, with an OpenAI key, after that: for the course and for every course not inside one yet, the six nodes of the other courses nearest its root by embedding go to the Decisions API (“where does it belong: the node that is the same subject, or the area it is a part of?”). At confidence ≥ 0.6 the course is linked: to the node itself when it is the same subject (its own parts give way to the course when none of them was learned; when one was, it is left alone), or to a new node, titled as the course, under the area. A course already inside another stays where it is. Embedding similarity alone does not decide: “Linear Regression” and “Logistic Regression” are 0.70 apart, “Computer Vision” and “计算机视觉（感知）” 0.62.
- **45. `POST /api/courses/{id}/syllabus`** `{"upload_ids": [int]}` (LLM: Syllabus Finder when searching, Planner): adds what a syllabus covers and the course lacks. The syllabus is the uploaded files, or with none a syllabus searched for the course's subject (its root's title). The Planner sees the course as `slug: title` lines indented under their parents and outputs only new nodes, each under a node of the tree (or another new one); a topic the course has under any name is not new. Nothing is removed or renamed, progress stays. The course's `source_course` / `source_url` become the syllabus's. Errors: 404 `course not found`, `upload not found`, `No syllabus found for this course.`; 409 size limit; 502 `Updating the course failed. Please try again.`
