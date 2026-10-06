"""JSON 重试包装：第一次输出不是合法 JSON 时带纠错提示重试一次（UT-29）。"""

from app.llm.base import JSON_RETRY_NOTICE, complete_with_json_retry


class Sequence:
    name = "sequence"

    def __init__(self, *outputs: str):
        self.outputs = list(outputs)
        self.seen: list[list[dict]] = []

    def complete(self, messages):
        self.seen.append(list(messages))
        return self.outputs[len(self.seen) - 1]


MESSAGES = [{"role": "system", "content": "s"}, {"role": "user", "content": "u"}]


def test_ut29_first_output_invalid_second_valid_returns_the_second():
    provider = Sequence("not json", '{"ok": true}')

    assert complete_with_json_retry(provider, MESSAGES) == '{"ok": true}'
    assert len(provider.seen) == 2


def test_the_retry_carries_a_correction_notice():
    provider = Sequence("not json", '{"ok": true}')

    complete_with_json_retry(provider, MESSAGES)

    assert provider.seen[1][-1] == {"role": "user", "content": JSON_RETRY_NOTICE}
    assert provider.seen[1][:-1] == MESSAGES


def test_valid_output_is_returned_without_a_retry():
    provider = Sequence('{"ok": true}')

    assert complete_with_json_retry(provider, MESSAGES) == '{"ok": true}'
    assert len(provider.seen) == 1


def test_retry_happens_only_once_and_the_second_output_is_returned_as_is():
    provider = Sequence("bad", "still bad")

    assert complete_with_json_retry(provider, MESSAGES) == "still bad"
    assert len(provider.seen) == 2
