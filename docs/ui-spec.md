# UI Specification (Flutter)

The client is a Flutter app in `app/` (package `self_infinity`). It talks only to the API in `docs/api-contract.md`.
The UI language is **Korean**. The visual frame is Dan Koe's "turn your life into a game": clear goal hierarchy, immediate feedback, challenge matched to skill.

---

## 1. Platform and packages

- Flutter 3.47 / Dart 3.13. Targets: **web** (primary demo, viewed in a browser), iOS, Android.
- Dependencies are fixed in `pubspec.yaml` by the scaffold and **must not be changed by feature work**:
  `http`, `go_router`, `provider`, `shared_preferences`, `url_launcher`, `intl`. Dev: `flutter_test`, `flutter_lints`.
- No code generation (no `build_runner`, no `freezed`, no `json_serializable`). Models are hand-written with `fromJson`.
- No graph library. The learning map and the knowledge graph are drawn with Flutter widgets, `CustomPainter` and `InteractiveViewer`.

### Configuration (`--dart-define`)
| Key | Default | Effect |
|---|---|---|
| `API_BASE_URL` | `http://127.0.0.1:8000/api` | Backend base URL |
| `USE_FAKE_API` | `false` | `true` → in-memory `FakeApiClient` that follows `api-contract.md` Section 4; no backend needed |

---

## 2. Architecture and file ownership

```
app/lib/
  main.dart                       scaffold
  app/app.dart                    scaffold  MaterialApp.router, theme, providers
  app/router.dart                 scaffold  all routes (Section 3)
  app/app_state.dart              scaffold  ChangeNotifier: selected course id, vision texts (shared_preferences)
  api/models.dart                 scaffold  every type in api-contract.md Section 2
  api/api.dart                    scaffold  abstract class SelfInfinityApi — one method per endpoint
  api/http_api.dart               scaffold  implementation over package:http
  api/fake_api.dart               scaffold  FakeApiClient (api-contract.md Section 4), deterministic
  api/api_exception.dart          scaffold  ApiException(statusCode, message) + Korean user message
  theme/tokens.dart               scaffold  colors, spacing, radii (Section 6)
  theme/app_theme.dart            scaffold  dark ThemeData
  widgets/                        scaffold  shared widgets (Section 5)
  voice/                          voice service interface (speech_to_text + flutter_tts) and the voice-mode loop
  features/stage/                 stage scaffold, left panel, input bar, proactive line
  features/chat/                  scene 1/5: home, chat controller, history panel
  features/map/                   scene 2: skill tree canvas and search
  features/skill/                 scene 4: node overview
  features/audit/                 scene 4-1: audit, verdict, reflection, material search
  features/onboarding/  features/checkin/  features/dex/  features/courses/   full pages
app/test/                         one file per feature area; FT tests named after Section 7
```

Feature work stays inside its own `features/<area>/` folder and its own test files. Shared files (`api/`, `app/`, `theme/`, `widgets/`, `pubspec.yaml`) belong to the scaffold. If a feature needs something there, it works around it locally and reports it.

State: `provider` for dependency injection (`SelfInfinityApi`, `AppState`). Screens load data with `FutureBuilder` or a small screen-local `ChangeNotifier`. No global stores beyond `AppState`.

---

## 3. Routes (go_router)

The main UI is a three-column **stage** (left panel · stage · history panel); see `ux-chat.md` for the scenes. Scenes switch with `go`, so the URL always names the scene. Routes are flat.

| Path | Screen |
|---|---|
| `/` | Scene 1 → 5: home, then chat (`?ask=checkin` opens with `오늘 하루 어땠어요?`) |
| `/map?course=<id>&focus=<skillId>` | Scene 2: skill tree of the course; `focus` highlights a node |
| `/skill/:id` | Scene 4: node overview |
| `/skill/:id/audit?mode=day\|night` | Scene 4-1: audit; starts a session on open |
| `/dex` | Principles and knowledge graph (full page, from ⚙) |
| `/checkin` | Condition check-in (full page, from ⚙) |
| `/onboarding` | Character creation (full page) |
| `/courses/new` | Course generation flow (full page) |

On first launch with no vision saved, `/` redirects to `/onboarding` once (skippable). Narrow screens (< 900 px): the left and history panels become drawers.

---

## 4. Screens

### 4.1 Character creation — `/onboarding` (feature C)
- Three text fields: **승리 조건** (vision: the life you want), **패배 조건** (anti-vision: the life you refuse), **메인 미션** (one-year goal). Saved locally only (`shared_preferences`); no API call, no LLM.
- Privacy notice (plan 9.4): `감사 대화와 컨디션 기록은 처리를 위해 설정된 AI 제공자에게 전송됩니다. 건강 데이터는 이 기기에만 저장됩니다.`
- Buttons: `시작하기` (save → `/`), `나중에` (skip → `/`).

### 4.2 Stage — `/` and scenes (see `ux-chat.md`)
- **Left panel**: stat bars `Lv.N` (level progress, total XP), `클리어` (mastered / total), `컨디션` — from `briefing.facts` (`xp`, `nodes`, `condition`); 오늘의 요약 from `GET /checkins/today`; ⚙ menu (도감, 컨디션 기록, 새 퀘스트 라인, 설정).
- **Scene 1 / 5**: avatar + speech bubble (her latest line only), a mini skill-tree bubble (→ scene 2), suggestions from `GET /chat/suggestions` (a chip with `skill_id` opens scene 4; otherwise it sends its `message`). Messages go to `POST /chat`; actions: `course` → `월드맵 보기`, `checkin` → refresh 오늘의 요약, `plan` / `briefing` → shown in the bubble, `navigate` → switch scene. History panel = `GET /chat/history`.
- The briefing and the study plan of the old home HUD are reached through chat (`지금 내 상태 보고`, `오늘의 퀘스트 받기`).
- **Voice**: 🎙 dictates into the input; ▮▮▮ starts voice mode (listen → send on silence → speak the reply → listen). Tap the avatar to interrupt her. Unsupported platforms show a Korean snackbar.
- **Proactive line**: at most once per 12 h, computed on the client (`ux-chat.md` §5).
- **Avatar**: 2D pixel placeholder per agent with `mood` and `state` (owned by a teammate for 3D; do not implement 3D).

### 4.3 Course generation — `/courses/new` (feature A)
Step 1 — topic: text field (`무엇을 배우고 싶나요?`), `다음` → `POST /skills/clarify`.
Step 2 — clarification (only if questions returned): one answer field per question; answers are appended to the topic as defined in api-contract.md endpoint 1.
Step 3 — settings (plan 4.3): depth profile segmented control `입문 / 표준 / 심화` (intro/standard/deep, default 표준); node count slider 4–30 (default 12); max levels slider 2–6 (default 4); switch `실제 강의계획서 찾기` (default on). `월드 생성` → `POST /skills/generate` with exactly these values (FT-01).
Loading: full-screen progress with `월드를 만드는 중…`.
Result: course title (first line of topic), node count, and — only when `source_course` is set — a source line `출처: {source_course}` with the URL opening externally (FT-02). Without a source: `모델 지식으로 구성됨`. `월드맵 보기` → `/map?course={id}` and the course becomes selected.

### 4.4 Skill tree — scene 2, `/map`
Data: `GET /courses` (course picker at the top; default = selected course or newest), `GET /courses/{id}/map`, `GET /skills/recommendation` (tier badge per node).
Layout (plan 4.5, Airflow-like):
- Each **branch** is drawn as a **group box** (title, status, `x/y 클리어`, chevron to collapse/expand). The root is the outermost box.
- Inside a box, children are laid out **left to right in layers** computed from `requires` edges among siblings (longest path), so requires arrows always point right.
- **Default expansion**: the root box and every first-level group under it are expanded; groups two or more levels below the root start collapsed (FT-05). For the 「수학」 demo course this shows 대수/함수/미적분 with their children, while 「이차방정식」 and 「수열」 are collapsed.
- A node with several contains parents is drawn **once**, inside its main parent (`is_primary`), with a badge `다른 소속: {other parent titles}` (FT-04).
- `requires` edges are drawn as arrows in the requires color (Section 6) by a painter over the layout; an edge whose end is hidden in a collapsed group attaches to that group's box.
- Node card: title, status (잠김 / 도전 가능 / 클리어 with mastery score), position badge (루트/그룹/리프), tier badge (쉬움/보통/어려움).
- Pan and zoom with `InteractiveViewer`.
- Nodes whose newest finished audit failed (and that are not mastered) are drawn red (`GET /audits`).
- The input bar is a **node search**: matches are highlighted and their groups opened; Enter goes to the first match.
- Tapping a node → scene 4 (`/skill/:id`).

### 4.4a Node overview — scene 4, `/skill/:id`
From `GET /skills/{id}/overview`: title, position, status, description, requires with reasons (`먼저 알면 좋은 것`), material links from earlier search plans, the course's syllabus source. The avatar offers `도전해 볼까요?` with a 낮/밤 toggle (밤 = 턴 2배) → scene 4-1. **Locked → no start button**; the avatar says which parent to clear first (FT-03). History panel = this node's audits.
Empty state (no course): `아직 퀘스트 라인이 없어요` + `새 퀘스트 라인`.

### 4.5 Audit — scene 4-1, `/skill/:id/audit`
On open: `POST /skills/{id}/audits {mode}`; show node title, position badge, mode.
- The auditor avatar (stern) shows the current question in its bubble; the full Q&A is in the history panel. While waiting: the bubble shows `…`; input disabled. Pass → happy avatar; fail → angry avatar.
- Probe → appended as an auditor bubble (FT-06). A Challenger probe looks the same (the API does not distinguish them).
- **Pass verdict** → victory panel `클리어!`: score, comment, `+{reward_amount} XP` (×multiplier) when present, and the newly unlocked nodes by title (`새로 열린 노드`) resolved via `GET /skills?course_id=` (FT-07). Buttons: `월드맵으로`, `본진으로`.
- **Fail verdict** → defeat panel `아직 아니에요`: score, comment, gaps as a list (FT-08). Below: reflection field `무엇을 잘못 알고 있었나요?` + `교훈 카드 만들기` → `POST /audits/{id}/reflection` → reveal the returned principle as a **loot card** (title, body, misconception) `교훈 카드 획득!`.
  Each gap has `보충 자료 찾기` → `POST /skills/{skillId}/search-plan {gap}` → list of items (title, snippet, reason) opening the URL externally.
  `다시 도전` restarts an audit on the same node.
- Errors: 502 → readable message, user's text stays in the input for retry; 400 closed session → message and a button back.
- Leaving mid-audit asks for confirmation.

### 4.6 Dex — `/dex` (feature C)
Two tabs:
- **교훈 카드** — `GET /principles`: cards with title, body, misconception (`오개념: …`), origin skill title, date (KST). Card action `보충 자료 찾기` → `POST /skills/{skill_id}/search-plan {misconception_id}` → results list. Empty: `아직 교훈 카드가 없어요. 실패는 카드가 됩니다.`
- **지식 그래프** — `GET /graph`: force-directed layout computed in Dart (deterministic seed, fixed iteration count), painted with `CustomPainter`, pan/zoom. Skill nodes colored by status; principle nodes in the loot color. Edge styles: contains neutral line, **requires accent color with an arrowhead**, origin dashed, related thin, contradicts warning color. A **legend** lists the five kinds (FT-10). Tap a node → small info card.

### 4.7 Condition check-in — `/checkin` (feature C)
- Voice is planned (Transcriber undecided). For now: a large text field `오늘 컨디션을 말하듯 적어 주세요` and a mic button shown disabled with `음성 입력 준비 중`.
- A toggle to a **manual form**: sleep hours (0–14), exercised (yes/no/unknown), diet note, focus 1–5, stress 1–5. Manual submit sends only the filled fields.
- Submit → show the extracted fields as stat tiles. If `missing_fields` is not empty (voice only): show **one** follow-up question naming the missing fields in Korean (e.g. `집중도와 스트레스는 어땠나요?`) with an answer field; submitting re-posts the combined transcript (api-contract endpoint 12). After that, missing fields stay empty (FT-11). Never pre-fill from earlier days.
- Privacy line from 4.1.

---

## 5. Shared widgets (scaffold)
`GameCard`, `StatusBadge(status)`, `PositionBadge(position)`, `TierBadge(tier)`, `StatTile(label, value)`, `XpBadge`, `Avatar(agent, mood, state)`, `SpeechBubble`, `StatBar`, `VoiceWave`, `MiniTree`, `LoadingView(message)`, `ErrorView(error, onRetry)`, `EmptyView(message, action)`, `PrimaryButton`, `SectionHeader`.
`ErrorView` shows `ApiException.userMessage` (Korean) and never a stack trace (FT-12).

### Korean error text
| Status | Text |
|---|---|
| network / no response | `서버에 연결할 수 없어요. 백엔드가 실행 중인지 확인해 주세요.` |
| 400 | the server message translated when known (table below), else `지금은 할 수 없는 동작이에요.` |
| 404 | `찾을 수 없어요.` |
| 422 | `입력값을 확인해 주세요.` |
| 502 | `AI 응답을 받지 못했어요. 잠시 후 다시 시도해 주세요.` |
| other | `알 수 없는 오류가 발생했어요.` |

Known 400 messages: `skill is locked` → `잠긴 노드예요. 상위 노드를 먼저 클리어하세요.`; `audit session is already closed` → `이미 끝난 도전이에요.`; `reflection is only accepted for a failed audit` → `실패한 도전에만 교훈 카드를 만들 수 있어요.`; `reflection already submitted for this audit` → `이미 교훈 카드를 만들었어요.`; the plan message → `도전 가능한 노드가 없어요. 먼저 퀘스트 라인을 만들어 주세요.`; the search-plan message → `찾을 gap이나 오개념이 필요해요.`

---

## 6. Design tokens — Pixel Mono

**The only style source is `app/lib/theme/tokens.dart` + `app/lib/theme/app_theme.dart` + `app/lib/widgets/`.** Feature code never writes a color, radius or font literal; it uses `AppColors`, `AppSpacing`, `AppRadius`, `AppFonts`, the theme's text styles and the shared widgets. Changing the look means changing those files only.

Style ("Pixel Mono", full reference in `DESIGN.md`): monochrome, square corners, chunky 2 px borders, a pixel font for headings and labels. Gold and red are the only hues: gold = mastered / XP / lesson cards, red = fail / errors / contradicts / warnings.

| Token | Value | Use |
|---|---|---|
| background | `#191919` | scaffold |
| surface | `#202020` | cards |
| surfaceHigh | `#2A2A2A` | raised cards, inputs |
| outline | `#3E3E3B` | borders (2 px), contains lines |
| textPrimary / primary | `#E9E9E7` | ink: text, actions, available nodes, requires arrows (with arrowhead) |
| textSecondary | `#9B9B96` | |
| locked | `#5C5C59` | 잠김 |
| mastered / xp / loot | `#FACC15` | 클리어, rewards, principle nodes |
| danger / warning | `#FF6B6B` | fail, errors, contradicts, low condition, cross-skill |
| onAccent | `#191919` | text on ink/gold/red fills |

Radius 0 everywhere. Spacing 4/8/12/16/24/32. Headings, titles and labels: **Galmuri11** (Korean pixel font, OFL, bundled in `app/assets/fonts/`); body text: platform font. Content max width 1100 px; 16 px gutter on phones. Dark theme only.

### Korean vocabulary
| Concept | UI text |
|---|---|
| course | 퀘스트 라인 |
| node statuses | 잠김 · 도전 가능 · 클리어 |
| positions | 루트 · 그룹 · 리프 |
| audit | 도전 (room title: 심사) |
| auditor | 심사관 |
| pass / fail | 클리어! / 아직 아니에요 |
| principle | 교훈 카드 |
| misconception | 오개념 |
| study plan step | 오늘의 퀘스트 |
| briefing | 상황 보고 |
| check-in | 컨디션 체크 |
| vision / anti-vision / mission | 승리 조건 / 패배 조건 / 메인 미션 |
| tiers | 쉬움 · 보통 · 어려움 |

---

## 7. Frontend tests (plan 11.5)

Widget tests run against `FakeApiClient` (or a test double of `SelfInfinityApi`); no network.

| ID | Owner | Test |
|---|---|---|
| FT-01 | A | Course generation submits the chosen settings |
| FT-02 | A | Source line shown when `source_course` is returned |
| FT-03 | A | Locked node: audit action disabled |
| FT-04 | A | Two-parent node drawn once with the `다른 소속` badge |
| FT-05 | A | First load: only the first level under the root expanded |
| FT-06 | B | Probe appended to the dialogue |
| FT-07 | B | Pass: result and unlocked nodes shown |
| FT-08 | B | Fail: gaps shown, reflection input offered |
| FT-09 | C | Briefing without narrative: facts shown, generate action offered |
| FT-10 | C | Knowledge graph: requires edge in legend and drawn with an arrow |
| FT-11 | C | Check-in with missing fields: exactly one follow-up question |
| FT-12 | scaffold + all | API 502: readable error, no crash |
