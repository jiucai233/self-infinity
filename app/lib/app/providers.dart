import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../api/api.dart';
import '../auth/auth_service.dart';
import '../features/chat/chat_controller.dart';
import '../features/stage/profile_controller.dart';
import '../features/stage/stage_controller.dart';
import '../upload/file_picker_service.dart';
import '../voice/live_voice.dart';
import '../voice/voice_service.dart';
import 'app_state.dart';
import 'panel_layout.dart';

/// Everything the screens read with `context.read<...>()`: the API, the
/// [AppState], the [PanelLayout], the [VoiceService], the [FilePickerService] and the two stage-wide controllers
/// ([StageController], [ChatController]) and the [ProfileController].
///
/// Used by the app and by the widget test helper, so both build the same tree.
class AppProviders extends StatelessWidget {
  const AppProviders({
    super.key,
    required this.api,
    required this.appState,
    required this.voice,
    required this.filePicker,
    required this.child,
    this.layout,
    this.clock,
    this.auth,
    this.live,
  });

  /// The talking scenes' live voice (the realtime Guide, the audit's streamed
  /// turns); null (tests) means they take turns over [voice].
  final LiveVoice? live;

  /// Who is signed in; [LocalAuth] (no accounts) when null.
  final AuthService? auth;

  final SelfInfinityApi api;
  final AppState appState;
  final VoiceService voice;
  final FilePickerService filePicker;
  final Widget child;

  /// Which panels are folded; a fresh [PanelLayout] when null (tests pass one
  /// to keep it across a rebuild).
  final PanelLayout? layout;

  /// "Now" (UTC) for the parts that compare with today (the daily quests);
  /// the system clock when null.
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SelfInfinityApi>.value(value: api),
        if (auth != null)
          ChangeNotifierProvider<AuthService>.value(value: auth!)
        else
          ChangeNotifierProvider<AuthService>(create: (_) => LocalAuth()),
        ChangeNotifierProvider<AppState>.value(value: appState),
        Provider<VoiceService>.value(value: voice),
        Provider<LiveVoice?>.value(value: live),
        Provider<FilePickerService>.value(value: filePicker),
        if (layout != null)
          ChangeNotifierProvider<PanelLayout>.value(value: layout!)
        else
          ChangeNotifierProvider<PanelLayout>(create: (_) => PanelLayout()),
        ChangeNotifierProvider<StageController>(
          create: (_) => StageController(api: api, appState: appState, clock: clock),
        ),
        ChangeNotifierProvider<ProfileController>(create: (_) => ProfileController(api: api)),
        ChangeNotifierProvider<ChatController>(
          create: (_) => ChatController(api: api, appState: appState),
        ),
      ],
      child: child,
    );
  }
}
