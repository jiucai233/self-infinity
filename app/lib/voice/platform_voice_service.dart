import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'voice_service.dart';

/// [VoiceService] over `speech_to_text` and `flutter_tts`.
///
/// The plugins are created on the first [init], so building the app (or a
/// test) never touches a platform channel. Every platform error is swallowed:
/// [init] answers false, [speak] simply returns.
class PlatformVoiceService implements VoiceService {
  SpeechToText? _stt;
  FlutterTts? _tts;
  bool? _ready;
  void Function()? _onEnd;

  @override
  Future<bool> init() async {
    final known = _ready;
    if (known != null) return known;
    var ok = false;
    try {
      final stt = SpeechToText();
      ok = await stt.initialize(
        onStatus: (status) {
          if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
            _finishListening();
          }
        },
        onError: (_) => _finishListening(),
      );
      if (ok) {
        _stt = stt;
        try {
          final tts = FlutterTts();
          await tts.setLanguage(kVoiceLocale.replaceAll('_', '-'));
          await tts.awaitSpeakCompletion(true);
          _tts = tts;
        } on Object catch (e) {
          debugPrint('PlatformVoiceService: text to speech unavailable ($e)');
        }
      }
    } on Object catch (e) {
      debugPrint('PlatformVoiceService: speech unavailable ($e)');
      ok = false;
    }
    _ready = ok;
    return ok;
  }

  @override
  bool get isListening => _stt?.isListening ?? false;

  void _finishListening() {
    final end = _onEnd;
    _onEnd = null;
    end?.call();
  }

  @override
  Future<void> listen({
    required VoiceResultCallback onResult,
    required void Function() onEnd,
    void Function(double level)? onLevel,
    Duration pauseFor = kVoicePause,
  }) async {
    final stt = _stt;
    if (stt == null) {
      onEnd();
      return;
    }
    _onEnd = onEnd;
    try {
      await stt.listen(
        onResult: (r) => onResult(r.recognizedWords, isFinal: r.finalResult),
        onSoundLevelChange: onLevel == null
            ? null
            : (level) => onLevel(((level + 2) / 12).clamp(0.0, 1.0)),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          listenFor: const Duration(seconds: 60),
          pauseFor: pauseFor,
          localeId: kVoiceLocale,
        ),
      );
    } on Object catch (e) {
      debugPrint('PlatformVoiceService: could not listen ($e)');
      _finishListening();
    }
  }

  @override
  Future<void> stopListening() async {
    try {
      await _stt?.stop();
    } on Object catch (e) {
      debugPrint('PlatformVoiceService: could not stop listening ($e)');
    }
    _finishListening();
  }

  @override
  Future<void> speak(String text) async {
    final tts = _tts;
    if (tts == null || text.trim().isEmpty) return;
    try {
      await tts.setLanguage(kVoiceLocale.replaceAll('_', '-'));
      await tts.speak(text);
    } on Object catch (e) {
      debugPrint('PlatformVoiceService: could not speak ($e)');
    }
  }

  @override
  Future<void> stopSpeaking() async {
    try {
      await _tts?.stop();
    } on Object catch (e) {
      debugPrint('PlatformVoiceService: could not stop speaking ($e)');
    }
  }
}
