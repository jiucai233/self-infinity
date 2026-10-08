// The life overview (contract #39): numbers, chart, patterns, advice, days.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/features/life/life_scene.dart';

import '../support/scene_helpers.dart';

/// Noon on 8 Oct 2026 in Seoul.
final DateTime now = DateTime.utc(2026, 10, 8, 3);

FakeApiClient newApi() => FakeApiClient(latency: Duration.zero, clock: () => now);

String day(int daysAgo) {
  final d = DateTime.utc(2026, 10, 8).subtract(Duration(days: daysAgo));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

Finder key(String k) => find.byKey(Key(k));

void main() {
  testWidgets('empty: no data yet, how patterns appear, advice to ask for, today to fill in', (
    tester,
  ) async {
    await pumpScene(tester, const LifeScene(), api: newApi());
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text('Nothing logged in these days yet.'), findsOneWidget);
    expect(find.textContaining('Once you have 5 days on each side'), findsOneWidget);
    expect(find.text('Get advice'), findsOneWidget);
    expect(key('life-day-${day(0)}'), findsOneWidget);
    expect(key('life-privacy'), findsOneWidget);
  });

  testWidgets('the numbers and the chart follow the days logged', (tester) async {
    final api = newApi();
    await api.editCheckIn(day(0), {'sleep_hours': 7, 'focus': 4, 'stress': 2, 'weight_kg': 71.5});
    await api.editCheckIn(day(2), {'sleep_hours': 5, 'exercise_minutes': 30, 'weight_kg': 72.0});
    await pumpScene(tester, const LifeScene(), api: api);

    expect(textsIn(tester, key('life-sleep')).join(), 'Sleep6 h');
    expect(textsIn(tester, key('life-exercise')).join(), 'Exercise1 days');
    expect(textsIn(tester, key('life-weight')).join(), 'Weight71.5 kg (−0.5)');
    expect(key('life-chart'), findsOneWidget);
    expect(textsIn(tester, key('life-day-${day(2)}')).join(), contains('30 min'));
  });

  testWidgets('a pattern shows once each side has five days', (tester) async {
    final api = newApi();
    for (var i = 0; i < 5; i++) {
      await api.editCheckIn(day(i), {'sleep_hours': 8, 'focus': 4});
      await api.editCheckIn(day(10 + i), {'sleep_hours': 5, 'focus': 2});
    }
    await pumpScene(tester, const LifeScene(), api: api);

    final pattern = textsIn(tester, key('life-pattern-sleep')).toList();
    expect(pattern, [
      'Slept 7 h+',
      '5 days · no audits · focus 4',
      'Under 6 h',
      '5 days · no audits · focus 2',
    ]);
    expect(find.textContaining('not a cause'), findsOneWidget);
  });

  testWidgets('Get advice shows three pieces with what each rests on', (tester) async {
    final api = newApi();
    await api.editCheckIn(day(0), {'sleep_hours': 6, 'focus': 3});
    await pumpScene(tester, const LifeScene(), api: api);

    await tester.tap(key('life-advice-get'));
    await tester.pumpAndSettle();

    expect(key('life-advice-item'), findsNWidgets(3));
    expect(find.text('Based on: slept 6.0 h on average'), findsOneWidget);
    expect(find.text('New advice'), findsOneWidget);
  });

  testWidgets('advice that fails says so', (tester) async {
    final api = newApi();
    await pumpScene(tester, const LifeScene(), api: api);
    api.failNext(method: 'requestLifeAdvice');

    await tester.tap(key('life-advice-get'));
    await tester.pumpAndSettle();

    expect(key('life-advice-failed'), findsOneWidget);
    expect(find.text('Get advice'), findsOneWidget);
  });

  testWidgets('tapping a day edits it', (tester) async {
    final api = newApi();
    await pumpScene(tester, const LifeScene(), api: api);

    await tester.tap(key('life-day-${day(0)}'));
    await tester.pumpAndSettle();
    await tester.enterText(key('edit-weight'), '71.5');
    await tester.enterText(key('edit-minutes'), '40');
    await tester.tap(key('edit-save'));
    await tester.pumpAndSettle();

    expect(key('life-edit-dialog'), findsNothing);
    expect(textsIn(tester, key('life-day-${day(0)}')).join(), contains('40 min · 71.5 kg'));
    final saved = (await api.getLife()).days.last;
    expect((saved.weightKg, saved.exerciseMinutes, saved.exercised), (71.5, 40, true));
  });

  testWidgets('the window can be 7 days', (tester) async {
    await pumpScene(tester, const LifeScene(), api: newApi());
    await tester.tap(key('life-window-7'));
    await tester.pumpAndSettle();
    expect(find.text('Last 7 days'), findsOneWidget);
  });
}
