import json
import logging
import re
import time

from app.llm.base import Message

logger = logging.getLogger(__name__)

# Deterministic stand-in for "the LLM decided these two principles conflict"
# — a real provider judges this from meaning, but a scripted mock has no
# meaning to judge, so tests that want a contradiction fixture just put this
# literal marker in a principle's body.
_CONTRADICTS_MARKER = "刻意矛盾"
_CANDIDATE_LINE_RE = re.compile(r"^\[(\d+)\] \((\w+)\) (.+?) —— (.*)$")
_MISCONCEPTION_LINE_RE = re.compile(r"^- (.+)$")
# Challenger 的替身判据：用户这轮说的话和某条历史 misconception 文本重叠到这个
# 程度就算"又落进去了"。真 provider 判的是语义，脚本只能判重叠——和 _link 同样的
# 妥协。阈值比 retrieval 的复发检测更高：那边比的是两条同为一句话的 misconception，
# 这边拿整段回答去比，偶然重合的机会大得多。
_CHALLENGE_THRESHOLD = 8
# Narrator 的替身从事实清单里认这两个标记：跨领域簇的前缀，以及簇行的起始符号。
_CROSS_DOMAIN_MARKER = "【跨领域】"
_CLUSTER_LINE_RE = re.compile(r"^·\s*(?:【跨领域】)?「(.+?)」发作 (\d+) 次，出现在这些技能点上：(.+)$")
_PLAN_NODE_RE = re.compile(r"^- skill_id=(\d+) 「(.+?)」（(\w+)，难度 (\w+)）")
_SUGGESTED_TIER_RE = re.compile(r"难度调度器建议的档位：(\w+)")
_SEARCH_SKILL_RE = re.compile(r"讲解「(.+?)」")
_CANDIDATE_INDEX_RE = re.compile(r"^\[(\d+)\] ")

_FIRST_PROBE = "为什么这个方法能生效？如果去掉关键的那一步，会发生什么？"
_ERROR_INJECTION_PROBE = (
    "听你这么说，这东西好像在任何情况下都成立、没有例外——这样理解对吗？"
)
_PASS_KEYWORDS = ("因为", "如果", "边界", "条件", "例外", "不对", "不是")

_TASK_PROBE = "具体打算怎么做？说清楚步骤。"
_TASK_HOLLOW_PHRASES = ("随便", "应该可以", "大概", "反正", "不知道")

_TASK_ORIENTED_KEYWORDS = ("把", "怎么", "如何", "部署", "搭建", "实现", "写一个", "做一个", "上线", "完成")

_KNOWN_VAGUE_TOPICS = ("做饭", "强化学习", "我要学编程", "编程", "学习")
_CLARIFY_QUESTIONS = ("你想深入哪个具体方向/菜系/流派？", "你希望学到什么深度——入门认知还是能实际动手做？")


class MockProvider:
    """确定性脚本化审计：不调用任何外部模型，用于离线演示与 CI 测试。

    概念型（concept）协议：第一轮追问"为什么"，第二轮埋错试探，第三轮起强制裁决。
    任务型（task）协议：只问一次"具体怎么做"，答案不空洞就从宽通过，不做埋错试探——
    这是因为任务型节点验证的是"有没有做到"，不是"能不能讲清楚原理"。
    """

    name = "mock"

    def complete(self, messages: list[Message]) -> str:
        start = time.perf_counter()
        system = next((m["content"] for m in messages if m["role"] == "system"), "")
        if "检索规划官" in system:
            result = self._search_queries(messages)
        elif "资料筛选官" in system:
            result = self._search_select(messages)
        elif "下一步推荐官" in system:
            result = self._recommend(messages)
        elif "叙述官" in system:
            result = self._narrate(messages)
        elif "审计复核官" in system:
            result = self._challenge(messages)
        elif "原则蒸馏官" in system:
            result = self._distill(messages)
        elif "关联图书管理员" in system:
            result = self._link(messages)
        elif "澄清官" in system:
            result = self._clarify(messages)
        elif "课程编排官" in system:
            result = self._generate_tree(messages)
        elif "任务核验官" in system:
            result = self._audit_task(messages)
        else:
            result = self._audit_concept(messages)
        elapsed_ms = (time.perf_counter() - start) * 1000
        logger.info("mock complete() success elapsed_ms=%.0f", elapsed_ms)
        return result

    @staticmethod
    def _clarify(messages: list[Message]) -> str:
        topic = next((m["content"] for m in messages if m["role"] == "user"), "").strip()
        is_vague = any(kw in topic for kw in _KNOWN_VAGUE_TOPICS)
        if is_vague:
            return json.dumps({"needs_clarification": True, "questions": list(_CLARIFY_QUESTIONS)})
        return json.dumps({"needs_clarification": False, "questions": []})

    @staticmethod
    def _generate_tree(messages: list[Message]) -> str:
        """确定性课程编排。

        树的形状刻意做成"根是容器、叶子才具体"，并且给出一条**兄弟之间**的先修边
        （基础 → 进阶）。兄弟先修是树结构表达不了、只能靠先修图承载的那种关系，
        离线测试必须覆盖到它，否则先修和父子的区别在测试里就看不出来。
        """
        topic = next((m["content"] for m in messages if m["role"] == "user"), "").strip() or "新主题"
        is_task_oriented = any(kw in topic for kw in _TASK_ORIENTED_KEYWORDS)
        node_type = "task" if is_task_oriented else "concept"
        nodes = [
            {
                "slug": "root",
                "title": topic[:16],
                "description": f"「{topic}」这门课覆盖的范围",
                "parent_slug": None,
                "node_type": node_type,
            },
            {
                "slug": "basics",
                "title": f"{topic[:12]}·基础",
                "description": f"{topic}里最先要会的那个具体东西",
                "parent_slug": "root",
                "node_type": node_type,
            },
            {
                "slug": "advanced",
                "title": f"{topic[:12]}·进阶",
                "description": f"{topic}里建立在基础之上的具体方法",
                "parent_slug": "root",
                "node_type": node_type,
            },
            {
                "slug": "applied",
                "title": f"{topic[:12]}·应用",
                "description": f"把{topic}用到一个具体问题里",
                "parent_slug": "advanced",
                "node_type": node_type,
            },
        ]
        prerequisites = [
            {"from": "basics", "to": "advanced", "reason": "mock: 进阶建立在基础之上（树上是兄弟）"}
        ]
        return json.dumps({"nodes": nodes, "prerequisites": prerequisites})

    @staticmethod
    def _link(messages: list[Message]) -> str:
        # Deterministic stand-in for the Librarian: reuses the same
        # word/bigram overlap heuristic app/agents/retrieval.py uses
        # elsewhere, purely so offline tests have *something* non-trivial to
        # assert on — a real provider judges this from meaning, not overlap.
        from app.agents.retrieval import relevance_score

        system = next((m["content"] for m in messages if m["role"] == "system"), "")
        title_match = re.search(r"标题：(.*)", system)
        body_match = re.search(r"内容：(.*)", system)
        new_text = f"{title_match.group(1) if title_match else ''} {body_match.group(1) if body_match else ''}"

        related = []
        contradicts = []
        for line in system.splitlines():
            m = _CANDIDATE_LINE_RE.match(line.strip())
            if not m:
                continue
            ref, kind, ctitle, ctext = int(m.group(1)), m.group(2), m.group(3), m.group(4)
            if kind == "principle" and _CONTRADICTS_MARKER in ctext:
                contradicts.append({"ref": ref, "reason": "mock: 检测到刻意矛盾标记"})
                continue
            if relevance_score(new_text, f"{ctitle} {ctext}") > 0:
                related.append({"ref": ref, "reason": "mock: 关键词重叠"})

        return json.dumps({"related": related[:4], "contradicts": contradicts})

    @staticmethod
    def _search_queries(messages: list[Message]) -> str:
        system = next((m["content"] for m in messages if m["role"] == "system"), "")
        m = _SEARCH_SKILL_RE.search(system)
        skill = m.group(1) if m else "未知主题"
        return json.dumps({"queries": [f"{skill} 原理", f"{skill} 常见误区"]})

    @staticmethod
    def _search_select(messages: list[Message]) -> str:
        """挑前两条候选。真 provider 判的是"这条能不能补上缺口"，脚本只能按位置挑。"""
        system = next((m["content"] for m in messages if m["role"] == "system"), "")
        indices = [
            int(m.group(1))
            for line in system.splitlines()
            if (m := _CANDIDATE_INDEX_RE.match(line.strip()))
        ]
        return json.dumps(
            {"picks": [{"index": i, "reason": f"mock: 第 {i} 条候选与缺口相关。"} for i in indices[:2]]}
        )

    @staticmethod
    def _recommend(messages: list[Message]) -> str:
        """确定性排序：建议档位匹配的节点优先，其余按原顺序补齐，最多 3 步。

        这个"优先匹配 bandit 建议档位"的行为刻意和 SkillTree 页的推荐排序保持一致
        （见 app/routers/skills.py 的 get_recommendation），这样离线演示里两处给出的
        建议不会互相打架。
        """
        system = next((m["content"] for m in messages if m["role"] == "system"), "")
        tier_match = _SUGGESTED_TIER_RE.search(system)
        suggested = tier_match.group(1) if tier_match else ""

        matched: list[tuple[int, str, str]] = []
        others: list[tuple[int, str, str]] = []
        for line in system.splitlines():
            m = _PLAN_NODE_RE.match(line.strip())
            if not m:
                continue
            entry = (int(m.group(1)), m.group(2), m.group(4))
            (matched if m.group(4) == suggested else others).append(entry)

        ordered = (matched + others)[:3]
        steps = [
            {
                "skill_id": skill_id,
                "rationale": f"mock: 难度 {tier} 与当前建议档位 {suggested or '未知'} 的匹配结果，排在第 {i + 1} 位。",
                "focus_hint": f"mock: 讲「{title}」时先说清楚它为什么成立。",
            }
            for i, (skill_id, title, tier) in enumerate(ordered)
        ]
        return json.dumps({"steps": steps})

    @staticmethod
    def _narrate(messages: list[Message]) -> str:
        """确定性叙述：真 provider 写的是人话，脚本只能按模板填空。

        刻意保留"点名跨领域涉及哪些技能"这一条行为——那是 Narrator 存在的核心理由，
        离线演示和测试都需要它可见，其余措辞则不必模仿。
        """
        system = next((m["content"] for m in messages if m["role"] == "system"), "")

        cross_domain: list[tuple[str, str]] = []
        total_clusters = 0
        for line in system.splitlines():
            m = _CLUSTER_LINE_RE.match(line.strip())
            if not m:
                continue
            total_clusters += 1
            if _CROSS_DOMAIN_MARKER in line:
                cross_domain.append((m.group(1), m.group(3)))

        if not total_clusters:
            return json.dumps({"narrative": "还没有足够的失败记录可供分析。先完成一次审计。"})

        if cross_domain:
            label, skills = cross_domain[0]
            narrative = (
                f"你有 {total_clusters} 个反复出现的错误心智模型，"
                f"其中「{label}」横跨了{skills}——问题不在某个知识点上。"
            )
        else:
            narrative = f"你有 {total_clusters} 个反复出现的错误心智模型，目前都集中在单个技能点上。"
        return json.dumps({"narrative": narrative})

    @staticmethod
    def _challenge(messages: list[Message]) -> str:
        from app.agents.retrieval import relevance_score

        system = next((m["content"] for m in messages if m["role"] == "system"), "")
        answers = " ".join(m["content"] for m in messages if m["role"] == "user")

        for line in system.splitlines():
            m = _MISCONCEPTION_LINE_RE.match(line.strip())
            if not m:
                continue
            misconception = m.group(1)
            if relevance_score(answers, misconception) >= _CHALLENGE_THRESHOLD:
                return json.dumps(
                    {
                        "action": "overturn",
                        "question": f"你刚才的说法里，是不是又假定了「{misconception}」？说说这里为什么不是。",
                        "reason": f"mock: 与历史 misconception 文本重叠 —— {misconception}",
                    }
                )

        return json.dumps({"action": "uphold", "reason": "mock: 未命中任何历史 misconception"})

    @staticmethod
    def _distill(messages: list[Message]) -> str:
        reflection = next((m["content"] for m in messages if m["role"] == "user"), "").strip()
        if reflection:
            body = f"当我再次面对同类问题时，我将记住这次的教训：{reflection[:40]}"
        else:
            body = "当我再次面对同类问题时，我将先讲清楚为什么，再给结论。"
        return json.dumps(
            {
                "title": "先讲机制，再讲结论",
                "body": body,
                "misconception": "以为记住结论就等于理解了机制",
            }
        )

    def _audit_concept(self, messages: list[Message]) -> str:
        user_turns = [m for m in messages if m["role"] == "user"]
        turn_index = len(user_turns)

        if turn_index == 1:
            return json.dumps({"action": "probe", "question": _FIRST_PROBE})
        if turn_index == 2:
            return json.dumps({"action": "probe", "question": _ERROR_INJECTION_PROBE})

        combined = " ".join(m["content"] for m in user_turns)
        hit_keywords = sum(1 for kw in _PASS_KEYWORDS if kw in combined)
        passed = len(combined) >= 60 and hit_keywords >= 2

        if passed:
            verdict = {
                "action": "verdict",
                "pass": True,
                "score": 82,
                "gaps": [],
                "comment": "能抓住核心机制，也顶住了埋错追问，边界条件说清楚了。",
            }
        else:
            verdict = {
                "action": "verdict",
                "pass": False,
                "score": 42,
                "gaps": ["未能清晰指出适用边界与例外情况", "面对故意错误的说法没有纠正"],
                "comment": "解释停留在复述层面，还没有触及第一性原理。",
            }
        return json.dumps(verdict)

    def _audit_task(self, messages: list[Message]) -> str:
        user_turns = [m for m in messages if m["role"] == "user"]
        turn_index = len(user_turns)

        if turn_index == 1:
            return json.dumps({"action": "probe", "question": _TASK_PROBE})

        combined = " ".join(m["content"] for m in user_turns)
        is_hollow = any(kw in combined for kw in _TASK_HOLLOW_PHRASES)
        passed = len(combined) >= 6 and not is_hollow

        if passed:
            verdict = {
                "action": "verdict",
                "pass": True,
                "score": 90,
                "gaps": [],
                "comment": "说清楚了具体怎么做，可以打勾了。",
            }
        else:
            verdict = {
                "action": "verdict",
                "pass": False,
                "score": 30,
                "gaps": ["还没说清楚具体打算怎么做"],
                "comment": "回答太空泛，说说具体步骤就行，不用讲原理。",
            }
        return json.dumps(verdict)
