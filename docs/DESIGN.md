# Self-Infinity 前端设计规范

本文档是当前实现的设计系统的**代码级参考**（token 值、组件规则、使用约束），
面向以后改前端样式时对照，避免再靠感觉猜。产品层面"为什么长这样"（历次改版
的历史与取舍）见 `docs/WHITEPAPER.md` §7；本文件只管"现在长什么样、怎么用"。

设计语言基准：2026-07-19 从"Notion 扁平 + 紫色主色调"改版为**纯黑白灰的像素
风格**（Google Stitch 生成的参考设计系统，位于
`stitch_continuous_momentum_tracker/self_infinity_mono_system/DESIGN.md` 与
`skill_tree_hub_pixel_mono_white/code.html`），只保留结构化的游戏感元素（技能
树折线连接、像素描边、分段体力条），去掉所有品牌色相。

---

## 1. 设计原则

1. **纯黑白灰**：只用 `#000000`/`#ffffff` 及其灰阶过渡，**没有紫色，没有
   蓝色，没有任何品牌强调色**。"强调"靠黑/白实心填充和描边表达，不靠色相。
2. **像素描边，不用圆角**：所有表面（面板/按钮/输入框/标签/技能树卡片）用
   `border-radius: 0`，边框用"四个方向偏移 box-shadow"伪造出的像素级台阶
   描边（`.pixel-border` / `.pixel-border-active`），不是普通的 1px CSS
   border。
3. **游戏感来自结构，不是装饰**：技能树的"游戏感"关键是节点间的**直角折线
   连接**（Manhattan path，不是曲线）和像素描边卡片，不加光效/模糊/渐变。
4. **深浅主题对等**：每个 token 在 `:root`（深色）和 `:root[data-theme=
   'light']`（浅色）里都有对应值，对比度纪律两边一致。
5. **两个功能性例外色**：`--danger`（审计失败/力场低专注档）和硬编码的
   `#facc15` 金色（"已掌握"状态、Sanity 条填充色）是仅有的非灰阶颜色——
   它们是状态指示器，不是品牌强调色，不受"纯黑白灰"规则约束。

---

## 2. 颜色 Token

定义在 `frontend/src/index.css` 的 `:root` / `:root[data-theme='light']`。

| Token | 深色 | 浅色 | 用途 |
|---|---|---|---|
| `--bg` | `#191919` | `#ffffff` | 页面背景 |
| `--panel` | `#191919` | `#ffffff` | 面板背景（=页面背景，靠像素描边分隔） |
| `--panel-translucent` | `#202020` | `#ffffff` | nav / 紧凑分身徽章背景，比 panel 略深一档 |
| `--border` | `rgba(255,255,255,.09)` | `rgba(55,53,47,.09)` | 极淡分隔线（nav 底边、点状网格背景） |
| `--border-strong` | `rgba(255,255,255,.13)` | `rgba(55,53,47,.16)` | 默认态像素描边颜色（`.pixel-border`）、锁定态连线 |
| `--hover-wash` | `rgba(255,255,255,.055)` | `rgba(55,53,47,.08)` | 按钮 hover 底色 |
| `--text` | `#e9e9e7` | `#37352f` | 正文/标题文字，也是唯一的"强调色" |
| `--dim` | `#9b9b96` | `#787774` | 次要文字、力场 mid 档描边 |
| `--accent` / `--accent-fill` | `#e9e9e7` | `#37352f` | 与 `--text` 同值——"强调"就是主墨色的黑/白实心填充，不是另一个色相 |
| `--accent-fill-text` | `#191919` | `#ffffff` | 实心填充按钮/pixel-border-active 上的反色文字 |
| `--danger` | `#ff6b6b` | `#c9362c` | 审计失败、力场低专注档（功能性例外色） |
| `#facc15`（无 token，硬编码） | 同左 | 同左 | "已掌握"状态色、Sanity 条填充色（功能性例外色，是"成就金"不是品牌色） |

**两份 Stitch DESIGN.md 的取舍说明**：`self_infinity_mono_system/DESIGN.md`
文件里有两段颜色定义——顶部 YAML frontmatter 是一份通用 Material 风格的色板
倾倒（`surface`/`surface-dim`/`surface-bright` 等），里面混了 `#fdf8f7`
这种偏暖调的"类灰"背景色，并不是严格纯灰；文件下方"## 2. Color Tokens"
表格给出的 `--bg`/`--text`/`--border` 等值是纯 `#ffffff`/`#191919` 灰阶，且
与本项目改版前的 Notion token 数值完全一致。本项目采用后者（表格），frontmatter
的暖色调色板未采用——理由是表格更符合"纯黑白灰"这条核心原则，采用它也让改版
的实际 diff 更小（颜色数值本身几乎不用改，改的是边框/圆角/连线的画法）。

---

## 3. 字体与间距

- 正文字体栈：`ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI",
  Helvetica, "Apple Color Emoji", Arial, sans-serif, "Segoe UI Emoji",
  "Segoe UI Symbol"`（不变，Press Start 2P 在段落长度不可读，只用于标签）。
- 像素显示字体：`"Press Start 2P"`（Google Fonts，`frontend/index.html` 里
  `<link>` 加载），通过 `.pixel-font` 工具类应用在：页面标题（h1/h2）、技能
  节点标题、nav 品牌字样、关键数值展示（体力条数值、审计得分）。**不要**
  用于正文/描述文字——8px 像素字体在长句子上不可读。
- 圆角：`--radius-control` / `--radius-panel` / `--radius-pill` 三个 token
  全部是 `0px`（像素风格没有圆角，token 保留是为了少改调用点，值已归零）。
- 面板内边距：`--gap: 20px`。
- 像素描边偏移：`--pixel-offset: 4px`（面板用 3px，按钮/输入框用 2px，见下）。

---

## 4. 组件规则

### 4.1 像素描边（`.pixel-border` / `.pixel-border-active`）
移植自 `skill_tree_hub_pixel_mono_white/code.html` 的核心技术：不用普通
`border`，而是四个方向、零模糊、固定偏移的 `box-shadow` 叠出"台阶"描边：

```css
box-shadow:
  0 -4px 0 0 <color>,
  0  4px 0 0 <color>,
  -4px 0 0 0 <color>,
  4px  0 0 0 <color>;
```

- `.pixel-border`：默认/锁定态，`--border-strong`（灰）描边 + `--panel` 背景。
- `.pixel-border-active`：主操作/激活态，`--text`（黑/白）描边 + `--text`
  实心填充 + `--bg` 反色文字。

`.panel`、按钮、`input`/`textarea`、技能树节点卡片都用这套技术而不是
`border` 属性；因为 `box-shadow` 不占布局空间，相邻元素之间留了 2-3px
`margin` 防止描边互相重叠。

### 4.2 Button
- 默认态：`.pixel-border` 灰描边，透明背景，hover 才出现 `--hover-wash` 底色，
  active 态有 1px 的 `translate` 位移模拟按下反馈。
- `.accent`（主操作按钮）：`.pixel-border-active` 同款黑/白实心填充。
- `disabled`：`opacity: 0.4`。

### 4.3 Tag（`.tag`，2026-07-19 改版）
不再用色相区分分类，圆角归零，边框改成 1.5px 纯色描边。concept/task 两种
节点类型靠**描边 vs 填充**这一维度区分，而不是颜色：
- `.tag--outline`（concept，"讲清楚为什么"）：透明背景 + `--text` 描边，
  视觉上更"轻"。
- `.tag--filled`（task，"做到就行"）：`--text` 实心填充 + `--bg` 反色文字，
  视觉上更"重"，呼应"任务是要交付的承诺"。

### 4.4 Input / Textarea
`--panel` 背景、`.pixel-border` 同款灰描边、`border-radius: 0`。聚焦态：
描边颜色从 `--border-strong` 变为 `--text`（`.pixel-border-active` 的描边
配色，但不填充背景，只换描边色）。

单选框/复选框：`accent-color: var(--accent)`（现在等于 `--text`，覆盖浏览器
默认蓝色原生控件配色）。

### 4.5 Bar（体力条 / Sanity 条，`Avatar.tsx` 内部 `Bar` 组件，2026-07-19 改版）
从"一条圆角连续填充"改为**分段像素条**（`.pixel-bar-segment`）——非紧凑态
20 格、紧凑态（nav 徽章）8 格，按 `value/max` 比例取整决定填充格数，未填充格
只有描边、透明背景。

轨道容器本身的宽度仍然按 `max/trackMax` 缩放（继承自 Notion 版的规则，行为
不变）——Sanity 条的轨道宽度随 `sanity_cap` 收缩，体现"体力值影响精神值上限"
这条规则的是**可用格子总数变少**，不只是"填充格子变少"。

### 4.6 Force Field（力场环，专注度可视化，2026-07-19 改版）
四档区分改为纯灰阶（去掉原来的琥珀色 `#d9a441`）：
- `idle`：`--border-strong` 细描边。
- `low`：`--danger` 红描边（功能性例外色，唯一非灰阶档位）。
- `mid`：`--dim` 灰虚线描边。
- `high`：`--text`（黑/白）实心描边。
不用 blur/box-shadow 光晕/动画。

### 4.7 技能树连接线（`.skill-edge`，2026-07-19 改版：贝塞尔 → 直角折线）
技能树节点之间的父子连线，SVG 描边路径，不填充（`fill: none`）。**画法从
三次贝塞尔曲线改成 Manhattan/直角折线**（移植自
`skill_tree_hub_pixel_mono_white/code.html` 的 `M x1 y1 L x1 midY L x2 midY
L x2 y2` 写法），从父节点底部中点直下，到两节点纵向中点转折，横向平移到子
节点 x 坐标，再直下进入子节点顶部中点——三段折线，不需要更复杂的路由。

`d` 字符串生成逻辑在 `frontend/src/pages/SkillTree.tsx` 的 `recomputeEdges`
闭包里；**节点定位算法 `computeSkillTreeLayout()`（子树感知的居中布局）本身
完全未改动**，这次改版只换了连线的画法，没碰坐标数学。

- `.skill-edge--locked`：`--border-strong` 描边，`stroke-width: 3`，
  虚线（`stroke-dasharray: 8 8`）。
- `.skill-edge--active`（子节点状态为 available/mastered）：`--text`
  描边，`stroke-width: 4`，实线。

技能树画布容器额外叠加了 `.pixel-grid`（点状网格背景，`repeating-linear-
gradient` 20px 间距），让整个滚动区域读起来像"棋盘/游戏画面"而不是空白页。

### 4.8 Nav（已废弃，见 §4.9）
旧版是 `sticky` 顶部导航，`--panel-translucent` 背景，底部 1px `--border`
分隔线。2026-07-19（第二次改版）已替换为左侧栏，见下。

### 4.9 App Shell — 左侧栏布局（2026-07-19 第二次改版）
在"只换视觉语言，不动页面骨架"之后，用户明确要求把 Stitch 参考稿的**页面
布局**也搬过来，不只是 token。`App.tsx` 从"顶部横向 nav + `max-width: 880px`
居中单栏"改成持久左侧栏 + 主内容区占满剩余宽度，对应
`character_dashboard_pixel_mono_white/screen.png` 的整体骨架。

- `.app-shell`：`display: flex`，侧栏 + `<main>` 左右布局，`min-height: 100svh`。
- `.app-sidebar`：固定 220px 宽，`position: sticky; top: 0`，内容从上到下是
  品牌字样、紧凑 `<Avatar compact />`、`.app-sidebar-nav` 竖排导航列表。
  背景复用 `--panel-translucent`，右边 1px `--border` 分隔线（沿用旧 nav 的
  分隔线数值，只是方向从水平变竖直）。
- `.app-sidebar-nav-item` / `.app-sidebar-nav-item--active`：导航项从旧版的
  横排按钮组改成竖排整行点击区，激活项用 `--hover-wash` 底色 + 左侧 3px
  `--text` 实心竖条，对应参考稿里 "Skills" 高亮行的画法（整行色块，不是
  加粗文字）。
- `.app-main`：`flex: 1`，`padding: 32px`，不再有 `max-width` 居中限制——
  内容用满侧栏之外的全部宽度，同参考稿"主内容区顶格铺满"的观感。
- `ThemeToggle` 保持原来 `position: fixed` 悬浮右下角的实现，没有并入侧栏
  （悬浮位置在有侧栏之后依然合理，未强行改造）。

### 4.10 分身页仪表盘网格（`AvatarPage.tsx`，2026-07-19）
对应 `character_dashboard_pixel_mono_white/screen.png` 的双栏布局。
`Avatar.tsx` 拆出两个可独立摆放的命名导出（默认导出 `Avatar` 的紧凑/完整
渲染保持不变，用于侧栏和历史测试）：
- `useVitalityFocus(refreshKey?)`：抽出的数据获取 hook，`AvatarPage` 用它
  一次性拿到 `vitality`/`focus`，分别传给下面两块，不再各自发请求。
- `AvatarPortrait`：只渲染力场环 + 像素小人 + 专注度文字（原非紧凑渲染的
  下半部分）。
- `VitalsPanel`：只渲染 Health/Sanity 分段条（原非紧凑渲染的上半部分）。

`AvatarPage.tsx` 用 `.avatar-dashboard-grid`（`grid-template-columns:
minmax(220px,1fr) minmax(260px,2fr)`，720px 以下退化为单列）把
`AvatarPortrait` 放左侧面板（标题"分身"），`VitalsPanel` 放右侧面板
（标题"VITALS STATUS"），网格下方是 `.avatar-stat-row`——一排
`.stat-card`（小号像素描边方块，上方 dim 小标签+下方粗体像素数字），对应
参考稿 STRENGTH/DEXTERITY/INTELLECT/LUCK 四格的**视觉样式**，但内容换成
本项目真实有的数字：HEALTH、SANITY（含 cap）、FOCUS（仅当存在最新专注度
会话时才渲染这一格，不伪造 0 值）。签到表单面板保持原位置和逻辑不变，挪到
网格下方。

### 4.11 技能树画布统计徽章（`SkillTree.tsx`，2026-07-19）
对应 `skill_tree_hub_pixel_mono_white/screen.png` 画布右上角的
"SKILL POINTS"/"ESSENCE" 小方块——**只搬视觉样式，不搬虚构资源**。新增
`.skilltree-stat-pills`（`position: absolute; top/right: 12px`，挂在
`.pixel-grid` 容器内，容器加 `position: relative`），内容是一个
`.stat-pill`：「已掌握 X / Y」，X/Y 是从已加载的 `skills` 数组客户端算出的
真实节点数（`status === 'mastered'` 计数 / 总数），没有引入 SKILL
POINTS/ESSENCE 这类不存在的货币概念。

### 4.12 审计室沉浸式暗色画布（`AuditRoom.tsx`，2026-07-19）
对应 `focus_mode_pixel_mono/screen.png`——参考稿里这个页面是**始终纯黑**的
独立画布，不跟随浅色/深色主题切换（"专注模式"本身就是自己的沉浸式场景）。
新增 `.audit-immersive`：`background: #0a0a0a`（硬编码，不用 `--bg` token），
浅色文字，替代 `App.tsx` 给这个视图套的 `<main>` padding（`isAuditView` 为真
时 `<main>` 用 `.app-main--bleed` 去掉 32px padding，让 `.audit-immersive`
自己的 32px padding 顶到侧栏边界和视口边缘，不留一圈平时主题色的窄边）。

布局用 `.audit-immersive-layout`（grid，`1fr minmax(220px,280px)`，800px
以下退化单列）：左侧是原有对话记录 + 输入框（功能完全不变），右侧
`.audit-quest-card` 是仿 Stitch ACTIVE_QUEST 卡片的信息面板，显示：
`roleLabel`（费曼审计官/任务核验官）、当前节点类型（概念/任务）、真实的
"已提交轮次"计数（`turns.filter(t => t.role === 'user').length`，本来就在
组件 state 里，不需要后端改动）。**没有搬** Stitch 卡片里的 EXP 百分比和
剩余时间倒计时——这两个需要 `max_turns`/计时数据，当前没有传进这个组件，
本次改版选择省略而不是编造假数字，代码注释里留了这个决定的记录。返回
技能树按钮、verdict/reflection/principle 流程逻辑完全不变。

---

## 5. 已知取舍 / 不做的事

- 不做卡片阴影分层（elevation）——像素描边本身已经是"轮廓感"的来源，不需要
  额外阴影暗示层级。
- 不做玻璃/模糊效果——Liquid Glass 版本已经试过并被否决（用户原话
  "简直是屎"），详见白皮书 §7；这次改版延续"零装饰"纪律，只是把描边语言从
  Notion 的 1px 细线换成像素台阶。
- 不照搬 Stitch 参考稿里的 Guild/Quests/Inventory/装备栏/ESSENCE 货币等
  虚构 RPG 功能——这些是 Stitch 生成的通用"Chronos/Vanguard"模板里的功能，
  本项目没有对应实际功能，移植的是视觉语言和**页面骨架**（侧栏、网格、
  统计徽章、沉浸式暗色画布），骨架里填的永远是本项目真实数据，不编造数值。
- 审计室 ACTIVE_QUEST 卡片不做 EXP% / 倒计时——数据源不存在，见 §4.12。

---

## 6. 待办 / 已知不足

- Avatar 的像素小人（`PixelFigure`）明确是占位符（代码注释里写死了），
  不是最终美术资源，不需要为它抠细节。
- 技能树连线依赖 `getBoundingClientRect()` 做实际测量定位，在 jsdom 测试
  环境下无法获得真实布局（永远返回 0），测试只验证连线元素存在/状态样式
  正确（class 名），不验证 `d` 属性里的具体像素坐标。

---

## 7. 全英文 1:1 复刻（2026-07-19，第三次改版）

用户明确要求"一比一，完全复制，用英语"——不再只搬视觉语言和页面骨架，连
§5 里明确说"不照搬"的 Guild/Quests/Inventory/装备栏/ESSENCE 也要按模板加上
（作为装饰性占位，不接后端逻辑），并把现有 UI 文案全部从中文改成英文。
本节记录这次改版做了什么、哪些数字是真的哪些是装饰性的——§5 那条"不照搬
虚构 RPG 功能"的取舍到这次改版为止已被用户显式推翻，但原文保留不改，改动
记录在这里。

### 7.1 全量英文化
`App.tsx`／`SkillTree.tsx`／`AuditRoom.tsx`／`AvatarPage.tsx`／
`PrincipleShelf.tsx`／`Avatar.tsx`／`ThemeToggle.tsx` 里所有面向用户的中文
字符串（标题、按钮、占位符、状态文案、错误提示、aria-label）改成英文，
配套测试（`SkillTree.test.tsx`／`AuditRoom.test.tsx`／`Avatar.test.tsx`）
里对应的 `getByText`/`getByRole(name:)` 查询同步改成英文断言，没有削弱
覆盖率。`原则卷轴`/PrincipleShelf 按模板的 "Archive" nav 槽位改名为
"Archive"（组件文件名本身没改，只改了渲染文案，避免无意义的大范围
重命名）。语音识别用的 `recognition.lang = 'zh-CN'`
没有改——语音输入的目标用户仍然讲中文，这是功能配置不是 UI 文案。

### 7.2 侧栏导航扩展 + 新增装饰页面（`App.tsx`）
侧栏 nav 从三项（技能树/分身/原则卷轴）扩到模板的全量七项：
`Character`／`Skills`／`Archive`／`Quests`／`Guild`／`Map`／`Support`／
`Log Out`（disabled 按钮，无 onClick——本项目没有真实登录系统，不为了
凑一个导航项去搭一套假登录）。新增 `pages/Quests.tsx`／`Guild.tsx`／
`Map.tsx`／`Support.tsx`：纯静态装饰页，`.panel` 包一段 flavor
文案，主题贴本项目"学习审计"而不是模板原版的科幻叙事，不接任何后端
状态。侧栏新增装饰性 "Level N / Auditor Class" 卡片——Level 从真实的
已掌握节点数派生（`1 + Math.floor(masteredCount / 3)`），Class 是写死的
flavor 字符串；侧栏底部新增 "New Mission" 按钮，真实功能是跳转回 Skills
视图（`goToSkills`）。

### 7.3 技能节点详情页（新增 `pages/SkillNodeDetail.tsx`）
`SkillTree.tsx` 每张卡片新增一个 "Details" 按钮（保留原有 "Start
Audit"/"Audit Passed" 按钮行为不变），点击后 `App.tsx` 切到
`{ name: 'nodeDetail'; skillId }` 视图。页面内容：
- Breadcrumb "Skills > NODE DETAIL"，点 "Skills" 回到技能树。
- 标题/描述用真实 `skill.title`/`description`，子标题是真实
  `node_type`（"Concept Node"/"Task Node"），不是模板假的
  "ACTIVE ABILITY / LEVEL 3"。
- Progression 条：真实——`mastered` 时用 `mastery_score`，否则 0%。
- Requirements 框：真实——有 `parent_id` 就显示 "Requires: <父节点标题>"，
  否则 "No prerequisites"。
- Benefits 框：装饰性 flavor 文案（"+Understanding" / "+Progress toward
  mastery"），代码注释标了 decorative——没有数值 buff 系统支撑这两行。
- 操作按钮 "Allocate Skill Point"：真实，复用 `onAudit` 回调，日/夜模式
  这里没有选择器，固定传 `'day'`（代码注释里写了这个简化）。
- 底部统计行：`UNLOCKED NODES` 真实（同技能树画布的 mastered/total 徽章）；
  `GLOBAL RANK`／`TIME PLAYED` 是装饰性静态值（`#128`／`12H 40M`），本项目
  没有排名/时长统计，注释标了 decorative，纯粹为了不让这一行看起来像
  没做完。

### 7.4 技能树画布第二个统计徽章（`SkillTree.tsx`）
"Mastered X / Y" 真实徽章旁边新增装饰性 "Essence" 徽章
（`masteredCount * 25`，代码注释标 decorative），凑成模板里
SKILL POINTS/ESSENCE 那种成对徽章的视觉。"生成技能树" 按钮改名
"New Mission"（真实生成行为不变）。

### 7.5 分身页仪表盘补全（`AvatarPage.tsx`／`Avatar.tsx`）
- `VitalsPanel` 的 Health/Sanity 条显示文案改成 "Health Score"/"Mental
  Score"（`Bar` 组件新增 `displayLabel` 参数，与原有 `label` 参数分离——
  `label` 仍然是 "Health"/"Sanity"，因为它同时驱动
  `data-testid="bar-track-Health"` 等既有测试钩子，改文案不需要连带改
  测试选择器）。
- 新增 Strength/Dexterity/Intellect/Luck 四格属性行：Intellect 从真实的
  已获得原则数派生（`10 + principles.length`），其余三个是装饰性静态值，
  代码注释标了 decorative。
- 新增 "Equipped Gear" 面板：真实数据——复用 `api.listPrinciples()` 取最近
  2 条原则，标题 + "+Audit Passed" 徽章；没有原则时显示提示文案，不编造
  假装备。
- 新增 "Recent Records" 面板：同样复用最近 2 条原则（标题 + 正文截断），
  不是独立的假日志时间戳。
- 新增右下角 "Initiate Mission" 悬浮按钮（`onInitiateMission` prop，
  `App.tsx` 传入 `goToSkills`），效果同侧栏 "New Mission"。

### 7.6 审计室 quest 卡片补一条进度条（`AuditRoom.tsx`）
新增 `estimateMaxTurns(nodeType, mode)`——镜像
`backend/app/routers/audits.py` 的 `_resolve_max_turns`（concept 基数 4／
task 基数 2，night 模式翻倍），仅用于渲染 quest 卡片里的一条
`已提交轮次 / 估算上限` 进度条，纯展示用途，不是新的后端调用；如果后端
`app/config.py` 的默认值以后改了，这条进度条的百分比会跟着漂移，代码注释
里写明了这一点。真实的"什么时候强制裁决"仍然完全由后端 `_resolve_max_
turns` 决定，前端这条只是估算展示。
