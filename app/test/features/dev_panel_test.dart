// The developer panel (contract #34): behind ◎ for developers; metrics on
// top, every finished audit below with the buttons to review its verdict.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/features/map/map_scene.dart';
import 'package:self_infinity/testing/test_app.dart';

import '../support/scene_helpers.dart';

class _NotADeveloper extends FakeApiClient {
  _NotADeveloper() : super(latency: Duration.zero);

  @override
  Future<Me> getMe() async => const Me(id: 'someone', isDev: false);
}

String metric(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key('dev-metric-$key'))).data!;

void main() {
  Future<void> openPanel(WidgetTester tester, FakeApiClient api) async {
    await pumpScene(tester, const MapScene(), api: api);
    await tester.tap(find.byKey(const Key('settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-dev')));
    await tester.pumpAndSettle();
  }

  testWidgets('only a developer has it in the account menu', (tester) async {
    final api = _NotADeveloper();
    await api.generateCourse(const GenerateRequest(topic: 'math'));
    await pumpScene(tester, const MapScene(), api: api);
    await tester.tap(find.byKey(const Key('settings-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-tutorial')), findsOneWidget);
    expect(find.byKey(const Key('settings-dev')), findsNothing);
  });

  testWidgets('metrics on top; reviewing a verdict moves them', (tester) async {
    final api = await seededFakeApi();
    final failed = await failAudit(api, 6);
    final passed = await passAudit(api, 6);
    await openPanel(tester, api);

    expect(find.byKey(const Key('dev-panel')), findsOneWidget);
    expect(metric(tester, 'finished'), '2');
    expect(metric(tester, 'pass-rate'), '50%');
    expect(metric(tester, 'agreement'), '—');
    expect(find.text('Discriminant'), findsNWidgets(2));

    // A leak can only be marked on a review.
    final leak = find.byKey(Key('dev-leak-${failed.sessionId}'));
    expect(tester.widget<FilterChip>(leak).onSelected, isNull);

    await tester.tap(find.byKey(Key('dev-review-wrong-${failed.sessionId}'))); // Too strict
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dev-review-right-2')));
    await tester.pumpAndSettle();
    expect(metric(tester, 'reviewed'), '2');
    expect(metric(tester, 'agreement'), '50%');
    expect(metric(tester, 'too-strict'), '1');

    await tester.tap(find.byKey(const Key('dev-leak-2')));
    await tester.pumpAndSettle();
    expect(metric(tester, 'leaked'), '1');
    expect(passed.passed, isTrue);
  });

  testWidgets('the transcript opens under its card', (tester) async {
    final api = await seededFakeApi();
    final failed = await failAudit(api, 6);
    await openPanel(tester, api);
    expect(find.textContaining(shortAnswer), findsNothing);
    await tester.tap(find.byKey(Key('dev-transcript-${failed.sessionId}')));
    await tester.pumpAndSettle();
    expect(find.textContaining(shortAnswer), findsWidgets);
  });
}
