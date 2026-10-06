# Self-Infinity 设计规范（Paper & Ember · Material 3 Light）

**唯一来源**：`app/lib/theme/`（token 与 Material 主题）和 `app/lib/widgets/`。页面代码不写颜色、圆角、字号、字体的字面量。值有冲突时以代码为准，并回头修本文件。

参考（2026-10-05，用户提供的录屏 `~/Movies/2026-10-05 18-17-18.mov`）：一个 Obsidian 创作工作台——暖灰纸面、几乎没有颜色、黑色胶囊主按钮、杂志式大标题、大数字小标签、一叠错开的纸卡片，以及整页唯一发光的东西：深色网格星座里的金色火花。

---

## 1. 原则

1. **对话是主角。** 右侧聊天面板是完整的对话记录；舞台上只放她当前说的话。
2. **纸面，不是屏幕。** 画布 `#E6E6E1`，舞台 `#F5F5F1`，侧栏深一档 `#EEEEE9`，卡片是浮起来的纸 `#FBFBF8`。圆角 20、间距 12。
3. **墨色是唯一的操作色。** 发送键、主按钮、链接、可挑战节点都是近黑 `#151514`；次按钮是一圈细描边。
4. **金色只给挣来的东西。** 通过、掌握、XP、火花用琥珀/金；失败用砖红。蓝色、Gemini 渐变全部去掉。
5. **整页只有一处发光**：人生树的深色面板（和水晶球里面）。其他地方安静。
6. **排版像杂志**：首页问候语 40 号、紧字距；数字用大号细字（30 / 400），标签用小号灰字。
7. **动效有意义**：场景切换淡入 + 轻微上移（220ms）；星座缓慢自转；通过时金色星光散开；节点卡片淡入上移。

---

## 2. Token（`lib/theme/tokens.dart`）

### 2.1 颜色 `AppColors`

| token | 值 | 用途 |
|---|---|---|
| `canvas` | `#E6E6E1` | 面板后面的画布 |
| `background` | `#F5F5F1` | 舞台面板 |
| `sidebar` | `#EEEEE9` | 左栏、聊天面板 |
| `surface` | `#FBFBF8` | 卡片（浮起来的纸） |
| `surfaceHigh` | `#EBEBE6` | 输入栏、她的气泡、hover |
| `userBubble` | `#E2E2DC` | 你的聊天气泡 |
| `outline` / `outlineStrong` | `#DEDED8` / `#C6C6BF` | 分割线 / 次按钮描边 |
| `textPrimary` / `textSecondary` / `textTertiary` | `#151514` / `#565651` / `#696963` | 文字三级（`textTertiary` 在 background / surface / surfaceHigh 上都 ≥ 4.5:1） |
| `primary` | `#151514` | 墨色：所有操作 |
| `primarySoft` / `glow` | `#ECF2C9` / `#D4E57E` | 浅柠檬：选中底色 / 选中与节点卡片的边缘光 |
| `success` / `successSoft` | `#8A5B0C` / `#F5E6C3` | 琥珀：通过、掌握、XP |
| `danger` / `dangerSoft` | `#A23B2C` / `#F2DCD6` | 失败、错误 |
| `locked` / `requires` | `#C9C9C2` / `#8F8F88` | 锁住的节点 / 技能图的边 |
| `night` / `nightHigh` | `#1A1A19` / `#2A2A28` | 人生树面板、水晶球内部 |
| `nightLine` / `nightText` / `nightMuted` | `#8E8E87` / `#EEEEE9` / `#6F6F69` | 夜色上的网格线 / 文字 / 暗点 |
| `ember` / `emberHot` / `emberRed` | `#F0B23E` / `#FFE0A0` / `#E0644E` | 夜色上的掌握节点与火花 / 失败节点 |
| `glass` | `#45453F → #242422 → #0E0E0D` | 烟色水晶球 |
| `magic` | `#3A2A10 → #B7791F → #F0B23E` | 古铜到金：思考微光、语音、庆祝 |

### 2.2 字体

两种字体：
- **展示衬线** `AppFonts.display` = Instrument Serif（OFL，打包在 `app/assets/fonts/`，只有 400 一个字重，另有斜体）。主题把 `display*` 和 `headlineLarge` 设成它；其他地方用 `AppTheme.serif(style)` 取（页面里不能写 `fontFamily:`）。不加粗。它没有中文/韩文字形：中文落到思源宋体 SC（Noto Serif SC），韩文落到 Noto Serif KR，都是 500 字重、按语言懒加载。
- 其余全部是 `AppFonts.sans` = Infinity Sans（Pretendard 的拉丁子集，按 OFL 改名；拉丁部分接近 Inter），字重 400 / 500 / 600，常驻。韩文落到同一设计的 Infinity Sans KR，中文落到思源黑体 SC（Noto Sans SC），切到对应语言时才加载（`lib/theme/font_loader.dart`）。来源、子集范围和重建方法见 `app/assets/fonts/README.md`。

| 样式 | 用途 |
|---|---|
| `displayMedium` 48 / 400 衬线，字距 -0.6 | 首页问候语（墨色，无渐变） |
| `displaySmall` 38 / 400 衬线，字距 -0.3 | 庆祝卡标题、审计裁决卡的结论 |
| `headlineLarge` 36 / 400 衬线 | 大数字（统计条、节点卡片、裁决卡的分数） |
| `AppTheme.serif(headlineSmall)` 斜体 | 身份宣言（左栏角色卡）；人生树顶上的引文用 `titleLarge` 的衬线斜体 |
| `headlineMedium` 24 / 600 | 节点卡片标题、手机上的问候语 |
| `headlineSmall` 20 / 600 | 舞台标题 |
| `titleMedium` 15 / 600 | 面板标题 |
| `bodyLarge` 16 / 400，行高 1.6 | 她的气泡、聊天正文 |
| `labelLarge` / `labelMedium` / `labelSmall` | 按钮 / 标签 / 大数字上方的小标签 |

### 2.3 尺寸

- 间距 4 / 8 / 12 / 16 / 24 / 32。
- 圆角：面板 `panel 20`、卡片 `card 16`、气泡 `bubble 20`、chip `8`、输入栏 `pill 28`。
- 阴影（柔、宽，像桌上的纸）：`input`（极淡）、`paper`（纸卡片）、`float`（节点卡片、庆祝卡、菜单；两层）。
- 布局：左栏 280、聊天面板 380、面板间距 12、舞台内容最宽 720、断点 900。

---

## 3. 组件

| 组件 | 规则 |
|---|---|
| **面板** | 白底、圆角 20、无边框；顶部 56 高的标题栏（`titleMedium` + 右侧折叠图标）。 |
| **输入栏** | `surfaceHigh` 填充的胶囊，无边框、聚焦时 1px 墨色边；左 ⊕，右侧发送键是墨色圆形（空输入时灰色）。语音键在框外，40px 圆形 `surfaceHigh`。 |
| **问候语**（scene 1） | `displayMedium`（手机 `headlineMedium`），墨色，居中；下面一行 `bodyLarge` 三级灰。 |
| **推荐卡片**（scene 1） | `surfaceHigh` 底、圆角 16、内边距 16，左上一个小图标，文字 `labelLarge`；最多两张并排（窄屏竖排）；hover 时底色加深。 |
| **她的气泡**（舞台） | `surfaceHigh` 底、圆角 20、尾巴指向 avatar；气泡上方一行小字是说话的 agent 名（`labelMedium`）。思考时气泡里是一条流动的古铜到金微光（三行骨架）。 |
| **你的最后一句**（舞台） | 发送后、她回答前，在输入栏上方右对齐显示一个 `userBubble` 小气泡；回答到达后淡出（它已经在聊天面板里）。审计页不用它：回答直接进对话列。 |
| **审计对话列**（scene 4-1） | 一列，最宽 720。顶部钉住说话人：形象 76 + 名字（`titleMedium`）+ 在做什么（`bodySmall` 三级灰），下面一条分隔线。之前的问题：agent 名（`labelSmall` 三级灰）+ `bodyMedium` 次要色；**当前的问题**：`AppTheme.serif(headlineMedium)`，行高 1.25；你的回答：右侧 `userBubble` 气泡。 |
| **裁决卡**（scene 4-1） | `surface` 底、圆角 16、`paper` 阴影，1px 边：通过 `ember`、失败 `outline`。`VERDICT`（`labelSmall`，字距 1.6）→ 结论（`displaySmall` 衬线，通过时琥珀）与分数（`headlineLarge` 衬线 + `pts`）同一基线 → `+N XP` → 评语 `bodyLarge` → 分隔线 + `What was missing` 与圆点列表（失败砖红点、通过灰点）→ 墨色主按钮 `Make a lesson card` + 文字按钮 `Back to node`。 |
| **聊天面板** | 你的话右对齐 `userBubble` 气泡（圆角 20，右上角 4）；她的话左对齐无气泡，左侧 28px 圆形 agent 小头像 + 名字 + 时间，正文 `bodyLarge`。日期分隔是居中的小字。新消息自动滚到底。 |
| **左栏** | 标题栏 `My character`：身份宣言、Win condition、Stakes、Main quests、Rules；三条属性条（`Lv 2 · 3/5`、`Cleared 4/12`、`Condition: …`），条高 8、圆角 4，填充墨色（Cleared 为琥珀，状态差为砖红）；Daily quests；Today。 |
| **统计条**（scene 2） | 进度环（细墨线，中间 `3/22`）+ 大数字小标签：`Cleared 3 / 22`、`Progress 13%`、`Ready`、`Audits`、`Lessons`。 |
| **人生树面板**（scene 2） | `night` 底、圆角 20。左上 `Tree | Outline` 胶囊切换；上方居中一行斜体身份宣言；左下图例；右下 `Drag to turn · tap a point`。 |
| **节点卡片**（scene 2） | 一叠纸：前面一张 `surface` 卡片（1px `glow` 边、`float` 阴影），后面错开两张更暗的纸。小号大写 kicker（`BOSS` / `MAIN QUEST` / `COURSE` / `YOU`）→ 标题 → 状态 chip → 大数字（Best / Attempts / Lessons）→ `Audit history`（日期、Passed/Failed、分数条）→ 教训卡 → 墨色 `Take it on`。 |
| **contents 卡片**（scene 4） | 白卡、1px `outline`、圆角 16。资料是一行一个：网站小图标位（首字母圆点）+ 标题 + 域名（次要色），整行可点。 |
| **技能图**（Outline 视图） | 圆点 14；可挑战 = 白底墨色描边，掌握 = 琥珀实心，失败 = 砖红实心，锁住 = 灰实心，Boss 多一圈；左下角图例。 |
| **庆祝卡片**（审计通过） | 舞台中央浮出的纸卡（`float` 阴影、圆角 20）：古铜到金的星光散开，`Cleared!` / `Boss cleared!` + 分数，`+N XP`（琥珀），等级提升时 `Lv N → N+1`，新解锁节点为浅柠檬 chip（点了进 scene 4）。 |
| **教训卡**（反思之后） | 卡片从背面翻到正面（300ms）：标题、正文、误解（红色小标签）。 |
| **形变图标**（`MorphIcon`，参考 Morphicons） | 线条图标放在 24 网格上，用折线描述；每笔重采样到同样多的点，在弹簧上移动（stiffness 420、damping 30，略过冲后很快停下）。笔画数不同时，多出来的那笔从另一形状最后一点长出或缩回。用在：发送键 → 等她回答时变成转圈（`ring`，转动），回来后变回箭头；∿ 悬停时竖条换一个节拍；听写麦克风 ↔ 停止方块；落地页 `Sign in` 悬停时箭头穿过一扇门（`signIn`）。动画关闭时直接到终态。 |
| **语音模式** | 输入栏变成 `surfaceHigh` 胶囊里的实时声波条（随音量跳动，古铜到金），上方一行状态字 `Listening… / Thinking… / Speaking…`，再上方是实时字幕（你说的话，灰色）。 |

---

### 3.x 落地页（登录前，`features/auth/landing_page.dart`）

- **一个画面讲完系统**：右边半身机器人（`assets/landing/robot.png`，AI 生成、去背景），掌心向上托着一颗深色小球，球里是转动的人生树（`LifeConstellation`）。左边打字机效果的衬线标题、一句话说明、“开始”胶囊按钮。
- **分屏翻页**：整页分 6 屏（开头、四章、结尾），不自由滚动——滚轮一下、触屏一划、↑↓ / PageUp / PageDown / 空格 / Home / End，各翻一屏，翻页动画 1.1 秒（easeInOutCubic）。触控板一次甩动只算一下（翻页中和余震期间的滚轮事件丢掉）。翻页过程中机器人跟着动：抬手、镜头升高。
- **滚动叙事**：四章（学 / 证明 / 记住 / 成长）依次淡入，球越来越大但始终在掌心上；最后一屏球铺满窗口变成夜空，只剩一句话和一个按钮。页头在夜空上自动变浅色。
- **3D 机器人**（Web）：`app/web/landing3d/`（three.js，`Robot3d` 用 iframe 嵌入，iframe 不接收指针，翻页仍归 Flutter）。页面把进度 0–5 发给场景，场景回报球在屏幕上的位置和半径；最后一屏人生树从这个位置长到铺满窗口。
  - 模型是 three.js 示例里的 Xbot（Mixamo 人偶），换成亮黑漆面 + 薄膜虹彩材质（`MeshPhysicalMaterial` 的 clearcoat / iridescence），反射一间带紫、青、品红灯条的暗房（`PMREMGenerator.fromScene`，不用外部贴图）。右臂、手指、头部按进度摆姿势：开头在锁骨前托球，最后把球举向镜头，头一直看着球；其余骨骼播 idle 动作。
  - 球是自写 shader：琥珀到金的玻璃，表层和深层两层流动光纹，边缘亮，有一点高光；球里是一棵小人生树（84 颗星、连到最近的前一颗），随进度从中心往外逐颗点亮。球的金光照在机器人身上。
  - 镜头每屏一个关键位，Catmull-Rom 插值：开头平视半身，到第四章接近俯视。桌面上画面整体右移 20%，球一直在左侧文字右边；手机上镜头更远、视角 40°、画面下移，机器人在下半屏。
  - 背景就是纸色 `AppColors.surface`，地面只留一层淡阴影。最后一屏被夜空盖满后场景停止渲染。
  - three.js 0.170 从 jsDelivr 加载；20 秒没准备好或没有 WebGL，就退回下面的影片。
- **页头**：品牌 + 逗号分隔的章节链接（点了滚到对应章）+ 语言 + 下划线 “Sign in”；手机上链接收进汉堡菜单，语言只留地球图标。
- **滚动影片**（非 Web 平台，或 3D 起不来时）：一段机器人视频切成帧放在 `assets/landing/frames/`，由 `app/tool/landing_frames.py <视频>` 生成——平视、掌心托着发光金球 → 举手、镜头升高变俯视、球越来越大。页面按滚动位置显示对应帧，并按 `track.json` 里每帧的球心和半径把人生树贴在球上；影片播完球离开画面铺满窗口。脚本把每帧背景校成 `AppColors.surface`，页面和视频边缘无缝。
  - 现用视频：即梦（Dreamina）首尾帧生成，8 秒 1248×704，切 120 帧（约 4.4 MB）；命令 `landing_frames.py robot.mp4 --crop iw:ih-88:0:0`（裁掉底部水印条）。
  - 影片立在窗口底边：桌面占窗口高 90%（头不压导航），手机占 62%，顶边渐隐进纸色。影片随球横向平移：桌面上球始终在左侧文字右边，手机上球居中。
  - 球上的人生树底色只有 30% 夜色，金球透出来；离开影片铺满窗口时夜色补满。
- 没有影片（无 `track.json`）时退回静态图 `robot.png`：掌心位置按比例写在 `LandingPage.palm`（0.30, 0.71），图片比例 `robotAspect`。

## 4. 形象占位（`Avatar`）

黑色细线小人，和手绘稿一个画法。每个 agent 一个区别（发型 / 眼镜 / 帽子 / 领结）；front_desk 是魔法师（尖帽带星、长发、长袍），scene 1 用 `OrbAvatar` 手托水晶球。

**水晶球**（参考 React Bits Orb、react-ai-orb、Aceternity Sparkles 的做法，用 CustomPainter 自绘，不引入依赖）：
- 分层：烟色玻璃底（`glass`，左上受光）→ 三团古铜到金的雾气，各自慢速漂移 → 人生树星座 → 高光椭圆、边缘暗角、每 7 秒一道扫光 → 2.5px 线稿描边（和小人同粗）。
- **星图**（2026-10-05 起是 `LifeConstellation`，取代 `MiniTree`；下面是旧版说明，留作对照）：径向布局，根节点在球心，每一层是一圈，子树按叶子数分扇区，半径按平方根分布让外圈宽松；连线是向球心微弯的弧线。掌握 = 绿点带柔光，可挑战 = 白芯蓝环且在呼吸（每个节点相位错开），锁住 = 暗灰小点。
- **动效**：出场 1.2 秒，由内向外一圈圈出现，节点轻弹出现，连线从父节点画向子节点；平时整片星座 60 秒自转一圈，带轻微倾斜晃动；每 3.2 秒有一个光点沿一条连线由内向外跑；周围四颗星各自闪烁。
- **交互**：悬停时球放大到 1.04、雾气变浓、星座转速变成 3.5 倍、星星变大；按下缩到 0.97；点击进 scene 2。
- **人生树星座**（`LifeConstellation`，水晶球和 scene 2 共用）：你在球心（白点 + 四角星 + 暖光），一圈主线任务（空心环 + 中心点），再往外课程与节点；节点按叶子数分扇区、半径按平方根分布，每个节点有一点高度差，整盘绕竖轴 90 秒转一圈，带透视（远处变暗变小）。外面一层 120 个点的线框球壳（近邻连线 + 少量三角面），像录屏里的网格。掌握 = 金色实心带光晕、往上冒火花；失败 = 砖红；可挑战 = 白环呼吸；锁住 = 暗灰小环；Boss 多一圈细环。每 2.6 秒一个金色光点沿一条边由内向外跑。水晶球里是同一棵树的 `compact` 版（无文字、点更少）。
- 系统开启"减少动态效果"或在测试中：所有动效停止，直接显示最终画面。avatar 下方或气泡上方总有 agent 名字。聊天面板里的小头像是同一个形象的头部特写，放在 28px 圆里。3D 做好后按 agent 名替换。

---

## 5. 约束

- 页面里出现 `Color(0x…)`、非 token 的 `BorderRadius.circular`、`fontSize:`、`fontFamily:` 字面量视为违规；图标、头像、气泡最大宽度这类布局尺寸除外。
- `test/theme_test.dart` 锁定 token 值和主题关键规则；改 token 要同步改测试。
