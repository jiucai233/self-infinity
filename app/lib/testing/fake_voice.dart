import 'dart:async';

import '../voice/voice_service.dart';

/// A [VoiceService] for tests: no plugins, fully scripted.
///
/// ```dart
/// final voice = FakeVoiceService();
/// ...                              // the UI calls listen()
/// voice.hear('hello there');          // partial + final result, then onEnd
/// expect(voice.spoken, ['nice to meet you']);
/// ```
class FakeVoiceService implements VoiceService {
  FakeVoiceService({this.available = true});

  /// What [init] answers.
  bool available;

  /// When true, [speak] stays pending until [finishSpeaking] (or
  /// [stopSpeaking]) is called.
  bool holdSpeech = false;

  /// Everything passed to [speak], in order.
  final List<String> spoken = [];

  int listenCalls = 0;
  int initCalls = 0;

  VoiceResultCallback? _onResult;
  void Function()? _onEnd;
  void Function(double level)? _onLevel;
  Completer<void>? _speech;

  @override
  Future<bool> init() async {
    initCalls++;
    return available;
  }

  @override
  bool get isListening => _onEnd != null;

  @override
  Future<void> listen({
    required VoiceResultCallback onResult,
    required void Function() onEnd,
    void Function(double level)? onLevel,
    Duration pauseFor = kVoicePause,
  }) async {
    listenCalls++;
    _onResult = onResult;
    _onEnd = onEnd;
    _onLevel = onLevel;
  }

  /// Delivers a partial result (no end of session).
  void partial(String text) => _onResult?.call(text, isFinal: false);

  /// Delivers the loudness.
  void level(double value) => _onLevel?.call(value);

  /// The user says [text] and then falls silent: a final result, then the end
  /// of the session.
  void hear(String text) {
    _onResult?.call(text, isFinal: true);
    end();
  }

  /// The session ends (silence, timeout, error) without a new result.
  void end() {
    final end = _onEnd;
    _onEnd = null;
    end?.call();
  }

  int cancelCalls = 0;

  @override
  Future<void> stopListening() async => end();

  @override
  Future<void> cancelListening() async {
    cancelCalls++;
    end();
  }

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    if (!holdSpeech) return Future.value();
    _speech = Completer<void>();
    return _speech!.future;
  }

  /// Completes a held [speak].
  void finishSpeaking() {
    final speech = _speech;
    _speech = null;
    if (speech != null && !speech.isCompleted) speech.complete();
  }

  @override
  Future<void> stopSpeaking() async => finishSpeaking();
}
