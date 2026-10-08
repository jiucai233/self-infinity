# Self-Infinity 技术白皮书

**版本** v0.2 · 2026-10-01（v0.1 · 2026-07-17 的架构已整体替换，见文末「版本记录」）
**性质** Capstone 技术设计文档，描述仓库里**现在**的实现。面向教授的计划书在 Notion，本文件不替代它。
**一句话** 把"自以为会"和"真的会"之间的差距，做成可测量、可游玩的产品机制。

---

## 0. 摘要

Self-Infinity 是一个游戏化的学习验证应用。现有学习工具只记录"学了"，不验证"会了"。本系统让用户把一个主题生成为一张课程图，图上每个节点都要通过 LLM 扮演的**费曼审计**才算掌握。审计失败时，用户写一段反思，系统把它整理成一张「교훈 카드」（原则卡），之后的审计会把这张卡拿出来追问。

费曼审计是唯一的核心机制，其余部分（XP、地图解锁、简报、每日打卡）都是围绕它的动机层。

**交付物**：Flutter 客户端（web / iOS / Android 一套代码）+ FastAPI 后端，LLM Provider 抽象层，可完全离线运行的 Mock，审计校准集。同一个项目同时作为 Capstone 与 Mobile Programming（GAI3008-01）的作业。

---

## 1. 问题定义

| 失败模式 | 现象 | 本系统的对应机制 | 章节 |
|---|---|---|---|
| 验证缺失 | "完成"等于打了卡；重复阅读产生的熟悉感被误判为理解 | 费曼审计：通过才算掌握 | §4.2 |
| 反馈错配 | 奖励挂在活动量上，用户学会刷奖励 | 奖励只在审计通过时结算 | §4.4 |
| 失败无沉淀 | 失败只留下负面情绪 | 失败强制反思 → 原则卡 → 下次审计复用 | §4.3 |

---

## 2. 命名约定与技术口径

| 产品叙事 | 技术口径 | 为什么 |
|---|---|---|
| "多 agent" | **多角色 LLM 编排**：同一模型、不同角色 prompt，由代码按固定流水线调用 | agent 之间没有独立目标、不互相调用（AD-7），不构成多智能体系统 |
| "动态奖励" | **确定性激励引擎**（RL-inspired，不是 RL） | 没有被学习的 policy 或 value function |
| "自适应难度" | **contextual bandit**（Thompson Sampling） | 这是系统里唯一真正在学习的组件 |
| "컨디션" | 最近 3 次打卡的睡眠/压力均值得出的标记 | 只用用户自报的数字，不推断、不监测 |

agent 命名规则：大的协调角色叫 *Agent*，单一职责的角色以 *-er* 结尾（Recorder、Linker、Transcriber…）。

---

## 3. 系统架构

```
app/ (Flutter 3.47, Dart 3.13)
  features/  stage · chat（scene 1/5）· map（scene 2）· skill（scene 4）· audit（scene 4-1）
  api/       ApiClient 接口 → HttpApi（真后端） | FakeApiClient（离线，同一份 Mock 脚本）
  theme/ + widgets/   样式的唯一来源（见 DESIGN.md）
        │  REST /api（契约：docs/api-contract.md）
backend/ (FastAPI + SQLModel + SQLite)
  routers/   24 个端点（18–24 为舞台界面新增）
  services/  确定性代码：course_generation · structure_validator · audit_flow · incentive · bandit · condition · profile · linking
  agents/    LLM 角色：clarifier · syllabus · planner · material_finder · auditor · challenger · recorder · linker · checkin_converter · narrator · recommender
  llm/       Provider 抽象：DeepSeek | OpenAI | Kimi | Gemini | Mock
  search/    搜索抽象：Tavily | Mock（与 LLM 正交）
```

### 3.1 Agent 一览（17 个）

| 组 | 角色 | 实现 | 职责 |
|---|---|---|---|
| Super Managing | Orchestrator | 代码 | 按固定流水线调用下面各角色 |
| | Front Desk | LLM | 对话入口：只判断用户这句话的意图，再由代码跑对应流水线 |
| | Narrator | LLM | 把聚合好的事实讲成一段简报，只能引用传入的事实 |
| | Recommender | LLM | 今日任务（3–5 步），输入含 bandit 建议难度 |
| Planning | Clarifier | LLM | 主题太模糊时最多问 2 个问题 |
| | Syllabus Finder | LLM + 搜索 | 找真实课程大纲或官方文档目录作为生成依据 |
| | Planner | LLM | 生成课程图（节点 + contains / requires 边） |
| | Structure Validator | 代码 | 11 条规则校验图结构，不合法则修正或拒绝 |
| | Material Finder | LLM + 搜索 | 针对某个 gap 找补充材料；URL 只来自搜索结果，绝不由 LLM 生成 |
| Audit loop | Memory Retriever | 代码 | 取 ≤3 张相关原则卡交给 Auditor |
| | Auditor | LLM | 多轮追问并裁决 |
| | Challenger | LLM | 对"通过"做一次对抗复核 |
| | Recorder | LLM | 把失败反思整理成原则卡 |
| | Linker | LLM | 判断新卡与旧卡/节点的 related / contradicts 关系（后台运行） |
| Analyst | Transcriber | OpenAI `gpt-transcribe`（无 key 时用浏览器/手机自带 STT） | 语音转文字（`POST /api/voice/transcribe`）；回复由 `gpt-4o-mini-tts` 朗读 |
| | Check-in Converter | LLM | 自由文本打卡 → 结构化字段，缺的字段留空不猜 |
| | Profile Builder | 代码 | 汇总画像：反复出现的误解、跨领域复发 |

**AD-7**：agent 之间从不互相调用，只有代码按固定顺序调用它们。每个 prompt 以 `[agent: name]` 开头，Mock 按这个标签分派。

### 3.2 关键架构决策

- **ADR-1 Flutter 一套代码。** 2026-10-01 起前端从 React 换成 Flutter：一套代码覆盖 web 演示和手机端，同时满足 Mobile Programming 课的要求。旧 React 客户端已删除。
- **ADR-2 不做屏幕/传感器监控。** iOS 不允许读取其他 App 的屏幕，Screen Time 数据只能在沙盒扩展里渲染。컨디션只来自用户自报的打卡。
- **ADR-3 LLM Provider 抽象。** 选择顺序：显式 `LLM_PROVIDER` → 第一个配置了 key 的 provider → Mock。`LLM_MODEL_OVERRIDES`（JSON）可按 agent 单独指定模型。DeepSeek / OpenAI / Kimi 共用一个 OpenAI 兼容实现。
- **ADR-4 审计输出是强约束 JSON。** probe / verdict 二选一 + 服务端轮次上限 + 超限强制裁决，模型不守约时系统仍然收敛。
- **ADR-5 搜索是 harness 的一层，不绑模型。** 不用模型自带的 grounding：换 provider 会让校准作废，且 grounding 配合结构化输出时拿不到来源 URL。
- **ADR-6 API 契约先行。** `docs/api-contract.md` 是约束性契约；后端 Mock 与客户端 `FakeApiClient` 跑同一份演示脚本（契约 §4），有没有后端，界面行为都一样。

---

## 4. 核心机制

### 4.1 课程图

用户输入一个主题，流水线是：Clarifier（可选追问）→ Syllabus Finder → Planner → Structure Validator。Syllabus Finder 会用三条查询（两种“课纲”说法，加官方文档/教程）读取搜索结果的页面正文，只接受两类来源：学校课纲（机构 + 课程名或代码 + 主题列表），或项目维护者、出版方的官方文档、教程、教材目录；找到时 Planner 以它的主题和顺序为骨架编排，找不到就凭模型自身知识。结果是一张有向无环图：

- **两种边**：`contains`（包含，决定位置）与 `requires`（前置）。两者一起决定学习顺序。
- **多父节点**：一个节点最多 3 个 contains 父节点，其中一个标 `is_primary`，决定它在地图上画在哪里。
- **位置**：root / branch / leaf，由 contains 边算出，不由 LLM 声明。
- **学习顺序**：树上叠一条线性顺序。一个节点包含的部分排在它前面（先学小节，再学整章，root 最后），`requires` 的前置排在前面，其余按 Planner 给出的大纲顺序。每门课同一时间只开放一个节点：顺序里第一个还没 mastered 的；通过后下一个才 available。已 mastered 的节点可以再审。
- **节点类型**：`concept`（要讲清为什么）与 `task`（只确认做法具体），决定审计协议和轮次上限。

Planner 只决定结构，不生成教学内容。内容质量由审计把关：拆得再合理，讲不清照样不过。

### 4.2 费曼审计

开场问题按节点位置选择（契约 §3.7）：leaf 要求从零讲给外行听；branch 要求说清子节点为什么是一组、何时用哪个；root 要求说清哪些问题该用它、哪些不该。task 节点只问具体怎么做。

**提问阶段：初学者人设。** 审计官只知道用户在本次对话里说过的话，只在"用了没解释的词"或"前后接不上"时追问，不主动引入外部概念带节奏。早期的"故意埋错"规则已移除：它要求审计官动用超出对话的专业知识，违背费曼法"听众必须无知"的设定。

**裁决阶段：完整专业知识。** 裁决时切回专家视角，提问阶段没问到的错误也要写进 gaps。宁 fail 不放水。

**轮次上限**：concept 8、task 4，夜间模式翻倍。上限只存在服务端，不写进 prompt，避免模型把它当配额。超限仍在追问 → 强制裁决 fail、score 0。

**Challenger**：Auditor 判通过时，Challenger 复核一次。推翻则把它的问题作为追问返回（每个会话最多一次）；维持或出错则最终通过。

**컨디션 只影响节奏**：最近打卡显示睡眠不足或压力高时，审计问题更短。不改轮次上限，不改通过标准。

```json
{"action": "probe",   "question": "..."}
{"action": "verdict", "pass": true, "score": 87, "gaps": ["..."], "comment": "..."}
```

### 4.3 原则回放

```
审计 fail → 用户写反思 → Recorder → 原则卡（title / body / misconception）入库
                                      ├─ Linker（后台）：related / contradicts 边
                                      └─ 下次审计：Memory Retriever 取 ≤3 张 → Auditor 追问
```

- 原则卡 body 是"当…时，我会…"形式的行为规则；`misconception` 是这次失败背后那个错误心智模型，一句话。
- Profile Builder 把相似的 misconception 聚成簇；跨 ≥2 个不同技能复发的簇最有说服力，简报会点名。
- Memory Retriever 用字符 bigram + 词重叠打分，不是向量检索：单用户数据量下够用，且无需向量库。

### 4.4 激励引擎与难度推荐

**奖励**：`reward = 10 × difficulty × 1.1^level`，只在审计最终通过时结算。difficulty = 节点类型权重（concept 2、task 1）+ 深度加成；level = 已掌握节点数 / 5。这是确定性规则，不是学习算法。

**bandit**：上下文压成一个就绪度分桶（low / mid / high，来自近期通过率、搁置会话数、会话时长），动作是难度档位（easy / medium / hard），共 9 个 Beta-Bernoulli 臂，Thompson Sampling。选它而不是 LinUCB：单用户数据量喂不饱线性模型。

**已知漏洞**：奖励信号是"通过 = 1"，策略会学到推简单题——通过率高、学习为零。设计目标是**挑战–技能平衡**：把用户维持在能力边缘。挑战–技能平衡是心流最稳健的前因之一 [Fong et al., 2015]，但该关联在教育情境下明显更弱，而且"平衡点 ≈ 50% 通过率"是本项目的推断，不是文献结论。因此用户评估要同时记录难度档位、结果和一条 1–5 分的主观投入度，用数据检验，而不是默认它成立。目标通过带尚未实现，落点在 `services/bandit.py`。

### 4.5 每日打卡与 컨디션

用户可以填结构化字段（睡眠、压力等），也可以写一段自由文本，由 Check-in Converter 转成字段；文本里没提到的字段留空，不猜。最近 3 次打卡的平均睡眠 < 6 小时或平均压力 ≥ 4 → `low`；没有打卡 → `unknown`。

刻意不做：卡路里、记账、HealthKit。这条线往"真实追踪"走就会长成三个独立 App，偏离核心。

---

## 5. 数据模型

| 表 | 说明 |
|---|---|
| Course | 一次生成的课程，含来源大纲（如有） |
| SkillNode | status：locked / available / mastered；node_type：concept / task；mastery_score |
| SkillEdge | kind：contains / requires；contains 边带 `is_primary`；requires 边带理由 |
| AuditSession / AuditTurn | 会话状态 active / passed / failed，score、gaps、max_turns、challenged |
| Principle / PrincipleLink | 原则卡；related / contradicts 关系 |
| RewardEvent | 奖励流水 |
| BanditArm | 9 个臂的 Beta 参数 |
| DailyCheckIn | 打卡字段，全部可空 |
| NarratorBriefing / StudyPlan / SearchPlan | 简报、今日任务、补充材料的缓存，避免重复调用 LLM |

SQLite 起步，schema 不依赖 SQLite 特性。启动时检测到旧（DAG 之前）的库会拒绝加载并报错。

---

## 6. API

以 [`api-contract.md`](api-contract.md) 为准：24 个端点、共享类型、错误文案、离线演示脚本。§5（端点 18–24）是舞台式主界面新增的接口，含文件上传。

---

## 7. 界面

- 视觉：白底、Notion 式暖灰与发丝边框，参考 ChatGPT / Gemini / NotebookLM；绿 = 通过/掌握，红 = 失败。见 [`DESIGN.md`](DESIGN.md)。
- 页面与验收测试映射：[`ui-spec.md`](ui-spec.md)。
- 主界面：[`ux-chat.md`](ux-chat.md)，严格按手绘稿：左栏角色属性与今日摘要，中间 avatar 与当前场景，节点和对话场景右侧加 history。打卡和建课程都在对话里完成，可上传 PDF/TXT/MD 作为课程大纲。每个 agent 一个形象，目前是线条小人占位，3D 由김수민负责。

---

## 8. 评估

**工程维度**
- **审计一致性**：30 条校准集（正确解释 / 含错解释 / 背诵式复述），测准确率与放水率（应 fail 却判 pass 的比例）。门槛：准确率 ≥ 80%，放水率 ≤ 10%。脚本：`backend/eval/run_calibration.py`，用 LLM 扮演学生续答，避免固定台词接不住深追问。
- **测试**：后端 pytest 528 个，客户端 flutter test 273 个，全部在 Mock 下确定性运行；CI 每次 push 跑两边。
- **成本与延迟**：单次审计 token 数、裁决延迟 P95。

**用户维度**（n = 5–10，两周）
- 自评掌握度 vs 审计通过率的差值——这个差值本身就是产品的存在性证明。
- 一周后复测：审计通过的节点 vs 未经审计的自学内容的保留率。
- 每次审计记录难度档位、结果、主观投入度（检验 §4.4 的假设）。

**当前状态**：2026-07 的真实跑分（DeepSeek）准确率约 81.7%、task 放水率约 16.7%，未过门槛；之后 Auditor prompt 随 2026-10 重构整体重写，旧数字作废，需要重跑。重跑会产生真实 API 费用。

---

## 9. 风险与对策

| 风险 | 对策 |
|---|---|
| 审计放水或过严 | 校准集回归 + Challenger 复核 + 轮次上限兜底；仍不稳则引入第二模型交叉裁决 |
| 照着材料念骗过审计 | 复述不得分；裁决用专家视角；原则卡追问历史误解 |
| 模型破坏 JSON 协议 | 解析失败按 probe 处理；超限强制 fail |
| LLM 生成的图不合法 | Structure Validator 11 条规则；服务端保证 slug 唯一、无环、父节点数 ≤3 |
| node_type 判错（步骤被当成概念追问"为什么"） | 校准集覆盖 task/concept 混合样本；地图上显示类型标签 |
| LLM 编造链接 | URL 只取自搜索结果 |
| 范围蔓延 | 打卡不做真实追踪；新想法进 backlog |
| 误用真实 key 产生费用 | run.sh 与测试默认 `LLM_PROVIDER=mock`；测试有网络防护 |

---

## 附录 A · 术语表

| 术语 | 定义 |
|---|---|
| 퀘스트 라인 / 课程 | 一次生成得到的课程图 |
| 월드맵 | 课程图的地图视图 |
| contains / requires | 包含边（决定位置与解锁）/ 软前置边（只影响顺序） |
| 费曼审计 | 按固定协议多轮追问并输出结构化裁决的过程 |
| 初学者人设 | 提问阶段只基于用户说过的话发问；裁决阶段用完整专业知识 |
| 교훈 카드 / 原则卡 | 失败反思整理出的行为规则，附带误解（misconception） |
| 컨디션 | 由最近打卡算出的 normal / low / unknown 标记，只影响审计节奏 |
| 激励引擎 | 确定性奖励规则（RL-inspired，非 RL） |

## 附录 B · 参考文献

- Fong, C. J., Zaleski, D. J., & Leach, J. K. (2015). The challenge–skill balance and antecedents of flow: A meta-analytic investigation. *The Journal of Positive Psychology, 10*(5), 425–446. https://doi.org/10.1080/17439760.2014.967799

## 版本记录

- **v0.2（2026-10-01）**：课程从树/森林改为带两种边的 DAG；agent 重组为 16 个（之后加入 Front Desk，共 17 个）（Architect → Planner + Structure Validator，Scribe → Recorder，Librarian → Linker，新增 Clarifier、Syllabus Finder、Material Finder、Challenger、Narrator、Recommender、Check-in Converter、Profile Builder）；体力系统与专注度评分移除，改为 컨디션；前端 React → Flutter。
- **v0.1（2026-07-17）**：初版，树状技能树 + Architect / Auditor / Scribe。
