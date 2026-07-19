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

### 4.8 Nav
`sticky` 顶部导航，`--panel-translucent` 背景，底部 1px `--border` 分隔线
（保持现有顶部横向导航结构，未改成侧边栏——这次改版只换视觉语言，不动页面
骨架）。品牌字样 `SELF·INFINITY` 用 `.pixel-font`。

---

## 5. 已知取舍 / 不做的事

- 不做卡片阴影分层（elevation）——像素描边本身已经是"轮廓感"的来源，不需要
  额外阴影暗示层级。
- 不做玻璃/模糊效果——Liquid Glass 版本已经试过并被否决（用户原话
  "简直是屎"），详见白皮书 §7；这次改版延续"零装饰"纪律，只是把描边语言从
  Notion 的 1px 细线换成像素台阶。
- 不照搬 Stitch 参考稿里的 Guild/Quests/Inventory/装备栏等虚构 RPG 功能——
  这些是 Stitch 生成的通用"Chronos/Vanguard"模板里的功能，本项目没有对应
  实际功能，移植的是视觉语言（token、像素描边、连线画法、分段条），不是
  页面结构。
- 不把顶部导航改成侧边栏——Stitch 参考稿默认是左侧栏布局，但这不在这次
  "换皮"任务范围内，`App.tsx` 的顶部横向导航结构原样保留。

---

## 6. 待办 / 已知不足

- Avatar 的像素小人（`PixelFigure`）明确是占位符（代码注释里写死了），
  不是最终美术资源，不需要为它抠细节。
- 技能树连线依赖 `getBoundingClientRect()` 做实际测量定位，在 jsdom 测试
  环境下无法获得真实布局（永远返回 0），测试只验证连线元素存在/状态样式
  正确（class 名），不验证 `d` 属性里的具体像素坐标。
