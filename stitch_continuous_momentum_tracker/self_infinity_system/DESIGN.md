---
name: Self-Infinity System
colors:
  surface: '#141317'
  surface-dim: '#141317'
  surface-bright: '#3a383d'
  surface-container-lowest: '#0f0e12'
  surface-container-low: '#1c1b1f'
  surface-container: '#201f23'
  surface-container-high: '#2b292e'
  surface-container-highest: '#363439'
  on-surface: '#e6e1e7'
  on-surface-variant: '#cac4d1'
  inverse-surface: '#e6e1e7'
  inverse-on-surface: '#313034'
  outline: '#938f9a'
  outline-variant: '#48454f'
  surface-tint: '#ccbeff'
  primary: '#dfd5ff'
  on-primary: '#332664'
  primary-container: '#c4b5fd'
  on-primary-container: '#514483'
  inverse-primary: '#625595'
  secondary: '#54d8e8'
  on-secondary: '#00363c'
  secondary-container: '#02aebe'
  on-secondary-container: '#003b42'
  tertiary: '#eedb79'
  on-tertiary: '#383000'
  tertiary-container: '#d1bf60'
  on-tertiary-container: '#594d00'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#e7deff'
  primary-fixed-dim: '#ccbeff'
  on-primary-fixed: '#1e0e4e'
  on-primary-fixed-variant: '#4a3d7c'
  secondary-fixed: '#91f1ff'
  secondary-fixed-dim: '#54d8e8'
  on-secondary-fixed: '#001f23'
  on-secondary-fixed-variant: '#004f57'
  tertiary-fixed: '#f7e380'
  tertiary-fixed-dim: '#d9c767'
  on-tertiary-fixed: '#211b00'
  on-tertiary-fixed-variant: '#514700'
  background: '#141317'
  on-background: '#e6e1e7'
  surface-variant: '#363439'
  accent-dark: '#c4b5fd'
  accent-light: '#7c3aed'
  accent-strong-dark: '#a78bfa'
  accent-strong-light: '#6d28d9'
  accent-fill: '#7c3aed'
  info-dark: '#67e8f9'
  info-light: '#0e7490'
  danger-dark: '#ff6b6b'
  danger-light: '#c9362c'
  mastery-gold: '#facc15'
typography:
  headline-lg:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: '1.2'
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: '1.2'
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '600'
    lineHeight: '1.2'
    letterSpacing: -0.01em
  body-base:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: '1.5'
  label-dim:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: '1.4'
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gap-panel: 20px
  edge-thickness-locked: 1.5px
  edge-thickness-active: 2.5px
---

# Self-Infinity 前端设计规范  本文档是当前实现的设计系统的**代码级参考**（token 值、组件规则、使用约束）， 面向以后改前端样式时对照，避免再靠感觉猜。产品层面"为什么长这样"（三次改版 的历史与取舍）见 `docs/WHITEPAPER.md` §7；本文件只管"现在长什么样、怎么用"。  设计语言基准：Notion 的生产环境视觉规则（扁平、不透明、极淡边框、零装饰）， 换成紫色主色调，外加游戏化元素（技能树连线、力场环、体力条）局部叠加， 但游戏化元素本身也遵守"不用发光/模糊/渐变"这条纪律。  ---  ## 1. 设计原则  1. **扁平、不透明**：任何表面都是纯色背景，禁止 `backdrop-filter`、渐变、    `box-shadow` 光晕。面板背景等于页面背景，仅靠 1px 边框分隔（这是 Notion    真实使用的规则，不是简化版）。 2. **低视觉熵**：界面本身的信息密度压到最低，注意力留给审计官的追问和技能树    的结构，不是靠界面本身抓眼球。 3. **紫色是唯一强调色**：`--accent` 系统贯穿按钮、边框高亮、力场"专注"档、    技能树"已解锁"连线。不额外引入其他高饱和色系当作品牌色；`--info`（青色）    仅用于"任务型节点"标签，做类别区分，不是第二强调色；`--danger`（红）和    `#facc15`（金）是状态色（失败/已掌握），不是品牌色。 4. **深浅主题对等**：每个 token 在 `:root` 和 `:root[data-theme='light']`    里都有对应值，对比度纪律两边一致（下文有具体数值）。 5. **游戏感来自结构，不是装饰**：技能树"像游戏"的关键是节点之间画连线、    解锁路径用颜色区分，不是加光效——连线本身也是纯色 stroke，不发光。  ---  ## 2. 颜色 Token  定义在 `frontend/src/index.css` 的 `:root` / `:root[data-theme='light']`。  | Token | 深色 | 浅色 | 用途 | |---|---|---|---| | `--bg` | `#191919` | `#ffffff` | 页面背景 | | `--panel` | `#191919` | `#ffffff` | 面板背景（=页面背景，靠边框分隔） | | `--panel-translucent` | `#202020` | `#ffffff` | nav / 紧凑分身徽章背景，比 panel 略深一档 | | `--border` | `rgba(255,255,255,.09)` | `rgba(55,53,47,.09)` | 极淡分隔线（nav 底边等） | | `--border-strong` | `rgba(255,255,255,.13)` | `rgba(55,53,47,.16)` | 面板/输入框轮廓、锁定态连线 | | `--hover-wash` | `rgba(255,255,255,.055)` | `rgba(55,53,47,.08)` | 按钮 hover 底色、进度条未填充轨道底色 | | `--text` | `#e9e9e7` | `#37352f` | 正文/标题文字 | | `--dim` | `#9b9b96` | `#787774` | 次要文字（状态标签、说明文字） | | `--accent` | `#c4b5fd` | `#7c3aed` | 主强调色：可用状态边框、聚焦力场高档、技能树已解锁连线 | | `--accent-strong` | `#a78bfa` | `#6d28d9` | tag 文字色、力场/连线用色比 `--accent` 略深 | | `--accent-fill` | `#7c3aed` | `#6d28d9` | 主按钮（`.accent`）实心填充 | | `--accent-tag-bg` | `rgba(196,181,253,.16)` | `#f3effc` | concept 类型标签背景 | | `--info` / `--info-strong` | `#67e8f9` | `#0e7490` | task 类型标签用色 | | `--info-tag-bg` | `rgba(103,232,249,.14)` | `#eafafd` | task 标签背景 | | `--danger` | `#ff6b6b` | `#c9362c` | 审计失败、力场低专注档 | | `#facc15`（无 token，硬编码） | 同左 | 同左 | "已掌握"状态色、Sanity 条填充色——刻意独立于 accent 系统，是"成就金"不是品牌色 |  对比度基准：`--text` on `--bg`（`#e9e9e7`/`#191919` 深色，`#37352f`/`#ffffff` 浅色）取自 Notion 官方生产配色，两边都远超 WCAG AA。`--dim` 用于次要文字， 不用于正文大段内容。  ---  ## 3. 字体与间距  - 字体栈：`ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, "Apple Color Emoji", Arial, sans-serif, "Segoe UI Emoji", "Segoe UI Symbol"`   （Notion 官方字体栈原样照搬）。 - 标题（h1-h3）：`font-weight: 600`，颜色与正文相同（不用彩色标题），   `letter-spacing: -0.01em`。 - 圆角：`--radius-control: 4px`（按钮/输入框），`--radius-panel: 6px`（面板），   `--radius-pill: 999px`（tag、力场环、进度条）。 - 面板内边距：`--gap: 20px`。  ---  ## 4. 组件规则  ### 4.1 Panel（`.panel`） 纯色背景 + 1px `--border-strong` 边框，零阴影。任何"卡片"都是这个， 不做 elevation 分层。  ### 4.2 Button - 默认态：透明背景、无边框，只有文字/图标，hover 才出现 `--hover-wash` 底色   （Notion 的"低调按钮"规则——按钮在不用的时候几乎隐形）。 - `.accent`（主操作按钮）：`--accent-fill` 实心填充 + `--accent-fill-text`   文字，hover 降透明度到 0.9，不变色不加阴影。 - `disabled`：`opacity: 0.4`。  ### 4.3 Tag（`.tag`） 药丸型徽章（`border-radius: pill`），用于分类标签（技能节点的 concept/task 类型）。背景用对应类别的 `*-tag-bg`，文字用 `*-strong`。 **不要用纯色文字代替 tag**——这是本项目踩过的坑（Liquid Glass 阶段遗留）， Notion 的分类标签惯例就是填色徽章，不是彩色文字。  ### 4.4 Input / Textarea `--panel` 背景、`--border-strong` 边框、`--radius-control` 圆角。 聚焦态：边框变 `--accent` + 2px accent 描边（`outline-offset: -1px`， 描边画在边框内侧，不额外占布局空间）。  单选框/复选框单独一条规则，从这条 input 规则里摘出来： `accent-color: var(--accent)`，覆盖浏览器默认的蓝色原生控件配色。  ### 4.5 Bar（体力条 / Sanity 条，`Avatar.tsx` 内部组件） 轨道（track）用 `--hover-wash` 背景 + `--border-strong` 边框——**不要用 `--bg` 或 `--panel` 做轨道底色**，那两个和页面背景同色，未填充部分会完全 看不出来（这是实际踩过的 bug，2026-07-19 修复）。填充部分用传入的强调色。 Sanity 条的轨道宽度本身随 `sanity_cap` 缩放（不是固定满宽），体现"体力 影响精神值上限"这条规则。  ### 4.6 Force Field（力场环，专注度可视化） 纯色描边环，按 `focus_score` 分四档（idle/low/mid/high），颜色区分档位， **不用 blur/box-shadow 光晕/动画**——这是从 Liquid Glass 阶段的发光效果 简化来的，符合 Notion 语言的"零装饰"要求。  ### 4.7 技能树连接线（`.skill-edge`，2026-07-19 新增） 技能树节点之间的父子连线，SVG 描边路径，不填充（`fill: none`）。 - `.skill-edge--locked`：`--border-strong` 描边，1.5px，虚线（`stroke-dasharray: 4 4`）。 - `.skill-edge--active`（子节点状态为 available/mastered）：`--accent`   描边，2.5px，实线。 两档用粗细+虚实+颜色三重区分，保证在深浅两个主题下都能一眼看出"哪条路径 已经点亮"——这是解决"技能树没有游戏感"这个问题的核心手段，连线比配色更 关键：没有连线，卡片列表不管怎么调色都不会像一棵树。  ### 4.8 Nav `sticky` 顶部导航，`--panel-translucent` 背景（比页面背景深一档， 不透明，不是玻璃），底部 1px `--border` 分隔线。  ---  ## 5. 已知取舍 / 不做的事  - 不做卡片阴影分层（elevation）——Notion 的扁平语言里内容靠边框分隔，   不靠阴影暗示层级。 - 不做玻璃/模糊效果——Liquid Glass 版本已经试过并被否决（用户原话   "简直是屎"），根因是背景太素净导致模糊效果不可见，详见白皮书 §7。 - 力场/连线的"游戏感"来自结构化视觉反馈（连线、颜色档位），不靠动画/光效   堆砌——两次改版的教训都是"装饰越多越像在遮丑"，克制是有意为之。  ---  ## 6. 待办 / 已知不足  - Avatar 的像素小人（`PixelFigure`）明确是占位符（代码注释里写死了），   不是最终美术资源，不需要为它抠细节。 - 技能树连线依赖 `getBoundingClientRect()` 做实际测量定位，在 jsdom 测试   环境下无法获得真实布局（永远返回 0），测试只验证连线元素存在/状态样式   正确，不验证像素坐标。