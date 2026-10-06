import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/api.dart';
import '../api/fake_api.dart';
import '../api/http_api.dart';
import '../auth/auth_service.dart';
import '../features/auth/sign_in_scene.dart';
import '../features/onboarding/onboarding_scene.dart';
import '../features/stage/profile_controller.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../upload/file_picker_service.dart';
import '../voice/platform_voice_service.dart';
import '../voice/voice_service.dart';
import '../widgets/widgets.dart';
import 'app_state.dart';
import 'providers.dart';
import 'router.dart';

// Run it:
//   flutter run -d chrome --dart-define=USE_FAKE_API=true                       (no backend)
//   flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000/api  (real backend)
//   ... --dart-define=SUPABASE_URL=https://xyz.supabase.co --dart-define=SUPABASE_ANON_KEY=...
//                                                                        (accounts, see docs/deploy.md)

/// `--dart-define=API_BASE_URL=...` (default `http://127.0.0.1:8000/api`; the
/// deployed app uses `/api`, same origin).
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: HttpApi.defaultBaseUrl,
);

/// `--dart-define=USE_FAKE_API=true` runs against the in-memory
/// [FakeApiClient] instead of the backend (default `false`).
const bool kUseFakeApi = bool.fromEnvironment('USE_FAKE_API');

/// Supabase project URL and anon (publishable) key. Both set = accounts on;
/// both empty = no accounts (local mode).
const String kSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String kSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

bool get kAccountsEnabled => kSupabaseUrl.isNotEmpty && kSupabaseAnonKey.isNotEmpty && !kUseFakeApi;

/// The API implementation selected by the `--dart-define` flags above; with
/// accounts, every call carries the token of [auth].
SelfInfinityApi createApiFromEnvironment({AuthService? auth}) => kUseFakeApi
    ? FakeApiClient(onboarded: false)
    : HttpApi(
        baseUrl: kApiBaseUrl,
        language: () => LocaleController.current.code,
        token: auth == null ? null : () => auth.accessToken,
        onUnauthorized: auth == null ? null : () => auth.signOut(),
      );

/// The root widget.
///
/// * Accounts on and nobody signed in: the sign-in page only.
/// * Signed in (or no accounts): the providers and controllers of that
///   account — rebuilt from scratch when the account changes, so nothing of
///   the previous one stays on screen — then the first-run tutorial until it
///   is done, then the scenes.
class SelfInfinityApp extends StatefulWidget {
  const SelfInfinityApp({
    super.key,
    required this.api,
    required this.appState,
    this.auth,
    this.voice,
    this.filePicker,
    this.initialLocation,
    this.locale,
  });

  final SelfInfinityApi api;

  final AppState appState;

  /// Who is signed in; [LocalAuth] (no accounts) when null.
  final AuthService? auth;

  /// Speech in and out; defaults to the platform implementation
  /// (`speech_to_text` + `flutter_tts`).
  final VoiceService? voice;

  /// The file dialog of the ⊕ upload; defaults to the `file_picker` plugin.
  final FilePickerService? filePicker;

  /// Overrides the start page (see [createRouter]).
  final String? initialLocation;

  /// The app's language; English (not remembered) when null.
  final LocaleController? locale;

  @override
  State<SelfInfinityApp> createState() => _SelfInfinityAppState();
}

/// What every `MaterialApp` of the app shares: title, theme and language.
class _AppLook {
  const _AppLook(this.language);

  final AppLanguage language;

  ThemeData get theme => AppTheme.light(language);
  Locale get locale => language.locale;
  static const delegates = AppLocalizations.localizationsDelegates;
  static const locales = AppLocalizations.supportedLocales;
}

class _SelfInfinityAppState extends State<SelfInfinityApp> {
  late final LocaleController _locale = widget.locale ?? LocaleController();
  late final AuthService _auth = widget.auth ?? LocalAuth();
  late final VoiceService _voice = widget.voice ?? PlatformVoiceService();
  late final FilePickerService _filePicker = widget.filePicker ?? PlatformFilePickerService();

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LocaleController>.value(
      value: _locale,
      child: ListenableBuilder(
        listenable: Listenable.merge([_auth, _locale]),
        builder: (context, _) {
          final look = _AppLook(_locale.language);
          // Local mode can sign out too, to show the front page (LocalAuth).
          if (!_auth.signedIn) {
            return ChangeNotifierProvider<AuthService>.value(
              value: _auth,
              child: MaterialApp(
                title: 'Self-Infinity',
                debugShowCheckedModeBanner: false,
                theme: look.theme,
                locale: look.locale,
                localizationsDelegates: _AppLook.delegates,
                supportedLocales: _AppLook.locales,
                home: const SignInScene(),
              ),
            );
          }
          return KeyedSubtree(
            key: ValueKey('account:${_auth.userId}'),
            child: AppProviders(
              api: widget.api,
              appState: widget.appState,
              voice: _voice,
              filePicker: _filePicker,
              auth: _auth,
              child: _AccountShell(look: look, initialLocation: widget.initialLocation),
            ),
          );
        },
      ),
    );
  }
}

/// One account's app: a splash while its profile loads, the tutorial until it
/// is done, then the router with the scenes.
class _AccountShell extends StatefulWidget {
  const _AccountShell({required this.look, this.initialLocation});

  final _AppLook look;
  final String? initialLocation;

  @override
  State<_AccountShell> createState() => _AccountShellState();
}

class _AccountShellState extends State<_AccountShell> {
  GoRouter? _router;

  GoRouter get _scenes => _router ??= createRouter(initialLocation: widget.initialLocation);

  @override
  void dispose() {
    _router?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileController>();
    final look = widget.look;
    if (!profile.loaded) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: look.theme,
        locale: look.locale,
        localizationsDelegates: _AppLook.delegates,
        supportedLocales: _AppLook.locales,
        home: const Scaffold(key: Key('account-loading'), body: LoadingView()),
      );
    }
    if (!profile.profile.onboarded) {
      return MaterialApp(
        title: 'Self-Infinity',
        debugShowCheckedModeBanner: false,
        theme: look.theme,
        locale: look.locale,
        localizationsDelegates: _AppLook.delegates,
        supportedLocales: _AppLook.locales,
        home: const OnboardingScene(),
      );
    }
    return MaterialApp.router(
      title: 'Self-Infinity',
      debugShowCheckedModeBanner: false,
      theme: look.theme,
      locale: look.locale,
      localizationsDelegates: _AppLook.delegates,
      supportedLocales: _AppLook.locales,
      routerConfig: _scenes,
    );
  }
}
