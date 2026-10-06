/// Speech in and out behind one interface, so that screens and tests never
/// touch the `speech_to_text` / `flutter_tts` plugins directly.
library;

import '../l10n/app_language.dart';

/// The recognition and synthesis locale: the app's language (`en_US`,
/// `zh_CN`, `ko_KR`), read at the start of every listen and utterance.
String get kVoiceLocale => LocaleController.current.speechLocale;

/// How long a silence ends an utterance in voice mode (`docs/ux-chat.md` 3).
const Duration kVoicePause = Duration(milliseconds: 1500);

/// Called with the words heard so far; [isFinal] is true for the last result.
typedef VoiceResultCallback = void Function(String text, {required bool isFinal});

/// Speech recognition (dictation) and text to speech.
///
/// Implementations never throw: a platform without speech support answers
/// `false` from [init] and the UI shows a short snackbar.
abstract class VoiceService {
  /// Prepares recognition and synthesis (asks for the microphone permission
  /// the first time). Returns false when speech is not available here.
  Future<bool> init();

  /// Whether the microphone is open right now.
  bool get isListening;

  /// Starts listening in [kVoiceLocale].
  ///
  /// * [onResult] gets partial and final transcripts.
  /// * [onLevel] gets the input loudness, 0–1 (for the waveform).
  /// * [onEnd] is called once when the session is over: after [pauseFor] of
  ///   silence, on a timeout or error, or after [stopListening].
  Future<void> listen({
    required VoiceResultCallback onResult,
    required void Function() onEnd,
    void Function(double level)? onLevel,
    Duration pauseFor = kVoicePause,
  });

  /// Stops listening; [onEnd] of the running session is called.
  Future<void> stopListening();

  /// Speaks [text] and completes when it is finished (or was stopped).
  Future<void> speak(String text);

  /// Cuts the current speech short; the pending [speak] completes.
  Future<void> stopSpeaking();
}
