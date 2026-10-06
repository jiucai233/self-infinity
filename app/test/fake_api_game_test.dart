// FakeApiClient, life as a game (contract Section 6): the profile and its
// limits, the journal, the reflection suggestion by KST time window (with an
// injected clock) and the no-LLM chat flow that answers it.
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/api_exception.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/api/reflection_prompts.dart';

/// A clock the test can move.
class Clock {
  Clock(this.now);
  DateTime now;
  DateTime call() => now;

  /// Sets “now” to [hour]:[minute] KST on [day] October 2026.
  void setKst(int hour, int minute, {int day = 5}) {
    now = DateTime.utc(2026, 10, day, hour, minute).subtract(const Duration(hours: 9));
  }
}

Future<ApiException> failure(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('expected an ApiException');
}

void main() {
  group('25 / 26 profile', () {
    test('a fresh database: empty strings, no rules, updated_at null', () async {
      final p = await FakeApiClient(latency: Duration.zero).getProfile();
      expect(p.identity, '');
      expect(p.vision, '');
      expect(p.antiVision, '');
      expect(p.rules, isEmpty);
      expect(p.updatedAt, isNull);
    });

    test('a partial update keeps the other fields; updated_at is set', () async {
      final clock = Clock(DateTime.utc(2026, 10, 5, 3));
      final api = FakeApiClient(latency: Duration.zero, clock: clock.call);
      await api.updateProfile(vision: 'A clear mind', rules: ['No phone in bed']);
      final p = await api.updateProfile(antiVision: 'Drifting');
      expect(p.vision, 'A clear mind');
      expect(p.antiVision, 'Drifting');
      expect(p.rules, ['No phone in bed']);
      expect(p.updatedAt, DateTime.utc(2026, 10, 5, 3));
      expect((await api.getProfile()).antiVision, 'Drifting');
    });

    test('an empty string clears a field; blank rules are dropped', () async {
      final api = FakeApiClient(latency: Duration.zero);
      await api.updateProfile(vision: 'x', rules: ['a', '  ', 'b']);
      expect((await api.getProfile()).rules, ['a', 'b']);
      final p = await api.updateProfile(vision: '', rules: []);
      expect(p.vision, '');
      expect(p.rules, isEmpty);
    });

    test('limits: 280 characters, 5 rules, 120 characters per rule — else 422', () async {
      final api = FakeApiClient(latency: Duration.zero);
      await api.updateProfile(identity: 'i' * 280, vision: 'v' * 280, antiVision: 'a' * 280);
      await api.updateProfile(rules: List.generate(5, (i) => 'r' * 120));
      for (final call in <Future<Profile> Function()>[
        () => api.updateProfile(identity: 'i' * 281),
        () => api.updateProfile(vision: 'v' * 281),
        () => api.updateProfile(antiVision: 'a' * 281),
        () => api.updateProfile(rules: List.generate(6, (i) => 'r$i')),
        () => api.updateProfile(rules: ['r' * 121]),
      ]) {
        expect((await failure(call)).statusCode, 422);
      }
      // Nothing was changed by the failed calls.
      final p = await api.getProfile();
      expect(p.identity, hasLength(280));
      expect(p.rules, hasLength(5));
    });

    test('failure injection reaches the new methods', () async {
      final api = FakeApiClient(latency: Duration.zero);
      api.failNext(method: 'updateProfile', statusCode: 500);
      expect((await failure(() => api.updateProfile(vision: 'x'))).statusCode, 500);
      expect((await api.getProfile()).vision, '');
      api.failNext(method: 'getProfile');
      expect((await failure(api.getProfile)).statusCode, 502);
    });
  });

  group('16 getCurrentPlan', () {
    test('null before any plan, then the latest one', () async {
      final api = FakeApiClient(latency: Duration.zero);
      expect(await api.getCurrentPlan(), isNull);
      await api.generateCourse(const GenerateRequest(topic: 'math'));
      await api.sendChat('What should I do today?');
      final plan = await api.getCurrentPlan();
      expect(plan, isNotNull);
      expect(plan!.steps, isNotEmpty);
    });
  });

  group('suggestions: the reflection prompt', () {
    late Clock clock;
    late FakeApiClient api;

    setUp(() {
      clock = Clock(DateTime.utc(2026, 10, 5, 3));
      api = FakeApiClient(latency: Duration.zero, clock: clock.call);
    });

    test('no check-in today: the check-in chip, not a reflection', () async {
      final s = await api.getChatSuggestions();
      expect(s.first.label, 'How was your day?');
      expect(s.any((x) => x.reflection), isFalse);
    });

    test('checked in: item 1 is the prompt of the current window, flagged', () async {
      await api.checkInVoice('I slept seven hours.');
      clock.setKst(12, 0);
      final s = await api.getChatSuggestions();
      expect(s.first.label, 'What are you putting off right now?');
      expect(s.first.reflection, isTrue);
      expect(s.first.message, '');
      expect(s.first.skillId, isNull);
      expect(s, hasLength(2));
      expect(s[1].reflection, isFalse);
    });

    test('each of the seven windows offers its own prompt', () async {
      await api.checkInVoice('I slept seven hours.');
      final seen = <String>[];
      for (final (h, m) in [(4, 0), (12, 0), (14, 0), (16, 0), (18, 0), (20, 0), (22, 0)]) {
        clock.setKst(h, m);
        // The check-in is dated by the KST day, so stay on the same day.
        seen.add((await api.getChatSuggestions()).first.label);
      }
      expect(seen, reflectionPrompts);
    });

    test('a prompt answered today is not offered again; the next window has its own', () async {
      await api.checkInVoice('I slept seven hours.');
      clock.setKst(12, 0);
      await api.sendChat('The taxes', reflectionPrompt: 'What are you putting off right now?');
      var s = await api.getChatSuggestions();
      expect(s.any((x) => x.reflection), isFalse); // item 1 is omitted
      expect(s.map((x) => x.label), ['Tell me what you want to learn']);

      clock.setKst(14, 0);
      s = await api.getChatSuggestions();
      expect(s.first.label, 'Looking at the last two hours, what were you really after?');
    });

    test('the same window the next day offers the prompt again', () async {
      clock.setKst(12, 0);
      await api.checkInVoice('I slept seven hours.');
      await api.sendChat('The taxes', reflectionPrompt: 'What are you putting off right now?');
      clock.setKst(12, 0, day: 6);
      await api.checkInVoice('I slept eight hours.');
      expect((await api.getChatSuggestions()).first.label, 'What are you putting off right now?');
    });
  });

  group('18 chat with a reflection_prompt', () {
    const prompt = 'What are you putting off right now?';
    late FakeApiClient api;

    setUp(() {
      api = FakeApiClient(latency: Duration.zero);
    });

    test('three messages: her prompt, the answer, the acknowledgement — no LLM', () async {
      final r = await api.sendChat('The taxes', reflectionPrompt: prompt);
      expect(r, hasLength(3));
      expect(r[0].role, ChatRole.assistant);
      expect(r[0].agent, 'front_desk');
      expect(r[0].content, prompt);
      expect(r[1].role, ChatRole.user);
      expect(r[1].content, 'The taxes');
      expect(r[2].role, ChatRole.assistant);
      expect(r[2].agent, 'front_desk');
      expect(r[2].content, "Noted. It's in your journal.");
      expect(r.every((m) => m.action == null), isTrue);
      expect(r.map((m) => m.id).toList(), [1, 2, 3]);
      // Persisted in that order; no course was made.
      expect((await api.getChatHistory()).map((m) => m.content), r.map((m) => m.content));
      expect(await api.listCourses(), isEmpty);
    });

    test('it is not run through the front desk (keywords do nothing)', () async {
      final r = await api.sendChat('I want to learn math', reflectionPrompt: prompt);
      expect(r, hasLength(3));
      expect(await api.listCourses(), isEmpty);
    });

    test('the answer lands in the journal, newest first', () async {
      final clock = Clock(DateTime.utc(2026, 10, 5, 3));
      final timed = FakeApiClient(latency: Duration.zero, clock: clock.call);
      await timed.sendChat('The taxes', reflectionPrompt: prompt);
      await timed.sendChat('Calling mom', reflectionPrompt: reflectionPrompts.first);
      final journal = await timed.listJournal();
      expect(journal.map((e) => e.answer), ['Calling mom', 'The taxes']);
      expect(journal.last.prompt, prompt);
      expect(journal.last.createdAt, DateTime.utc(2026, 10, 5, 3));
      expect((await timed.listJournal(limit: 1)).single.answer, 'Calling mom');
    });

    test('a prompt that is not one of the seven is a 422 and nothing is saved', () async {
      expect(
        (await failure(() => api.sendChat('x', reflectionPrompt: 'Make something up'))).statusCode,
        422,
      );
      expect(await api.getChatHistory(), isEmpty);
      expect(await api.listJournal(), isEmpty);
    });

    test('a blank answer is a 422', () async {
      expect((await failure(() => api.sendChat('  ', reflectionPrompt: prompt))).statusCode, 422);
    });

    test('an injected failure saves nothing', () async {
      api.failNext(method: 'sendChat');
      await failure(() => api.sendChat('The taxes', reflectionPrompt: prompt));
      expect(await api.getChatHistory(), isEmpty);
      expect(await api.listJournal(), isEmpty);
    });

    test('limit of listJournal is 1-100', () async {
      expect((await failure(() => api.listJournal(limit: 0))).statusCode, 422);
      expect((await failure(() => api.listJournal(limit: 101))).statusCode, 422);
    });
  });
}
