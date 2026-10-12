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

/// A server with model calls logged and an audit that ran on GPT-Live.
class _WithCosts extends FakeApiClient {
  _WithCosts() : super(latency: Duration.zero);

  @override
  Future<DevLlm> getDevLlm() async => const DevLlm(
    calls: 12,
    failed: 1,
    cost: 0.0042,
    avgCost: 0.00038,
    unpricedCalls: 2,
    providers: [
      DevLlmRow(
        provider: 'openai',
        model: 'gpt-6-luna',
        calls: 6,
        failed: 1,
        avgInputTokens: 2000,
        avgOutputTokens: 300,
        avgMs: 2400,
        cost: 0.0024,
        avgCost: 0.0004,
      ),
      DevLlmRow(provider: 'claude', model: 'claude-haiku-5-5', calls: 4, cost: 0.0018, avgCost: 0.00045),
    ],
    agents: [
      DevLlmRow(provider: 'openai', model: 'gpt-6-luna', agent: 'auditor', calls: 5, avgCost: 0.0005),
    ],
    audits: [
      DevLlmRow(provider: 'openai', model: 'gpt-6-luna', audits: 2, avgCalls: 3, avgCost: 0.0015),
      DevLlmRow(provider: 'claude', model: 'claude-haiku-5-5', audits: 1, avgCalls: 4, avgCost: 0.0018),
    ],
  );

  @override
  Future<DevVoice> getDevVoice({int limit = 50}) async => DevVoice(
    guideSessions: 1,
    guideMinutes: 2,
    guideCost: 0.102,
    guideAllLive: 0.102,
    guideAllRealtime: 0.144,
    realtimePerMinute: 0.072,
    guideLiveVoiceCost: 0.1,
    guideLiveBackendCost: 0.002,
    guideCostPerSession: 0.102,
    auditSessions: 2,
    auditMinutes: 9,
    auditCost: 0.288,
    auditLiveSessions: 1,
    auditLiveMinutes: 4,
    auditLiveVoiceCost: 0.2,
    auditLiveBackendCost: 0.003,
    auditLiveCostPerSession: 0.203,
    auditTurnsCostPerSession: 0.085,
    sessions: [
      DevVoiceSession(
        id: 3,
        kind: 'audit',
        model: 'gpt-live-1',
        startedAt: DateTime.utc(2026, 10, 12, 3),
        minutes: 4,
        turns: 5,
        audioIn: 0,
        audioOut: 0,
        cost: 0.203,
        backendCost: 0.003,
      ),
      DevVoiceSession(
        id: 2,
        kind: 'transcribe',
        model: 'gpt-live-transcribe',
        startedAt: DateTime.utc(2026, 10, 11, 3),
        minutes: 5,
        turns: 6,
        audioIn: 0,
        audioOut: 0,
        cost: 0.085,
      ),
    ],
  );
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

  testWidgets('the voice tab: what live voice cost, next to the other voice', (tester) async {
    final api = await seededFakeApi();
    await api.reportVoiceUsage(
      VoiceUsage(id: 'a', kind: 'guide', model: 'gpt-realtime-2.1')
        ..seconds = 120
        ..turns = 6,
    );
    await api.reportVoiceUsage(VoiceUsage(id: 'b', kind: 'transcribe')..seconds = 300);
    await api.reportVoiceUsage(
      VoiceUsage(id: 'c', kind: 'guide', model: 'gpt-live-1')
        ..seconds = 60
        ..turns = 2,
    );
    await openPanel(tester, api);

    await tester.tap(find.byKey(const Key('dev-tab-voice')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dev-voice')), findsOneWidget);
    expect(metric(tester, 'guide-sessions'), '2');
    expect(metric(tester, 'guide-minutes'), '3.0');
    expect(metric(tester, 'guide-all-live'), '\$0.150');
    expect(metric(tester, 'realtime-rate'), '\$0.072');
    expect(metric(tester, 'audit-minutes'), '5.0');
    await tester.drag(find.byKey(const Key('dev-voice')), const Offset(0, -400)); // down to the sessions
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dev-voice-1')), findsOneWidget);
    expect(find.byKey(const Key('dev-voice-2')), findsOneWidget);
    // Each Guide session names its voice and prices the other one.
    expect(find.textContaining('Guide (Realtime)'), findsOneWidget);
    expect(find.textContaining('On GPT-Live \$0.100'), findsOneWidget);
    expect(find.textContaining('Guide (GPT-Live)'), findsOneWidget);
    expect(find.textContaining('On Realtime ≈ \$0.072'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dev-tab-audits')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dev-voice')), findsNothing);
    expect(find.byKey(const Key('dev-metric-finished')), findsOneWidget);
  });

  testWidgets('the voice tab: a GPT-Live session in its two parts, an audit on each voice', (tester) async {
    final api = _WithCosts();
    await api.generateCourse(const GenerateRequest(topic: 'math'));
    await openPanel(tester, api);
    await tester.tap(find.byKey(const Key('dev-tab-voice')));
    await tester.pumpAndSettle();

    expect(metric(tester, 'guide-per-session'), '\$0.102');
    expect(metric(tester, 'audit-live-per-session'), '\$0.203');
    expect(metric(tester, 'audit-turns-per-session'), '\$0.085');
    // The voice, and its other call beside it.
    expect(metric(tester, 'guide-live-voice'), '\$0.100');
    expect(metric(tester, 'guide-live-backend'), '\$0.0020');
    expect(metric(tester, 'audit-live-voice'), '\$0.200');
    expect(metric(tester, 'audit-live-backend'), '\$0.0030');
    await tester.drag(find.byKey(const Key('dev-voice')), const Offset(0, -400)); // down to the sessions
    await tester.pumpAndSettle();
    expect(find.textContaining('Audit (GPT-Live)'), findsOneWidget);
    expect(find.textContaining('(other call \$0.0030)'), findsOneWidget);
    expect(find.textContaining('Audit (turns)'), findsOneWidget);
  });

  testWidgets('the model cost tab: every call, per audit on each model, by model and by agent', (tester) async {
    final api = _WithCosts();
    await api.generateCourse(const GenerateRequest(topic: 'math'));
    await openPanel(tester, api);
    await tester.tap(find.byKey(const Key('dev-tab-llm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dev-llm')), findsOneWidget);
    expect(metric(tester, 'llm-calls'), '12');
    expect(metric(tester, 'llm-failed'), '1');
    expect(metric(tester, 'llm-cost'), '\$0.004');
    expect(metric(tester, 'llm-per-call'), '\$0.00038');
    expect(metric(tester, 'llm-unpriced'), '2');
    // One audit on OpenAI next to one on Claude.
    expect(find.textContaining('2 Audits · 3.0 Calls · \$0.0015'), findsOneWidget);
    expect(find.textContaining('1 Audits · 4.0 Calls · \$0.0018'), findsOneWidget);
    expect(find.text('claude · claude-haiku-5-5'), findsNWidgets(2));
    expect(find.textContaining('6 Calls (1 Failed) · 2000 → 300 tok · 2.4 s'), findsOneWidget);
    expect(find.text('auditor · gpt-6-luna'), findsOneWidget);
  });

  testWidgets('the model cost tab offline: nothing was called', (tester) async {
    final api = await seededFakeApi();
    await openPanel(tester, api);
    await tester.tap(find.byKey(const Key('dev-tab-llm')));
    await tester.pumpAndSettle();
    expect(metric(tester, 'llm-calls'), '0');
    expect(find.text('No model calls logged yet.'), findsOneWidget);
  });
}
