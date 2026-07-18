# Self-Infinity 技术白皮书

**版本** v0.1 · 2026-07-17
**性质** 软件工程 Capstone 设计文档（同时作为范围冻结文件）
**一句话** 把"自以为会"和"真的会"之间的差距，做成可测量、可游玩的产品机制。

---

## 0. 摘要

Self-Infinity 是一个游戏化学习验证系统（Web 全栈应用）。现有学习工具只记录"学了"，不验证"会了"；本系统用 LLM 扮演的**费曼审计官（Feynman Auditor）**对用户进行多轮压力测试——能用直觉层语言解释、能识破故意埋下的错误、能说出边界条件，技能树节点才会点亮为「原理方块」。审计失败强制触发结构化反思，反思被提炼为可执行的「原则卷轴」，长期存档并在后续审计中作为上下文复用。

**产品定位**：费曼审计是唯一的核心机制，其余一切都是围绕它的动机层。游戏化的作用不是娱乐，而是给"验证是否真的学会"这件反人性的苦事提供持续的正反馈。养成对象不是虚拟宠物，而是**用户自己的赛博分身**——技能树、原理方块、原则卷轴、体力值，全部是同一个人真实能力与状态的镜像渲染，玩的是自己，不是一个和自己无关的角色。

交付物：React + FastAPI 全栈应用，含 LLM Provider 抽象层、可离线演示的 Mock 审计、审计协议校准集与用户评估数据。

---

## 1. 问题定义

现有 to-do / 打卡 / 学习类产品有三个可观察的失败模式：

1. **验证缺失**。"完成"的定义是打了卡，不是掌握了。自评掌握度系统性虚高——重复阅读产生的熟悉感被误判为理解（流利性错觉）。
2. **反馈错配**。奖励与行为数量挂钩（连续打卡天数、专注分钟数），与学习质量零相关。用户很快学会刷奖励，而不是学习。
3. **失败无沉淀**。放弃、跳票、犯错只产生负面情绪，不产生任何结构化、可复用的知识。

Self-Infinity 的三个对应设计：

| 失败模式 | 对应机制 | 章节 |
|---|---|---|
| 验证缺失 | 费曼审计：LLM 守门人，通过才算完成 | §4.2 |
| 反馈错配 | 激励引擎：奖励只挂在审计通过上，不挂在活动量上 | §4.4 |
| 失败无沉淀 | 原则回放：失败强制转化为可执行行为规则 | §4.3 |

---

## 2. 命名约定与技术口径

先把话说清楚，避免过度声明。产品叙事和技术口径分开维护：

| 产品叙事 | 技术口径 | 为什么 |
|---|---|---|
| "动态奖励 / Modified Advantage" | **确定性激励引擎（RL-inspired）** | 系统中没有被学习的 policy、没有被估计的 value function，不构成强化学习。真正的可学习组件在 V2.1（contextual bandit）才引入 |
| "Watcher / Architect / Auditor / Scribe 多智能体共治" | **多角色 LLM 编排**（同一模型、不同角色 prompt） | 角色之间没有独立目标函数、没有博弈，不构成 MAS |
| "PFC 护盾 / 多巴胺" | **专注度评分（focus score）** | 技术文档只使用可定义、可测量的量 |

这张表本身是项目的答辩资产：**文档里每一个术语都经得起追问到底。**

---

## 3. 系统架构

```
┌─ Frontend   React 18 + Vite + TypeScript        (Pixel Minimalism 渲染层)
│      技能树 · 审计室 · 原则卷轴架
│      │  /api  (dev 反向代理)
├─ Backend    FastAPI (Python 3.13) + SQLite      (V2 迁移 Postgres)
│      ├─ routers/    REST API
│      ├─ agents/     architect(主题拆解) · auditor(审计协议状态机) · scribe(原则蒸馏)
│      ├─ llm/        Provider 抽象: GeminiProvider | MockProvider
│      └─ engine/     激励引擎 (V1.5)
└─ LLM        Gemini (云端多模态)；经 Provider 抽象解耦，可替换
```

### 关键架构决策（ADR）

- **ADR-1 Web 优先。** 演示零安装；浏览器 MediaRecorder / getUserMedia 直接覆盖 V1.1 语音审计的输入需求；迭代速度最大化。移动端推迟到 V3。
- **ADR-2 不做 iOS 屏幕语义监控。** 平台事实：iOS 禁止 App 截取其他 App 的屏幕；Screen Time API（FamilyControls / DeviceActivity）返回不透明 token，用量数据只能在沙盒化报告扩展内渲染，且分发需向 Apple 申请 entitlement。截图级语义监控只在桌面端（macOS ScreenCaptureKit）可行，安排在 V2；移动端 V3 只做"应用类别用量阈值"降级方案。
- **ADR-3 LLM Provider 抽象。** 所有 agent 只依赖 `complete(messages) -> str` 契约。MockProvider 提供确定性脚本化审计：离线可演示、CI 可测试、不被任何供应商锁定。
- **ADR-4 审计输出为强约束 JSON 协议。** probe / verdict 双形式 + 轮次上限 + 服务端兜底裁决。LLM 不守约时系统仍然收敛，不存在"审计永不结束"状态。

---

## 4. 核心机制

### 4.1 技能树生成与原理方块

学习内容不预设范围。用户输入一个主题或一个想完成的大任务，**分解规划官（Architect）**
把它拆解成 4~7 个节点、不超过三层的浅层树，追加挂到技能树上（多次生成的树彼此独立并存，
形成一片森林，不互相覆盖）。

节点状态机：`locked → available → (审计通过) → mastered`。

- 生成规则：每批生成的根节点直接 available，其余节点 locked。
- 解锁规则：父节点 mastered 后，子节点变为 available。
- mastered 节点渲染为合成完毕的像素「原理方块」，附掌握分数。
- Slug 全局唯一：同名主题重复生成、多批次节点标题重复时，服务端自动去重编号，不由
  Architect 自己保证。

**为什么这是"分解"而不是"内容生成"**：Architect 只负责拆解结构（给出节点标题/描述/父子关系），
不生成教学内容本身——它不解释"B 树是什么"，只决定"理解 B 树需要先搞懂哪几块"。真正的内容
质量把关仍然在 §4.2 的验证协议——拆得再合理，用户讲不清楚/做不到照样过不了关。这也是为什么
Architect 不需要比 Auditor 更强的能力：拆解是结构性任务，验证才是理解性/执行性任务。

**节点分两种类型，Architect 逐个节点判断**，这不是可选的元数据，而是决定用哪套验证协议：

| node_type | 含义 | 验证方式 |
|---|---|---|
| `concept` | 需要理解"为什么成立"的知识点（原理、机制、权衡） | §4.2 费曼审计：多轮追问 + 埋错试探 |
| `task` | 一个可执行的具体步骤，做没做到一目了然 | §4.2 任务核验：只确认做法具体，不深挖原理，从宽裁决 |

这个区分不是事后补丁，而是修正了一个真实踩过的坑：把"把大象放进冰箱"这种纯步骤类任务，
当成需要讲清楚第一性原理的知识点来审——用户会被问"为什么打开门这个方法在任何情况下都成立、
没有例外"，答案不管怎么说都会被判定为"停留在复述层面"，因为这个问题本身对一个操作步骤就是
无意义的。task 类型存在的意义就是不让这种审判发生。

### 4.2 两套验证协议：费曼审计 / 任务核验

用户对 available 节点发起审计，Auditor 根据节点的 `node_type` 选择协议和开场问题。

**concept 节点 → 费曼审计协议（Feynman Audit Protocol）**：开场挑战"假设我完全没听说过它，
从零开始，讲给我听"。追问策略（固化在 system prompt 中，作为协议而非临场发挥）：

1. 每轮只问一个问题；
2. 优先追问"为什么"，直到触及第一性原理；
3. 全场至少一次**故意提出看似合理但含细微错误的理解**（deliberate error injection），检验用户能否发现并纠正——这是对"背诵式掌握"的针对性打击；
4. 审计官不教学、不给答案、不安慰；
5. 追问轮次上限 N=4，之后必须裁决。

裁决维度：直觉层解释能力 / 隐含假设与边界条件 / 埋错识别。基线原则：宁 fail 不放水（由校准集验证，见 §8）。

**task 节点 → 任务核验协议（Task Verification Protocol）**：开场问题"这一步你打算具体怎么做？"

1. 不追问"为什么"，不设埋错陷阱——验证的是"有没有做到/知道怎么做"，不是"能不能讲清楚原理"；
2. 追问轮次上限更低（N=2）：问清楚具体怎么做就够了；
3. 裁决从宽：回答具体、不是空话套话（"随便弄弄""应该可以吧"）就通过。

两套协议共用同一个输出契约（二选一，严格 JSON），Auditor 只是根据 node_type 换 system prompt
和轮次上限，不是两套独立实现：

```json
{"action": "probe",   "question": "<下一个问题>"}
{"action": "verdict", "pass": true, "score": 87, "gaps": ["<未掌握/未说清的点>"], "comment": "<裁决理由>"}
```

**V1.1 多模态扩展**：讲解输入从文本升级为语音（MediaRecorder 录音直传多模态模型）。协议不变，只换输入模态——这是把多模态能力接进来成本最低、收益最直接的位置。

### 4.3 原则回放（Principle Loop）

```
审计 fail → 前端强制反思输入 → Scribe 蒸馏 → 原则卷轴入库
                                                │
              V2: 按 skill 语义检索相关原则 ────┘
                  注入下一次审计的 Auditor 上下文
```

- Scribe 输入 =（审计暴露的 gaps + 用户自由反思），输出一条 Dalio 式行为规则：title ≤ 20 字，body 为"当…时，我将…"形式，≤ 80 字，禁止空话。
- V2 将原则库向量化：审计开始时检索该 skill 相关的历史原则注入 Auditor 上下文（"该用户历史上在 X 类问题上栽过"），原则从被动档案变成主动 buff。这构成一个完整的 memory-augmented agent 闭环。

### 4.4 激励引擎（V1.5 → V2.1）

**V1.5（确定性规则系统）**：`reward = base × difficulty × level_multiplier^k`，只在审计通过时结算。等级越高、完成同等杠杆任务的奖励系数越大（复利式放大）。明确声明：这是确定性规则，不是学习算法。已实现：`base=10`；`difficulty` 由 node_type（concept 2x / task 1x）与树深度共同决定；`level` 由全局已 mastered 节点数推出（单用户应用不存在账号体系，无法按用户维度分层）；`level_multiplier=1.1`。

**关于 focus score（力场可视化的数据来源）**：§7 的力场设计假设有一个 0-100 的专注度评分驱动视觉状态，原稿设想由桌面端屏幕监控写入（`FocusSession.source`）；但 ADR-2 已明确不做屏幕监控。实现改为从审计追问的时间间隔推导 focus_score 的工程代理指标（答题节奏落在合理区间给高分，过快疑似瞎蒙、过慢疑似分心都会降分），`FocusSession.source` 字段因此保留为通用字符串（如 `"audit_engagement"`）而非绑定屏幕捕获语义。这是诚实的替代方案，不是真实专注力测量——如果未来真的接入屏幕监控，只需换一个 source 值和对应的采集逻辑，不需要改数据模型或前端可视化。

**V2.1（可学习组件）**：引入 contextual bandit（LinUCB 或 Thompson Sampling）。

- 上下文特征：用户近期审计通过率、放弃率、平均会话时长；
- 动作空间：推荐任务的难度档位；
- 奖励信号：任务被完成且审计通过。

目标是把用户维持在"够得着的困难"区间。选 bandit 而非 deep RL 是刻意的：单用户、小样本、冷启动场景下，bandit 是统计上诚实的选择——这一段本身就是答辩时展示算法判断力的地方。

**关于 bandit 的定位，需要明确一个容易混淆的点**：它不是"让 agent 更懂用户"的语义升级，不改变 Auditor 对用户解释的理解能力——那是 LLM 本身和 §4.3 原则检索注入的工作。bandit 只是一个独立的难度分发策略层，输入用户状态特征，输出任务难度，靠"是否完成+审计通过"这个奖励信号自我修正，与推荐系统"该给用户推哪篇内容"是同一类问题。两者互补，不要在叙事里混为一谈。

### 4.5 体力系统（Vitality System）· V2

游戏化的落点不止在学习本身，还在支撑学习的身体与精神状态——这是把赛博分身做"真"的关键一环：分身的状态应该真实反映用户本人的状态，而不是一套自娱自乐的独立数值。

参考《饥荒》的 Health / Sanity 互锁设计，但**刻意不做真实数据追踪**（记账、健身、饮食三个方向若做成完整追踪，每一个单独复杂度都超过费曼审计本体，参见 §10 风险与对策中的范围蔓延教训）。改用**每日签到**：三道轻量自评题（今天开销如何 / 今天动了吗 / 今天吃得规律吗），10 秒填完，滚动平均驱动数值：

```
health      = f(签到滚动平均, 窗口 7 天)
sanity_cap  = base + k  × health      # 健康越好，精神值上限越高
sanity_regen= rate0 × (1 + k' × health)  # 健康越好，精神值恢复越快
sanity      = 审计通过 → 加值 / 审计失败或长期空档 → 衰减，封顶 sanity_cap
```

- Sanity 是**审计行为的资源化表现**：通过审计涨、逃避审计或连续失败跌，直接对应"是否真的在推进理解"，不是单纯的活跃度刷分。
- Health 不产生直接奖励，只影响 Sanity 的**上限和恢复曲线**——身体状态差时，即使审计通过，精神值涨幅也打折；这是刻意的设计约束，呼应"学习需要身体基础"这个朴素事实，而不需要編造神经科学机制来自证。
- 明确不做的事：不算卡路里、不接 HealthKit/Strava、不做记账分类。这条线一旦往"真实追踪"方向走，就会长成三个独立 App，偏离费曼审计这个核心差异化——技术含量在审计协议里，不在这里。

---

## 5. 数据模型

| 表 | 字段 | 说明 |
|---|---|---|
| SkillNode | id, slug, title, description, parent_id, status, node_type, mastery_score | status: locked / available / mastered；node_type: concept / task |
| AuditSession | id, skill_id, status, score, gaps_json, created_at | status: active / passed / failed |
| AuditTurn | id, session_id, role, content, created_at | role: user / auditor |
| Principle | id, title, body, source_session_id, created_at | V2 增加 embedding 列 |
| FocusSession *(V2)* | id, started_at, ended_at, focus_score, source | 桌面端监控写入 |
| RewardEvent *(V1.5)* | id, session_id, amount, multiplier, created_at | 激励引擎结算流水 |
| DailyCheckIn *(V2)* | id, date, spending_rating, activity_rating, eating_rating | 每日签到三项自评，1–3 分 |
| VitalityState *(V2)* | id, health, sanity, sanity_cap, updated_at | 滚动计算得出的单行当前状态 |

SQLite 起步（零运维、单用户够用），schema 不依赖 SQLite 特性，V2 平移 Postgres。

---

## 6. API 设计

| Method | Path | 作用 |
|---|---|---|
| GET | `/api/skills` | 技能树全量（多批次生成的树以森林形式并存） |
| POST | `/api/skills/generate` | 提交主题/大任务，Architect 拆解并追加一批节点 |
| POST | `/api/skills/{id}/audits` | 发起审计，返回开场挑战 |
| POST | `/api/audits/{id}/turns` | 提交解释，返回追问或裁决 |
| POST | `/api/audits/{id}/reflection` | 失败后提交反思，返回蒸馏出的原则 |
| GET | `/api/principles` | 原则卷轴列表 |
| POST | `/api/checkins` | 提交每日签到，返回更新后的 Vitality 状态 |
| GET | `/api/vitality` | 当前 health / sanity / sanity_cap（首次访问自动创建默认状态） |
| GET | `/api/focus/latest` | 最近一次审计的 focus_score（本文档原定由桌面监控写入，实际改为审计追问间隔的工程代理指标，见 §4.4 附注） |
| GET | `/api/health` | 健康检查 + 当前 LLM provider |

---

## 7. 视觉规范（Pixel Minimalism）

- 深色单底 + 2px 硬边框 + 硬阴影，无渐变、无圆角、等宽字体。低视觉熵不是风格偏好，是功能需求：界面本身的信息量压到最低，注意力留给解释与追问。
- V1 三个核心可视化：分层像素技能树、原理方块合成动画（CSS `steps()` 帧动画）、原则卷轴架。
- V2 力场：环绕角色的像素圆环，粒子密度与噪点比例绑定专注度评分——专注时凝实流动，分心时出现坏点。
- V2 体力条：赛博分身头顶叠加 Health / Sanity 双条，Sanity 条的实际上限随 Health 变化可视化伸缩，让"健康影响精神值上限"这条规则不需要文字说明也能被看懂。

---

## 8. 评估计划

没有 evaluation 的系统项目不完整。两个维度：

**工程维度**
- **审计协议一致性**：构建 30 条校准集（正确解释 / 含错解释 / 背诵式复述三类），测裁决准确率与放水率（假阳性率）。校准集同时充当回归测试，模型或 prompt 每次变更都要重跑。
- **成本与延迟**：单次审计 token 预算、裁决延迟 P95。
- **测试**：agents 与 engine 单元测试（MockProvider 使其完全确定性）、API 集成测试。

**用户维度**（轻量实验，n = 5~10，两周）
- 自评掌握度 vs 审计通过率的差值。预期存在显著差值——这个差值本身就是产品的存在性证明。
- 一周后复测：审计通过的节点 vs 未经审计的自学内容，对比保留率（自身对照）。

---

## 9. 里程碑

| 里程碑 | 周期 | 内容 | 验收标准（Definition of Done） | 状态 |
|---|---|---|---|---|
| M1 | 第 1–2 周 | 审计闭环骨架 + 动态技能树生成 | MockProvider 下全流程离线可演示：给主题 → Architect 拆解 → 选节点 → 审计 → 裁决 → 方块/卷轴 | 已完成 |
| M2 | 第 3–4 周 | 接入 Gemini + 校准集 | 30 条校准集裁决准确率 ≥ 80%，放水率 ≤ 10% | 代码就绪（GeminiProvider 加固、`/backend/eval` 30 条校准集与评估脚本、路由层 502 兜底、Auditor 强制收敛、输入校验、前端测试、CI 均已落地）；真实验收待配置 `GEMINI_API_KEY` 后跑 `eval/run_calibration.py --provider gemini` |
| M3 | 第 5–6 周 | 语音讲解 + 原则检索注入 | 语音审计可用；历史原则出现在审计上下文并影响追问 | 已完成（语音讲解用浏览器原生 Web Speech API 转写接入已有文本审计流程，而非直传多模态模型——MockProvider 无法处理音频，这样才能离线可跑；原则检索用字符 bigram + 词元重叠代替向量检索，因为项目里没有向量库基础设施） |
| M4 | 第 7–8 周 | 激励引擎 + 力场可视化 + 体力系统 | 奖励结算入库；力场与 focus score 实时绑定；每日签到驱动 Health/Sanity 且可视化联动 | 已完成（focus score 来源见 §4.4 附注：审计追问间隔代替屏幕监控） |
| M5 | 第 9 周起 | 评估与报告 | §8 用户维度两项数据成文 | 未开始 |

本文档不再是"V1=M1-M2"的范围冻结——M3/M4 已应用户要求提前实现（详见各节内正文标注的范围决策）。M5（用户维度评估）待真实使用数据积累后进行，无法靠离线开发产出。

---

## 10. 风险与对策

| 风险 | 对策 |
|---|---|
| LLM 审计放水或过严 | 校准集回归（§8）+ 裁决 prompt 固化为协议 + 轮次兜底强制裁决；仍不稳则引入第二模型交叉裁决 |
| 用户照着材料念，骗过审计 | 协议规定复述不得分；埋错检测专门惩罚背诵；V1.1 语音输入提高即时性成本 |
| 审计 token 成本失控 | 轮次上限 N=4、上下文裁剪、单日审计次数预算 |
| 模型破坏 JSON 协议 | `response_mime_type` 强约束 + 解析失败兜底为 probe + 超限强制 fail 裁决 |
| 平台能力误判 | 已前置处理：iOS 截图监控从设计中移除（ADR-2），不存在"做到一半发现做不了" |
| 范围蔓延 | 本文档冻结 V1 范围；新想法一律进 backlog 排队 |
| 体力系统膨胀成三个独立追踪 App | 明确约束：Vitality System 只用每日签到自评，不做记账分类/HealthKit 集成/卡路里估算（§4.5） |
| Architect 拆解质量差（节点太大/太空/parent 引用错误） | 服务端不信任 LLM 的 parent_slug 一定合法：解析失败或引用不存在的父节点一律挂回根节点，保证树结构永远合法；slug 唯一性由服务端而非 LLM 保证（§4.1） |
| Architect 把 node_type 判断错（该判 task 判成了 concept，反之亦然） | 已发生过的真实案例：把"把大象放进冰箱"整批判成 concept，导致每一步都被追问"为什么在任何情况下都成立"。校准集（§8）需要覆盖 task/concept 混合的拆解样本，不能只测概念型主题；用户也可以在生成结果里看到 node_type 标签，发现判错能重新生成 |

---

## 附录 A · 审计裁决 JSON Schema

```json
{
  "oneOf": [
    {
      "type": "object",
      "properties": {
        "action":   {"const": "probe"},
        "question": {"type": "string"}
      },
      "required": ["action", "question"]
    },
    {
      "type": "object",
      "properties": {
        "action":  {"const": "verdict"},
        "pass":    {"type": "boolean"},
        "score":   {"type": "integer", "minimum": 0, "maximum": 100},
        "gaps":    {"type": "array", "items": {"type": "string"}},
        "comment": {"type": "string"}
      },
      "required": ["action", "pass", "score", "gaps"]
    }
  ]
}
```

## 附录 B · 术语表

| 术语 | 定义 |
|---|---|
| 分解规划官（Architect） | 把用户输入的主题/大任务拆解成技能节点树的角色，只负责结构不负责内容，同时给每个节点标注 node_type |
| node_type | 节点类型，concept（需要讲清楚原理，走费曼审计）或 task（只需确认做到了，走任务核验），决定用哪套验证协议 |
| 费曼审计 | LLM 按固定协议对用户解释进行多轮压力测试并输出结构化裁决的过程 |
| 原理方块 | 通过审计后技能节点的视觉形态，携带掌握分数 |
| 原则卷轴 | 由失败反思蒸馏出的单条可执行行为规则（"当…时，我将…"） |
| 激励引擎 | 确定性奖励结算规则系统（RL-inspired，非 RL） |
| 埋错检测 | 审计官故意提出含细微错误的理解，检验用户能否识破 |
| 专注度评分 | V2 桌面端由前台应用/屏幕内容推断的连续专注量化值 |
| 赛博分身 | 用户在系统内的可视化形象，其技能树/方块/卷轴/体力值均为真实能力与状态的镜像，不是独立于用户的养成对象 |
| 体力系统 | V2 引入的 Health/Sanity 双资源系统：Health 由每日签到滚动驱动，决定 Sanity 的上限与恢复速度；Sanity 由审计通过/失败直接结算 |
