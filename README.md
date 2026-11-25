# Self-Infinity

**A learning app that checks whether you really understand something.** Say what you want to learn and it builds a course and hangs it on your life tree. To clear a node, you have to explain it to an AI auditor until she gets it. The auditor plays a student meeting the idea for the first time and follows up on what you said. Where you get stuck is what you don't know yet. A failed audit asks for a reflection, which becomes a lesson card that later audits bring back up. Experience is paid only for a pass, and the tree grows as you learn more.

> **Naming**: the rewards are a deterministic incentive engine (RL-inspired, not reinforcement learning). The Auditor,
> Challenger and the rest are role prompts orchestrated by code, not a multi-agent system. The only component that
> actually learns is the contextual bandit that chooses how each audit is run.

## Features

- **Chat first.** The Guide on the home page takes one sentence. The Front Desk decides what it is and hands it to the matching pipeline: build a course, check in, plan today, or brief you. A course can start from an uploaded syllabus (PDF / TXT / MD). Without one, the Syllabus Finder looks up a real course outline with Tavily.
- **Life tree.** Home is the life tree: "me" sits at the centre of a night sky and courses and nodes grow around it. Up to three next nodes are tied to their points on the right. An outline view is one tap away.
- **Feynman audit.** The Auditor plays the student. She opens with one small question and asks along the knowledge points of the node.
  - The verdict is a vote, and one vote can come from another model family.
  - The Challenger then reviews every pass adversarially.
  - Who you explain to and how deep she asks are chosen per audit by a contextual bandit.
- **Replays and lesson cards.** A failed audit can be replayed with each gap next to your own words. Your reflection becomes a lesson card, and later audits check whether it held.
  - Past audits feed a learner model.
  - When the judging rules change, old verdicts can be judged again under the new rules.
- **Incentives.** XP, stars and levels are paid only when an audit passes, by a fixed formula you can reproduce (`services/incentive.py`).
- **Life page.** Daily check-ins and a condition flag from them. A Fact Keeper keeps the facts that hold for weeks, and a Life Coach gives three suggestions for the week.
- **Voice.** Both the Guide and the audits can talk full duplex on GPT-Live, so you can interrupt her mid-sentence. Each of the two has its own voice setting.
- **Also:**
  - The interface comes in Korean, English and Chinese, and a first visit opens in Korean.
  - A hands-on tour works without an account.
  - The companion is our own fairy, with six animations: standing, cheering, celebrating, reading, waving and sleeping.
  - A developer panel records the tokens, latency and cost of every model call, by model, by agent and per audit.

## Repository

| Path | Contents |
|---|---|
| `backend/` | FastAPI + SQLModel (SQLite locally, Postgres online), agent orchestration, LLM and search provider layers, and `eval/` for the calibration and memory evaluations |
| `app/` | Flutter client (Flutter 3.47 / Dart 3.13), one codebase for web, iOS and Android |
| `docs/` | See below |

| Document | Contents |
|---|---|
| [`WHITEPAPER.md`](docs/WHITEPAPER.md) | Technical design: every agent, the audit mechanism, the data model, evaluation |
| [`api-contract.md`](docs/api-contract.md) | The binding API contract. The backend Mock and the client's `FakeApiClient` play the same demo script |
| [`DESIGN.md`](docs/DESIGN.md) | Visual design (Paper & Ember). The source of truth is `app/lib/theme/` and `app/lib/widgets/` |
| [`ui-spec.md`](docs/ui-spec.md) / [`ux-chat.md`](docs/ux-chat.md) | Page specs and the chat-first home |
| [`deploy.md`](docs/deploy.md) | Running it online (Vercel + Supabase) |

## Architecture

```
app/ (Flutter)  ──/api──▶  backend/ (FastAPI routers → services (deterministic code) / agents (LLM roles))
                                         ├─ llm/     DeepSeek | OpenAI | Kimi | Gemini | Claude | Mock
                                         └─ search/  Tavily | Mock
```

A course is a graph. Nodes are skills, and edges are either `contains` (part of) or `requires` (prerequisite). There are about twenty LLM roles in four groups: Super Managing, Planning, Audit loop and Analyst. Each role does one job, and code calls them in fixed pipelines. The whitepaper (§3.1) describes them one by one.

## Evaluation

- **Audit calibration**:
  - 50 scenarios: 26 should pass and 24 should not.
  - Run three times on gpt-6-luna, through the same flow as production.
  - Accuracy 145/150 (96.7%). Lenient passes, i.e. a fail judged as a pass: 2/72 (2.8%). Wrong fails: 3/78.
  - Scripts and notes are in `backend/eval/`.
- **Memory consistency**: 16 scenarios split by the abilities in LongMemEval, all 16 passed.
- **Tests**: 1,435 backend tests (pytest) and 1,025 client tests (flutter test). All run deterministically on the Mock.

## Quick start

`./run.sh` starts the backend (Mock by default, so it costs nothing) and the Flutter web app together. Then open http://127.0.0.1:8090.

- For real models: `LLM_PROVIDER=deepseek ./run.sh` (or `openai`, `claude`, …).
- Locally `AUTH_MODE=dev` is the default, so there is no sign-in.

### Backend

```bash
cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python -m pytest -q                                   # tests
LLM_PROVIDER=mock .venv/bin/uvicorn app.main:app --port 8000    # run; API docs at http://127.0.0.1:8000/docs
```

> **Note**: without `LLM_PROVIDER=mock`, any real key in `backend/.env` is used, and real calls cost money.

### Client

```bash
cd app
flutter pub get
flutter test && flutter analyze
# web, against the backend
flutter run -d web-server --web-port 8090 --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
# web, fully offline on built-in demo data
flutter run -d web-server --web-port 8090 --dart-define=USE_FAKE_API=true
# render every screen to a PNG on demo data (screenshots, the poster and the demo video come from here)
SHOTS_DIR=/tmp/shots SHOTS_LANG=ko flutter test test/screenshots_test.dart
```

`.claude/launch.json` has ready-made configurations: `backend-mock`, `app-web`, `app-web-offline`.

**Everyday use (not developing).** Double-click `Self-Infinity.command`.

- The first run builds the app into `app/build/web`.
- After that, the backend serves both the API and the page on one port, http://127.0.0.1:8000, with the provider set in `backend/.env`.
- After changing app code, delete `app/build/web` and start it again.

## Configuration

Configuration lives in `backend/.env`. Every option is commented in `backend/.env.example`.

- **`LLM_PROVIDER`**: `deepseek`, `openai`, `kimi`, `gemini`, `claude` or `mock`. Left empty, it picks the first provider with a key, or `mock` if there is none.
- **`LLM_MODEL`** sets the default model. **`LLM_MODEL_OVERRIDES`** (JSON) sets one per agent.
- **Per-account provider**: when the server has both OpenAI and Claude keys, each account picks one in its settings.
- **`AUDITOR_SECOND_PROVIDER` / `AUDITOR_SECOND_MODEL`** let a second model family vote on verdicts.
- **Voice** always goes through OpenAI. See `LIVE_MODEL`, `REALTIME_MODEL`, `GUIDE_VOICE`, `AUDIT_VOICE` and the related options.
- **Other options**:
  - `TAVILY_API_KEY` for search.
  - `DATABASE_URL`.
  - `AUTH_MODE` / `SUPABASE_*` for sign-in online.
  - `APP_TIMEZONE`.
  - The audit turn limits.
  - `CHALLENGER_ENABLED`.

## CI

`.github/workflows/ci.yml` runs two jobs on every push and pull request to `main`: backend pytest, and Flutter `analyze` + `test`.

## Team

신영군 and 김수민. The in-app 3D companion is 김수민's part and is not integrated yet.
