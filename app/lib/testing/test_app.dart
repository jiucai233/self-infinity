/// Helpers for widget tests of feature screens.
///
/// ```dart
/// testWidgets('shows the map', (tester) async {
///   final api = await seededFakeApi();
///   await tester.pumpWidget(buildTestApp(child: const MapScene(), api: api));
///   await tester.pumpAndSettle();
///   ...
/// });
/// ```
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../api/fake_api.dart';
import '../api/models.dart';
import '../auth/auth_service.dart';
import '../l10n/l10n.dart';
import '../app/app_state.dart';
import '../app/panel_layout.dart';
import '../app/providers.dart';
import '../app/router.dart';
import '../theme/app_theme.dart';
import '../upload/file_picker_service.dart';
import '../voice/voice_service.dart';
import '../widgets/avatar.dart';
import 'fake_file_picker.dart';
import 'fake_voice.dart';
import 'package:provider/provider.dart';

/// Wraps [child] the way the real app does: the providers, the light theme and
/// a `GoRouter` — so that screens can call
/// `context.go` / `context.push` and `context.read<...>()`.
///
/// * [api] defaults to a zero-latency [FakeApiClient] (empty: no courses).
/// * [state] defaults to a fresh [AppState].
/// * [voice] defaults to a [FakeVoiceService] and [filePicker] to a
///   [FakeFilePicker]; no plugin is ever touched.
/// * [layout] keeps which panels are folded across several [buildTestApp]s.
/// * [clock] is “now” (UTC) for the daily quests; the system clock by default.
/// * [language] is the UI language (English by default).
/// * The avatar animations are switched off ([Avatar.animationsEnabled]).
/// * [child] is mounted at an internal route. Navigating anywhere else —
///   `/`, `/map`, `/skill/:id`, `/skill/:id/audit` — shows a placeholder whose
///   text is `route:<location>`, e.g. `find.text('route:/skill/5/audit')`
///   after tapping the → of scene 4. Use `route:` plus `AppRoutes.audit(5)` to
///   build the expected text.
Widget buildTestApp({
  required Widget child,
  SelfInfinityApi? api,
  AppState? state,
  VoiceService? voice,
  FilePickerService? filePicker,
  PanelLayout? layout,
  DateTime Function()? clock,
  AuthService? auth,
  AppLanguage language = AppLanguage.en,
}) {
  Avatar.animationsEnabled = false;
  LocaleController.current = language;
  final router = GoRouter(
    initialLocation: _testRoute,
    routes: [
      GoRoute(
        path: _testRoute,
        builder: (context, routerState) => Material(color: Colors.transparent, child: child),
      ),
      for (final path in const [
        AppRoutes.home,
        AppRoutes.map,
        '/skill/:skillId',
        '/skill/:skillId/audit',
      ])
        GoRoute(
          path: path,
          builder: (context, routerState) =>
              _RoutePlaceholder(location: routerState.uri.toString()),
        ),
    ],
  );
  final providers = AppProviders(
    api: api ?? FakeApiClient(latency: Duration.zero),
    appState: state ?? AppState(),
    voice: voice ?? FakeVoiceService(),
    filePicker: filePicker ?? FakeFilePicker(),
    layout: layout,
    clock: clock,
    auth: auth,
    // Follows the LocaleController, like the app's MaterialApps.
    child: Consumer<LocaleController>(
      builder: (context, locale, _) => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(locale.language),
        locale: locale.language.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  return ChangeNotifierProvider<LocaleController>(
    create: (_) => LocaleController(language),
    child: providers,
  );
}

/// A zero-latency [FakeApiClient] in which the “math” course (12 nodes, only the
/// root `available`) has already been generated.
Future<FakeApiClient> seededFakeApi() async {
  final api = FakeApiClient(latency: Duration.zero);
  await api.generateCourse(const GenerateRequest(topic: 'math'));
  return api;
}

/// An answer long enough (≥ 160 characters) to pass an audit without the
/// Challenger overturning it.
const String longAnswer =
    'Start with the definition: this idea is a way to find a value under given conditions. It works because the conditions pin the value down to exactly one answer. '
    'There are exceptions too. If the conditions contradict each other there may be no solution at all, and if they are too loose there can be many. '
    'So before using it, always state which range you are working in.';

/// A short answer that makes an audit fail.
const String shortAnswer = "I'm not sure";

/// Plays an audit on [skillId] with [longAnswer]s until it ends, and returns
/// the (passing) verdict. Marks the node `mastered` and unlocks its children.
Future<VerdictResult> passAudit(SelfInfinityApi api, int skillId) async {
  final start = await api.startAudit(skillId);
  for (var i = 0; i < 12; i++) {
    final result = await api.submitTurn(start.session.id, longAnswer);
    if (result is VerdictResult) return result;
  }
  throw StateError('The audit on node $skillId did not end');
}

/// Plays an audit on [skillId] with [shortAnswer]s until it fails and returns
/// the session id (needed for `submitReflection`) and the verdict.
Future<({int sessionId, VerdictResult verdict})> failAudit(
  SelfInfinityApi api,
  int skillId,
) async {
  final start = await api.startAudit(skillId);
  for (var i = 0; i < 12; i++) {
    final result = await api.submitTurn(start.session.id, shortAnswer);
    if (result is VerdictResult) return (sessionId: start.session.id, verdict: result);
  }
  throw StateError('The audit on node $skillId did not end');
}

const String _testRoute = '/__test__';

class _RoutePlaceholder extends StatelessWidget {
  const _RoutePlaceholder({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text('route:$location')));
}
