import json

from app.llm.base import Message

_FIRST_PROBE = "为什么这个方法能生效？如果去掉关键的那一步，会发生什么？"
_ERROR_INJECTION_PROBE = (
    "听你这么说，这东西好像在任何情况下都成立、没有例外——这样理解对吗？"
)
_PASS_KEYWORDS = ("因为", "如果", "边界", "条件", "例外", "不对", "不是")

_TASK_PROBE = "具体打算怎么做？说清楚步骤。"
_TASK_HOLLOW_PHRASES = ("随便", "应该可以", "大概", "反正", "不知道")

_TASK_ORIENTED_KEYWORDS = ("把", "怎么", "如何", "部署", "搭建", "实现", "写一个", "做一个", "上线", "完成")


class MockProvider:
    """确定性脚本化审计：不调用任何外部模型，用于离线演示与 CI 测试。

    概念型（concept）协议：第一轮追问"为什么"，第二轮埋错试探，第三轮起强制裁决。
    任务型（task）协议：只问一次"具体怎么做"，答案不空洞就从宽通过，不做埋错试探——
    这是因为任务型节点验证的是"有没有做到"，不是"能不能讲清楚原理"。
    """

    name = "mock"

    def complete(self, messages: list[Message]) -> str:
        system = next((m["content"] for m in messages if m["role"] == "system"), "")
        if "原则蒸馏官" in system:
            return self._distill(messages)
        if "技能树规划官" in system:
            return self._generate_tree(messages)
        if "任务核验官" in system:
            return self._audit_task(messages)
        return self._audit_concept(messages)

    @staticmethod
    def _generate_tree(messages: list[Message]) -> str:
        topic = next((m["content"] for m in messages if m["role"] == "user"), "").strip() or "新主题"
        is_task_oriented = any(kw in topic for kw in _TASK_ORIENTED_KEYWORDS)
        node_type = "task" if is_task_oriented else "concept"
        # 任务型主题（比如"把大象放进冰箱"）本身就是一整个要做的事，根节点也该是
        # task，不该被当成需要讲清楚原理的知识点——这正是本文件要纠正的那个 bug。
        nodes = [
            {
                "slug": "root",
                "title": topic[:16],
                "description": f"{topic}的整体目标" if is_task_oriented else f"{topic}的入门整体理解",
                "parent_slug": None,
                "node_type": node_type,
            },
            {
                "slug": "core",
                "title": f"{topic[:12]}·第一步" if is_task_oriented else f"{topic[:12]}的核心机制",
                "description": f"{topic}要先完成的第一个具体步骤"
                if is_task_oriented
                else f"支撑{topic}成立的关键原理",
                "parent_slug": "root",
                "node_type": node_type,
            },
            {
                "slug": "boundary",
                "title": f"{topic[:12]}·第二步" if is_task_oriented else f"{topic[:12]}的边界情况",
                "description": f"{topic}要完成的第二个具体步骤"
                if is_task_oriented
                else f"{topic}在什么条件下失效或需要特别处理",
                "parent_slug": "root",
                "node_type": node_type,
            },
            {
                "slug": "apply",
                "title": f"{topic[:12]}·收尾确认" if is_task_oriented else f"{topic[:12]}的实战应用",
                "description": f"确认{topic}整体是不是真的做完了"
                if is_task_oriented
                else f"把{topic}用到一个具体问题里",
                "parent_slug": "core",
                "node_type": node_type,
            },
        ]
        return json.dumps(nodes)

    @staticmethod
    def _distill(messages: list[Message]) -> str:
        reflection = next((m["content"] for m in messages if m["role"] == "user"), "").strip()
        if reflection:
            body = f"当我再次面对同类问题时，我将记住这次的教训：{reflection[:40]}"
        else:
            body = "当我再次面对同类问题时，我将先讲清楚为什么，再给结论。"
        return json.dumps({"title": "先讲机制，再讲结论", "body": body})

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
