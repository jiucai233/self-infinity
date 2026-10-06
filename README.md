# Self-Infinity

把「学习验证」做成游戏机制的全栈应用：想点亮课程图谱上的节点，必须先通过 LLM 扮演的
**费曼审计官**的压力测试——解释得了直觉、扛得住追问、识破得了故意埋下的错误；审计失败则强制
反思，反思会被提炼成「原则卷轴」长期存档。

> **命名约定**：奖励机制是确定性的激励引擎（RL-inspired），不是强化学习；
> Auditor / Challenger 等是多角色 Agent 编排，不是多智能体博弈。

## 仓库结构

| 目录 | 内容 |
|---|---|
| `backend/` | FastAPI + SQLModel + SQLite，Agent 编排与 LLM provider 抽象 |
| `app/` | Flutter 客户端（Flutter 3.47 / Dart 3.13），web / iOS / Android |
| `docs/` | `WHITEPAPER.md`（技术设计）、`api-contract.md`（API 契约）、`ui-spec.md`（页面规格）、`DESIGN.md`（视觉规范）、`ux-chat.md`（对话式首页草案） |

## 架构

课程是一张图：节点是技能，边分 `contains`（包含）和 `requires`（前置）两类。后端 Agent 按职责分四组
（代码在 `backend/app/agents/` 与 `backend/app/services/`）：

- **审计环**：Auditor（多轮追问并裁决）、Challenger（对通过结论做对抗复核）、Recorder（失败后提炼原则）、Linker（原则与节点间的关联/矛盾边）、Memory Retriever（检索历史原则注入下一次审计）
- **Analyst**：Check-in Converter（每日签到转事实）、Profile Builder（`services/profile.py`，汇总用户画像）
- **Super Managing**：Narrator（简报）、Recommender（下一步该练什么，含 contextual bandit 难度推荐）
- **Planning**：Clarifier（澄清目标）、Syllabus Finder、Planner、Structure Validator、Material Finder，把一个主题生成为课程图

激励引擎（`services/incentive.py`）按 `base × difficulty × level_multiplier^level` 确定性结算奖励。

```
app/ (Flutter)  ──/api──▶  backend/ (FastAPI routers → agents/services → llm provider)
                                         ├─ deepseek / openai / kimi / gemini
                                         └─ mock（离线）
```

API 以 `docs/api-contract.md` 为准（约束性契约）；界面与交互见 `docs/ui-spec.md`。
UI 风格（白底 Notion 风，见 `docs/DESIGN.md`）的唯一来源是 `app/lib/theme/` 与 `app/lib/widgets/`；界面按手绘稿，见 `docs/ux-chat.md`。

## 快速开始

一条命令同时起后端（默认 Mock，不花钱）和 Flutter 网页版：`./run.sh`，然后打开 http://127.0.0.1:8090 。要用真实模型：`LLM_PROVIDER=deepseek ./run.sh`。

### 后端

```bash
cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python -m pytest -q                                   # 测试
LLM_PROVIDER=mock .venv/bin/uvicorn app.main:app --port 8000    # 运行，API 文档 http://127.0.0.1:8000/docs
```

> **注意**：不加 `LLM_PROVIDER=mock` 时，只要 `backend/.env` 里配了真实 key，就会调用真模型并产生费用。

首次启动会新建一个空的 SQLite 数据库。旧的 DAG 之前的数据库会被拒绝加载并报错
（已改名保存为 `backend/self_infinity.pre-dag.db`）。

### 客户端

```bash
cd app
flutter pub get
flutter test && flutter analyze
# 连后端跑 web
flutter run -d web-server --web-port 8090 --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
# 不要后端，完全离线（内置假数据）
flutter run -d web-server --web-port 8090 --dart-define=USE_FAKE_API=true
```

`.claude/launch.json` 里有现成配置：`backend-mock`、`app-web`、`app-web-offline`。

日常使用（不开发）：双击 `Self-Infinity.command`。第一次会把 app 编译到 `app/build/web`，之后由后端在 http://127.0.0.1:8000 一个端口同时提供 API 和页面；它用 `backend/.env` 里配置的 provider。改了 app 代码后删掉 `app/build/web` 再启动。

## LLM 配置

通过 `backend/.env` 配置（模板见 `backend/.env.example`）。`LLM_PROVIDER` 可选
`deepseek` / `openai` / `kimi` / `gemini` / `mock`；留空时自动选第一个配了 key 的
provider，一个都没配则用 `mock`。`LLM_MODEL` 设默认模型，`LLM_MODEL_OVERRIDES`
（JSON）可按子 Agent 单独指定模型。其余项（`TAVILY_API_KEY` 搜索、`DATABASE_URL`、
`APP_TIMEZONE`、审计轮数上限、`CHALLENGER_ENABLED` 等）见模板里的注释。

## CI

`.github/workflows/ci.yml` 在 push / PR 到 `main` 时跑两个 job：后端 pytest、Flutter
`analyze` + `test`。

## 团队与范围

团队：신영군、김수민。3D 头像（avatar）由队友负责，目前未实现。
