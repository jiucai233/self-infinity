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

### 3.1 Agent 一览（19 个）

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
| | Point Lister | LLM | 给没有知识点的叶子列出 3–6 个知识点（旧课程、手动加的节点；新课由 Planner 直接带出） |
| | Material Finder | LLM + 搜索 | 针对某个 gap 找补充材料；URL 只来自搜索结果，绝不由 LLM 生成 |
| Audit loop | Memory Retriever | 代码 | 取 ≤3 张相关原则卡交给 Auditor |
| | Auditor | LLM | 每轮先点评上一个回答，再出下一题或裁决；按知识点记录对错 |
| | Challenger | LLM | 对"通过"做一次对抗复核 |
| | Recorder | LLM | 把失败反思整理成原则卡 |
| | Linker | LLM | 判断新卡与旧卡/节点的 related / contradicts 关系（后台运行） |
| Analyst | Transcriber | OpenAI：输入框语音 `gpt-transcribe`，审计实时转写 `gpt-live-transcribe`（无 key 时用浏览器/手机自带 STT） | 语音转文字；审计追问由 `gpt-4o-mini-tts` 流式朗读；首页 Guide 的语音模式默认是 GPT-Live（`gpt-live-1` 负责说话，工具交给后台 `gpt-6-luna`），连不上时退回端到端的 `gpt-realtime-2.1`（契约 #35、#36） |
| | Check-in Converter | LLM | 自由文本打卡 → 结构化字段，缺的字段留空不猜 |
| | Life Coach | LLM | 生活页上按需给三条本周建议，只看 14 天汇总和长期事实 |
| | Fact Keeper | LLM（前置 Decisions 闸门） | 后台从打卡和对话里维护长期事实：新增 / 更新 / 结束 |
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

用户输入一个主题，流水线是：Clarifier（可选追问）→ Syllabus Finder → Planner → Structure Validator。Syllabus Finder 会用三条查询（两种“课纲”说法，加官方文档/教程）读取搜索结果的页面正文，只接受两类来源：学校课纲（机构 + 课程名或代码 + 主题列表），或项目维护者、出版方的官方文档、教程、教材目录；找到时**课纲条目就是第一层节点**：一条一个、顺序不变、标题照用，只去掉不是知识点的条目（导论、复习、考试、项目），把分几讲的条目（I、II）合成一个；代码核对每个条目是否落在第一层，漏了就点名让 Planner 重写一次。课纲本来就是真实课程定义好的节点，不该再被模型重新编排；概论课的课纲因此自然得到一棵中层节点的树，想深入时再逐个拆开。找不到课纲就凭模型自身知识。结果是一张有向无环图：

- **两种边**：`contains`（包含，决定位置）与 `requires`（前置）。两者一起决定学习顺序。
- **多父节点**：一个节点最多 3 个 contains 父节点，其中一个标 `is_primary`，决定它在地图上画在哪里。
- **位置**：root / branch / leaf，由 contains 边算出，不由 LLM 声明。
- **学习顺序**：树上叠一条线性顺序。一个节点包含的部分排在它前面（先学小节，再学整章，root 最后），`requires` 的前置排在前面，其余按 Planner 给出的大纲顺序。root 的子节点是“章”，章由用户自己挑：每章同一时间开放一个节点（该章顺序里第一个还没 mastered 的），所有章都通过后 root 才开放。已 mastered 的节点可以再审。
- **大小不设上限，只定最小粒度**：叶子是一个能单独讲清楚的东西——一个模型、方法、算法或定理（二次函数、CNN、SAC），文科是一个概念。宽的领域（计算机视觉）可以有几百个节点。一次 Planner 调用写不出几百个节点，所以**分层生成**：第一次写骨架（root 和全部主要领域，至多 30 个节点；一层一层写，下一层能整层放进预算才往下），预算外的类别标 `unexpanded`。每次回答只保留完整的层：某一层出现待展开的类别，这层以下全部丢掉、这层的类别都标 `unexpanded`，因为模型爱在部分类别下塞几个示例叶子，而有子节点的类别会被当成已拆完。用户点开或学到那里时再单独展开（每次只展开一层，即它的直接组成部分，至多 40 个；更深一层由用户逐个点开，展开结果过同一个 Structure Validator）。叶子的大小按教材的一节算：学一两个小时、讲十分钟左右；只需几分钟就能学会的东西（二进制、八进制、十六进制）是同一个叶子里的几种情况，拿不准时就当叶子。之前允许一次展开两层时，模型会把预算用满，拆出“位值记数法”“八进制”这种单独审计只能问出抠字眼问题的节点。只设一个防失控的上限：一门课 500 个节点。实测（gpt-6-luna）：计算机视觉骨架 30 个节点约 30 秒，展开 Motion Analysis 得 37 个节点约 50 秒。
- **叶子里是知识点，不是更小的节点**：叶子是最小的节点，再往下不再拆节点，而是它里面的 3–6 个**知识点**（“Transformer 基础”里是自注意力、前馈层、位置编码）。Planner 生成叶子时一并给出；旧课程和手动加的节点在第一次审计前由 Point Lister 补上（一次调用，失败就照旧按描述审）。“拆开”一个节点时 Planner 先判断它是什么：一个模型、架构、方法、算法或定理（或它的“基础”），或者课程里的一讲，就是叶子，不管能讲多少——它的组成部分、步骤、变体是知识点，不是节点，这时不产生子节点，只给出知识点；只有包含好几个模型或方法、每个都值得单独一讲的领域才拆。实测（gpt-6-luna，线上那门 VLA 课）：改之前“Transformer 基础”被拆成 9 个节点（输入嵌入、自注意力、多头注意力、交叉注意力、注意力掩码、位置编码……），改之后保持为一个节点、带 5 个知识点；“多模态融合与 VLM”“Operating Systems”仍正常拆成类别。带知识点的叶子不能再“继续拆开”（接口回 400，菜单里也不出现）；想改结构仍可手动加子节点，那时它成为分支，知识点不再使用。每个知识点在节点上记三样：对（讲清过）、错（上次没讲清）、还没考，以及错在哪的一句话。
- **整块挑战**：已经会的分支不必逐个叶子审。对任意分支、root 或未展开的类别（锁着的也行）发起挑战：审计官从它下面最小的单元里抽三个各问一题，再问两者的关系，一个不会就不通过；通过则它和它下面所有节点记为 mastered（`tested_out` 标明不是逐个审过的）。
- **节点类型**：`concept`（要讲清为什么）与 `task`（只确认做法具体），决定审计协议和轮次上限。
- **手动编辑**：节点可以改名、加子节点、删除（连同只属于它的部分和它们的审计记录）、补全（Planner 只看已有的部分，补缺的）。新课纲也可以套到已有的课上：Planner 看到整棵树，只输出缺的节点并指明挂在哪个节点下，已有的不删不改，进度保留。
- **课程套课程**：一个节点可以就是用户的另一门课（CS 里的“计算机视觉”就是那门 CV 课）。它没有自己的子节点，内容就是那门课；两边一起通关：那门课的 root 通过，这个节点就通过；从上面整块挑战通过了这个节点，那门课整个记为 tested_out。建课或拆开时先按标题自动识别（忽略大小写、标点和括号里的补充），再用“召回 + 判定”两步找：embedding 取最近的几个节点，交给 Decisions API 选“就是这个节点”还是“属于这个领域”，置信度 ≥ 0.6 才动（同名节点下面若没学过，让位给那门课；学过就不动）。也可以手动设置；不允许互相包含。
- **重复建课**：同一门课再建一次（换个名字或语言也算），不会新建，而是把新课纲里缺的部分补进原来的树，进度保留。判断同样是 embedding 召回 + Decisions API 判定。只靠向量相似度不行：实测 Linear Regression 与 Logistic Regression 相似度 0.70，反而高于“Computer Vision”与“计算机视觉（感知）”的 0.62。

Planner 只决定结构，不生成教学内容。内容质量由审计把关：拆得再合理，讲不清照样不过。

### 4.2 费曼审计

开场问题按节点位置选择（契约 §3.7）：带知识点的 leaf 从第一个还没过的知识点问起（“它是做什么的？为什么需要它？”）；没有知识点的 leaf 要求从零讲给外行听；branch 要求说清子节点为什么是一组、何时用哪个；root 要求说清哪些问题该用它、哪些不该。task 节点只问具体怎么做。整块挑战另有开场：从它下面第一个最小单元问起。

**每一轮：先点评，再出题（先判后教）。** 审计官的每句话分两段。先点评用户刚才的回答：指着原话说哪句对、哪句错，并把错的纠正过来（正确的说法和理由，两到四句）。再出下一题。约束只有一条：没答之前不提示——正在问的这道题，题面不能带答案或暗示；答过之后才讲。这取代了早期的“只判不教”：那时审计只在最后给一个结论和缺口清单，用户答错之后不知道错在哪，下一场还得从头讲一遍。检索练习之后立即给纠正性反馈，比只告知对错更有效 [Roediger & Karpicke, 2006; Hattie & Timperley, 2007]。为了不让“听来的”冒充“会的”，被纠正过的知识点这一场记为没过：只有用户自己的回答先答对，或者之后在新题里用对，才算。

**问情境，不问定义。** 每道题给一个具体情境，要一个判断和理由，而且一层比一层深：它做什么 → 为什么这样设计 → 改掉会坏什么 → 实际中怎么验证。“假设把 V 打乱而 K 和注意力权重不变，输出会怎样？”“Q、K、V 都是可学习的矩阵，为什么最后分工不同？”“你看到某一层的注意力几乎均匀，怎么判断这是不是真问题？”背定义答得出来的题分不出懂和没懂。题面最后说明好的回答要区分什么或论证什么，但不给出答案。情境必须是机制里真能发生的、答案确定的，不出陷阱题，不超出节点的范围。早期的“初学者人设”（只追问用户说过但没解释的词）已移除：它问不出这种题，用户背一段流畅的定义就能通过。

**按知识点考，不用每次重来。** 叶子的审计只考还没过的知识点，一个一个来，每个最多两问。裁决逐个给出结果，写回节点：对的记为已讲清，错的记下错在哪。下一场只考没过的那些，考官能看到上次错在哪，换一道新题考同一个点；全部讲清才算通过。已通过的节点复习时全部重考。没结束的审计（24 小时内）再进来会接着来，对话原样还在，也可以选择重新开始；没等到回复的那条回答会放回输入框。

**不逼问。** 用户说不会、或者说顶不住了，审计官讲清楚、把这个点记为没过，然后往下走或直接给裁决。

**裁决阶段。** 标准是节点的描述（Covers）而不是整个领域：说错的一律算缺口，问没问到都算；做的时候会去查的细节不算。宁 fail 不放水。

**轮次上限**：带知识点的叶子每个知识点两轮（最少 4、最多 10），其余 concept 8、task 4，夜间模式翻倍。上限只存在服务端，不写进 prompt，避免模型把它当配额。超限仍在追问 → 强制裁决 fail、score 0，知识点保持原状。

**可复制。** 审计页里的问题、回答、点评、裁决卡和教训卡都可以选中复制；裁决卡和出错提示各有一个复制按钮（出错提示会带上状态码和服务端原话，方便反馈问题）。

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

**每日任务按时间和状态安排**（`services/day_plan.py`）：一天的专注时间按 4 小时算——即使是专家，刻意练习每天也就 4 小时左右 [Ericsson et al., 1993]；状态 `low` 时减半，没有打卡时按 3 小时；今天的审计已经用掉的时间（从开题到最后一轮）扣掉。剩下的时间按时段分给两类事：需要判断的（学新节点、整块挑战、分支）和回忆类的（复习已通过的节点）。早上 80/20，下午 60/40，晚上 25/75，深夜最多一个短复习。晚上偏复习，是因为学完后的睡眠帮助巩固记忆 [Gais et al., 2006; Diekelmann & Born, 2010]：今天通过的节点，睡前再讲一遍。复习本身是提取练习 [Roediger & Karpicke, 2006]，按间隔排期——通过后 1、3、7、14 天，之后每 30 天 [Cepeda et al., 2006]。状态低时不安排挑战，只排叶子节点。时段比例是默认值：人的最佳时段因作息类型而异 [Schmidt et al., 2007]，计划里记录了时段，之后可以用用户自己按时段的通过率来校正。每日任务上方有一句说明，今天的打卡如果落在用户自己某个规律的较差一组（比如今天睡不满 6 小时），就引用他自己的通过率。

### 4.5 每日打卡与 컨디션

用户可以填结构化字段（睡眠、压力等），也可以写一段自由文本，由 Check-in Converter 转成字段；文本里没提到的字段留空，不猜，但入睡和起床时间算说了（“11 点睡到 7 点”= 8 小时）。一天里分几次说的（早上说睡眠、晚上说运动）会合并到当天这一行：新说到的字段覆盖，没说到的保留。语音 Guide 被要求一听到就调用打卡工具；它没调用时，对话记录会经过一个兜底：Decisions API 先判断这句话有没有在报告当天的状态，是的话再转换，找到字段才写入。睡眠质量（1–5）、运动分钟数、体重三项只在说到或填了时记录，从不追问。最近 3 次打卡的平均睡眠 < 6 小时、平均压力 ≥ 4 或平均专注 ≤ 2 → `low`；没有打卡 → `unknown`。

**生活记录**：身体状态和学习记录放在同一个库里，才能比较两者的关系，而不是靠猜（计划书 1.1.2(1)）。生活页按天列出每天的打卡和当天的审计，给出平均值和体重的起止；“你的规律”把用户自己的日子分成两组比较（睡满 7 小时 vs 不足 6 小时、运动 vs 没运动、压力 1–2 vs 4–5），各组满 5 天才显示，标出天数，只当用户自己的数字看，不下因果结论。之所以只看个人：睡眠不足的影响因人差异很大 [Van Dongen et al., 2004]，群体结论推不到个人 [Fisher et al., 2018]。

**Life Coach**：用户点一下，生成三条本周可做的小建议，每条写明依据的数字。它只看最近 14 天的粗粒度汇总（平均值、运动天数、体重变化、审计通过数、规律及其天数）和用户的身份、愿景、规则、主线任务，看不到任何一天的明细和饮食内容。不诊断、不提药物、不给卡路里或饮食方案；数字令人担心时建议找专业人士。

**长期事实**（计划书 1.1.2(2)）：会持续几周的情况——受伤、夜班、考试期、一段时间内不能做的事、稳定的偏好——存成一条条短句，最多同时 20 条，这样可以整份放进 Life Coach 的 prompt，而不用把每天的记录交出去。做法综合了三个先例：Mem0 的操作集（新增 / 更新 / 结束 / 不变）[Chhikara et al., 2025]；Zep 的做法，过时的事实标上结束时间而不删除，历史保留，Fact Keeper 改错了也能恢复 [Rasmussen et al., 2025]；MemGPT 的常驻记忆上限 [Packer et al., 2023]。Fact Keeper 在响应发出之后后台运行，读打卡原文、路由到打卡或闲聊的消息、语音 Guide 里用户说的话。调用前先用 Decisions API 问一个是非题（"有没有说到长期的事"，约 0.3 秒、只计输入 token），把握大的"没有"直接跳过。每天的睡眠、心情、饮食、运动归打卡，不进事实；用户没说出口的病名不写；"六周内不跑步"这样的相对时间换算成日期，以后读也不失真。用户在生活页能看到每一条，可以改字、结束、恢复、删除（只有用户能真正删除）。

刻意不做：卡路里、记账、HealthKit。这条线往"真实追踪"走就会长成三个独立 App，偏离核心。

**隐私**：打卡存在应用的数据库里（部署版是 Supabase 上的 Postgres，每个账号一个 schema）；语音打卡的原文会发给配置的大模型来转换；打卡和对话里说的话会交给 Fact Keeper，只存它记下的短句；生成建议时，大模型只拿到上面的汇总和当前有效的长期事实。

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
| LifeAdvice | Life Coach 的建议，连同当时给它的汇总一起保存 |
| LifeFact | 长期事实：category、text、source（said / manual）、ended_at（为空表示仍成立）、replaces_id |
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
- **记忆一致性**：16 个固定场景，按 LongMemEval 的能力划分 [Wu et al., 2025]：抽取（长期事实被记下）、噪声（只说当天的事不记）、更新（新版本成立、旧版本进历史）、结束、保持（后续闲聊不重复、不误删）、不臆测（用户没说的病名不写）。中英韩混合。脚本：`backend/eval/run_memory.py`。2026-10-08 用应用的模型（gpt-6-luna）加 Decisions 闸门实跑：16/16；22 条消息里闸门跳过 5 条，Fact Keeper 调用 17 次，单次约 2 秒（后台运行，不占用户等待时间）。场景少，只说明行为对，不代表长期使用下的准确率。

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

- Cepeda, N. J., Pashler, H., Vul, E., Wixted, J. T., & Rohrer, D. (2006). Distributed practice in verbal recall tasks: A review and quantitative synthesis. *Psychological Bulletin, 132*(3), 354–380.
- Chhikara, P., et al. (2025). Mem0: Building production-ready AI agents with scalable long-term memory. arXiv:2504.19413.
- Diekelmann, S., & Born, J. (2010). The memory function of sleep. *Nature Reviews Neuroscience, 11*(2), 114–126.
- Ericsson, K. A., Krampe, R. T., & Tesch-Römer, C. (1993). The role of deliberate practice in the acquisition of expert performance. *Psychological Review, 100*(3), 363–406.
- Fisher, A. J., Medaglia, J. D., & Jeronimus, B. F. (2018). Lack of group-to-individual generalizability is a threat to human subjects research. *PNAS, 115*(27), E6106–E6115.
- Fong, C. J., Zaleski, D. J., & Leach, J. K. (2015). The challenge–skill balance and antecedents of flow: A meta-analytic investigation. *The Journal of Positive Psychology, 10*(5), 425–446. https://doi.org/10.1080/17439760.2014.967799
- Gais, S., Lucas, B., & Born, J. (2006). Sleep after learning aids memory recall. *Learning & Memory, 13*(3), 259–262.
- Hattie, J., & Timperley, H. (2007). The power of feedback. *Review of Educational Research, 77*(1), 81–112.
- Packer, C., et al. (2023). MemGPT: Towards LLMs as operating systems. arXiv:2310.08560.
- Rasmussen, P., et al. (2025). Zep: A temporal knowledge graph architecture for agent memory. arXiv:2501.13956.
- Roediger, H. L., & Karpicke, J. D. (2006). Test-enhanced learning: Taking memory tests improves long-term retention. *Psychological Science, 17*(3), 249–255.
- Schmidt, C., Collette, F., Cajochen, C., & Peigneux, P. (2007). A time to think: Circadian rhythms in human cognition. *Cognitive Neuropsychology, 24*(7), 755–789.
- Van Dongen, H. P. A., Baynard, M. D., Maislin, G., & Dinges, D. F. (2004). Systematic interindividual differences in neurobehavioral impairment from sleep loss: Evidence of trait-like differential vulnerability. *Sleep, 27*(3), 423–433.
- Wu, D., et al. (2025). LongMemEval: Benchmarking chat assistants on long-term interactive memory. *ICLR 2025*. arXiv:2410.10813.

## 版本记录

- **v0.2（2026-10-01）**：课程从树/森林改为带两种边的 DAG；agent 重组为 16 个（之后加入 Front Desk，共 17 个）（Architect → Planner + Structure Validator，Scribe → Recorder，Librarian → Linker，新增 Clarifier、Syllabus Finder、Material Finder、Challenger、Narrator、Recommender、Check-in Converter、Profile Builder）；体力系统与专注度评分移除，改为 컨디션；前端 React → Flutter。
- **v0.1（2026-07-17）**：初版，树状技能树 + Architect / Auditor / Scribe。
