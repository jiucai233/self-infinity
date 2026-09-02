"""叙述官（Narrator）：把画像里的事实讲成一段关于这个用户的话。

系统对用户的了解一直是分散且沉默的——技能状态在技能树页、原则在归档页、体力在角色
页，misconception 更是只在反思提交后弹一次就再也见不到。Narrator 是那个把它们合起来
开口说话的角色，也是白皮书 §4.5 那句"养成对象是用户自己的赛博分身"在系统图上第一次
有对应物。

**职责边界**：所有事实由 app/services/profile.py 算好（纯 DB，零 LLM），这里只负责
把事实讲成话。之所以要用模型而不是模板拼字符串：把"横跨统计学和投资两个不相关领域的
同一个心智模型"讲成一句有分量的人话，是规则代码写不出来的，而这恰好是这个角色存在的
全部理由。反过来，任何"算出来"的部分都不该交给模型——它会算错。
"""

import json
import logging

from app.llm.base import LLMProvider, Message, complete_with_json_retry
from app.services.profile import LearnerProfile

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """\
你是叙述官（Narrator），负责把系统掌握的事实讲成一段写给用户本人的话。

写作规则：
1. 只能引用下面「事实」里给出的内容。绝对不能编造没发生过的审计、不存在的技能点、
   或者事实里没有的数字——用户会拿这段话对照自己的记录，编一个就全盘失信。
2. 如果某个错误心智模型被标记为「跨领域」，必须点名它具体横跨了哪几个领域。这是
   系统能说出而通用聊天助手说不出的话，是这段叙述里最有价值的一句，不要写成
   "你在多个领域都有问题"这种含糊说法。
3. 不打鸡血，不安慰，不用"加油""相信自己"这类话。用户来这里是为了知道真相，
   不是为了被哄。同样也不要刻薄或说教。
4. 陈述句，第二人称，150 字以内。事实少的时候就少说，不要为了凑字数灌水。
5. 如果事实里几乎没有内容（新用户），就如实说明还没有足够记录，并指出接下来做什么
   能产生第一批数据。不要假装了解这个人。

事实：
{facts}

只输出严格 JSON：{{"narrative": "<这段话>"}}
不要输出 JSON 之外的任何文字。
"""


def format_facts(profile: LearnerProfile) -> str:
    """把画像摊成给模型看的事实清单。

    刻意用朴素的键值行而不是 JSON dump：模型对自然语言标签的理解比对字段名稳，
    而且这段会进 prompt，可读性直接影响可调试性。
    """
    lines = [
        f"- 技能节点：共 {profile.total_skills} 个，已掌握 {profile.mastered_skills} 个，"
        f"当前可挑战 {profile.available_skills} 个",
        f"- 审计记录：共 {profile.total_audits} 场，通过 {profile.passed_audits} 场，"
        f"未通过 {profile.failed_audits} 场",
    ]
    if profile.pass_rate is not None:
        lines.append(f"- 通过率：{profile.pass_rate * 100:.0f}%")
    if profile.health is not None:
        lines.append(f"- 体力值 Health：{profile.health:.0f}")
    if profile.sanity is not None:
        lines.append(f"- 精神值 Sanity：{profile.sanity:.0f}")
    if profile.focus_score is not None:
        lines.append(f"- 最近一次专注度：{profile.focus_score}")

    if not profile.clusters:
        lines.append("- 错误心智模型：暂无记录（还没有失败并完成反思的审计）")
    else:
        lines.append(f"- 错误心智模型：识别出 {len(profile.clusters)} 个")
        for cluster in profile.clusters:
            skills = "、".join(dict.fromkeys(cluster.skills))
            tag = "【跨领域】" if cluster.cross_domain else ""
            lines.append(
                f"    · {tag}「{cluster.label}」发作 {cluster.occurrences} 次，"
                f"出现在这些技能点上：{skills}"
            )

    return "\n".join(lines)


class Narrator:
    def __init__(self, provider: LLMProvider):
        self._provider = provider

    def narrate(self, profile: LearnerProfile) -> str:
        messages: list[Message] = [
            {"role": "system", "content": SYSTEM_PROMPT.format(facts=format_facts(profile))},
            {"role": "user", "content": "请给出这段叙述。"},
        ]
        logger.info("narrator.narrate() calling provider=%s", self._provider.name)
        raw = complete_with_json_retry(self._provider, messages)
        try:
            narrative = json.loads(raw)["narrative"]
        except (json.JSONDecodeError, KeyError, TypeError):
            logger.warning("narrator returned unusable output", exc_info=True)
            raise ValueError("叙述官未产出有效内容")
        if not isinstance(narrative, str) or not narrative.strip():
            raise ValueError("叙述官返回了空内容")
        return narrative.strip()
