// The day's plan (contract #15): the time of day decides between judgement
// and review, a review is done only when explained again, a stale plan is
// made again, and the daily quests say what each one is.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/app/app_state.dart';
import 'package:self_infinity/features/map/map_scene.dart';
import 'package:self_infinity/features/stage/stage_controller.dart';
import 'package:self_infinity/testing/test_app.dart';

import '../support/scene_helpers.dart';

/// A fake whose clock the test moves; [kst] is a KST wall-clock time.
class Clock {
  Clock(String kst) {
    set(kst);
  }

  late DateTime now;

  void set(String kst) => now = DateTime.parse('${kst}Z').subtract(const Duration(hours: 9));
}

Future<FakeApiClient> math(Clock clock) async {
  final api = FakeApiClient(latency: Duration.zero, clock: () => clock.now);
  await api.generateCourse(const GenerateRequest(topic: 'math'));
  return api;
}

Finder key(String k) => find.byKey(Key(k));

void main() {
  group('the fake API', () {
    test('a morning plan is judgement and may hold a challenge', () async {
      final clock = Clock('2026-10-05 09:00');
      final api = FakeApiClient(latency: Duration.zero, clock: () => clock.now);
      await api.generateCourse(const GenerateRequest(topic: 'Computer Vision'));

      final plan = await api.generatePlan();

      expect((plan.slot, plan.focusBudget, plan.focusLeft), (DaySlot.morning, 180, 180));
      expect(plan.steps.map((s) => s.kind), containsAll([QuestKind.learn, QuestKind.challenge]));
      expect(plan.summary, startsWith('Morning: judgement first'));
    });

    test('an evening plan reviews what is due, and has no challenge', () async {
      final clock = Clock('2026-10-02 10:00');
      final api = await math(clock);
      await passAudit(api, 6); // Discriminant, three days before
      clock.set('2026-10-05 20:00');

      final plan = await api.generatePlan();

      expect(plan.slot, DaySlot.evening);
      final review = plan.steps.firstWhere((s) => s.kind == QuestKind.review);
      expect((review.skillId, review.minutes), (6, 10));
      expect(review.rationale, 'You explained it 3 days ago: tell it again before it fades.');
      expect(plan.steps.where((s) => s.kind == QuestKind.challenge), isEmpty);
    });

    test('late at night one short review at most', () async {
      final clock = Clock('2026-10-02 10:00');
      final api = await math(clock);
      await passAudit(api, 6);
      clock.set('2026-10-05 23:30');

      final plan = await api.generatePlan();

      expect(plan.steps.map((s) => s.kind), [QuestKind.review]);
    });

    test('a plan from another time of day is stale', () async {
      final clock = Clock('2026-10-05 09:00');
      final api = await math(clock);
      await api.generatePlan();
      expect((await api.getCurrentPlan())!.stale, isFalse);
      clock.set('2026-10-05 19:00');
      expect((await api.getCurrentPlan())!.stale, isTrue);
    });
  });

  test('a stale plan is made again in the background', () async {
    final clock = Clock('2026-10-05 09:00');
    final api = await math(clock);
    final morning = await api.generatePlan();
    clock.set('2026-10-05 19:00');

    final stage = StageController(api: api, appState: AppState());
    addTearDown(stage.dispose);
    await stage.refresh();
    await pumpEventQueue();

    expect(stage.plan!.id, isNot(morning.id));
    expect(stage.plan!.slot, DaySlot.evening);
  });

  group('the daily quests', () {
    testWidgets('say what the day is for, and what each quest is', (tester) async {
      final clock = Clock('2026-10-05 09:00');
      final api = await math(clock);
      await api.generatePlan();
      await pumpScene(tester, const MapScene(), api: api, clock: () => clock.now);

      expect(textOf(tester, key('quests-summary')), startsWith('Morning: judgement first'));
      expect(textOf(tester, key('quest-kind-6')), 'Learn · 25 min');
    });

    testWidgets('a review is done only when explained again after the plan', (tester) async {
      final clock = Clock('2026-10-02 10:00');
      final api = await math(clock);
      await passAudit(api, 6);
      clock.set('2026-10-05 20:00');
      await api.generatePlan();
      await pumpScene(tester, const MapScene(), api: api, clock: () => clock.now);
      // Mastered three days ago, but not explained again yet.
      await tester.ensureVisible(key('quest-6'));
      expect(find.descendant(of: key('quest-6'), matching: key('quest-open')), findsOneWidget);
      expect(textOf(tester, key('quest-kind-6')), 'Review · 10 min');

      clock.set('2026-10-05 20:30');
      await passAudit(api, 6);
      tester.element(find.byType(MapScene)).read<AppState>().markDataChanged();
      await tester.pumpAndSettle();
      expect(find.descendant(of: key('quest-6'), matching: key('quest-done')), findsOneWidget);
    });
  });
}

String textOf(WidgetTester tester, Finder finder) => tester.widget<Text>(finder).data ?? '';
