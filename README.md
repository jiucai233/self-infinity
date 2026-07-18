# Self-Infinity

把「学习验证」做成游戏机制的全栈应用：想点亮技能树上的节点，必须先通过 LLM 扮演的
**费曼审计官**的压力测试——解释得了直觉、扛得住追问、识破得了故意埋下的错误，才能合成
「原理方块」；审计失败则强制反思，反思会被提炼成「原则卷轴」长期存档。

> **命名约定（对外口径与代码保持一致）**：本项目的奖励机制是确定性的激励引擎
> (RL-inspired)，不是强化学习；Auditor / Scribe 是多角色 Agent 编排，不是多智能体博弈。

## 已实现功能

- **技能树**：`locked → available → mastered`，通过审计解锁子节点；主题/大任务经 Architect 拆解自动生成
- **两套审计协议**：concept 节点走费曼审计（多轮追问 + 故意埋错检验），task 节点走任务核验（从宽裁决，不深挖原理）
- **语音输入**：浏览器 Web Speech API 转写，接入既有文本审计流程
- **原则卷轴**：审计失败 → 强制反思 → LLM 提炼为「当…时，我将…」的可执行原则；历史原则会被检索并注入下一次相关审计的上下文
- **激励引擎**：审计通过按 `base × difficulty × level_multiplier^level` 确定性结算奖励（非学习算法）
- **体力系统**：每日签到（花销/运动/饮食三项自评）驱动 Health/Sanity，Sanity 上限与恢复速度随 Health 变化
- **赛博分身可视化**：力场环随专注度评分（由审计追问间隔推导）变化，体力条随体力系统数值联动

## 架构

```
frontend (React + Vite + TS, 像素极简风)
    │  /api (vite dev proxy)
    ▼
backend (FastAPI + SQLite)
    routers → agents (auditor / scribe) → llm provider 抽象
                                            ├─ GeminiProvider (设 GEMINI_API_KEY 时)
                                            └─ MockProvider   (默认, 离线可演示)
```

## 快速开始

后端（需要 Python 3.10+）：

```bash
cd backend
python3.13 -m venv .venv && source .venv/bin/activate   # 或 uv venv --python 3.13
pip install -r requirements.txt
uvicorn app.main:app --reload    # API 文档: http://127.0.0.1:8000/docs
```

前端：

```bash
cd frontend
npm install
npm run dev                      # http://localhost:5173
```

## LLM 配置

不配置任何环境变量时使用内置 **MockProvider**（脚本化审计，全流程可离线演示）。
接真模型：在 `backend/.env` 写入

```
GEMINI_API_KEY=your-key
LLM_MODEL=gemini-2.5-flash    # 可替换为 gemini-3 系列的 model id
```

## 校准评估（M2 验收）

`backend/eval/` 下有 30 条人工标注的审计场景（概念/任务对半，通过/不通过对半）和一个
离线评估脚本，用于衡量裁决准确率与「放水率」（本该不通过却被判通过的比例）：

```bash
cd backend
.venv/bin/python eval/run_calibration.py --provider mock     # 离线冒烟，非验收基准
.venv/bin/python eval/run_calibration.py --provider gemini    # 配置 GEMINI_API_KEY 后的真实验收
```

M2 验收线：真实模型跑 30 条校准集，准确率 ≥ 80%，放水率 ≤ 10%。详见 `backend/eval/README.md`。

## 路线图

- **V1** 费曼审计闭环 ✅
- **V1.1** 语音讲解 ✅（浏览器 Web Speech API 转写接入既有文本审计流程，非直传多模态模型）
- **M3** 原则检索注入 ✅（字符/词元重叠检索，非向量检索）
- **M4** 激励引擎 ✅ + 专注力场可视化 ✅（focus score 由审计追问间隔推导，非桌面屏幕监控）+ 体力系统 ✅
- **M5** 用户维度评估（n=5-10 轻量实验，待真实使用数据）
- **V2.1** 可学习组件：contextual bandit 根据完成/放弃率动态调节任务难度
- **V3** 移动端（Screen Time 类别用量阈值；iOS 不允许截图其他 App，不做截图监控）
