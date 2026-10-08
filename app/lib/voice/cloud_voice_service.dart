import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../api/api.dart';
import '../api/api_exception.dart';
import 'audio_io.dart';
import 'voice_service.dart';

/// [VoiceService] through the server (contract #35): the browser records an
/// utterance, the server's OpenAI speech model writes it down, and replies are
/// read aloud in the server's voice.
///
/// It falls back to [device] (the browser's or the phone's own speech) when
/// there is no [AudioIo] here (the phones) or the server has no voice
/// (no OpenAI key, the offline fake API). A reply the server fails to read
/// aloud is spoken by [device] instead.
///
/// There are no partial results: the words arrive once, after the utterance.
/// An utterance ends after `pauseFor` of quiet once speech was heard, after
/// [waitForSpeech] without any, after [maxUtterance], or on [stopListening].
class CloudVoiceService implements VoiceService {
  CloudVoiceService({required this.api, required this.device, AudioIo? io})
    : io = io ?? createAudioIo();

  final SelfInfinityApi api;
  final VoiceService device;
  final AudioIo io;

  /// How often the loudness is checked against the pause.
  static const Duration tick = Duration(milliseconds: 100);

  /// The loudness (0–1) that counts as speech; a quiet room is far below it.
  static const double speechLevel = 0.35;

  /// No speech for this long ends the utterance with nothing heard.
  static const Duration waitForSpeech = Duration(seconds: 8);

  /// The longest utterance (the server takes up to ~4 MB, ~1 minute).
  static const Duration maxUtterance = Duration(seconds: 60);

  /// The longest text the server reads aloud.
  static const int maxSpeechChars = 4096;

  bool? _cloud; // null: not asked yet (or the server could not be reached)
  bool _listening = false;
  int _session = 0;
  int _utterance = 0;
  Timer? _timer;
  VoiceResultCallback? _onResult;
  void Function()? _onEnd;
  bool _heard = false;
  int _ticks = 0;
  int _quietTicks = 0;
  double _loudest = 0;

  /// Whether speech goes through the server (decided by the first [init]).
  bool get usesServer => _cloud == true;

  @override
  Future<bool> init() async {
    if (io.supported) io.unlock(); // still inside the tap that called this
    if (_cloud == true) return true;
    if (_cloud == null && io.supported) {
      try {
        _cloud = await api.voiceAvailable();
      } on ApiException catch (e) {
        debugPrint('CloudVoiceService: server voice unknown ($e)');
      }
      if (_cloud == true) {
        if (await io.requestMicrophone()) return true;
        _cloud = null; // ask again next time; the device would be refused too
        return false;
      }
    }
    return device.init();
  }

  @override
  bool get isListening => usesServer ? _listening : device.isListening;

  @override
  Future<void> listen({
    required VoiceResultCallback onResult,
    required void Function() onEnd,
    void Function(double level)? onLevel,
    Duration pauseFor = kVoicePause,
  }) async {
    if (!usesServer) {
      return device.listen(onResult: onResult, onEnd: onEnd, onLevel: onLevel, pauseFor: pauseFor);
    }
    if (_listening) await cancelListening();
    final session = ++_session;
    _onResult = onResult;
    _onEnd = onEnd;
    _heard = false;
    _ticks = 0;
    _quietTicks = 0;
    _loudest = 0;
    _listening = true;
    try {
      await io.startRecording(
        onLevel: (level) {
          if (session != _session) return;
          _loudest = math.max(_loudest, level);
          onLevel?.call(level);
        },
      );
    } on Object catch (e) {
      debugPrint('CloudVoiceService: could not record ($e)');
      _end(session);
      return;
    }
    if (session != _session) {
      unawaited(io.stopRecording());
      return;
    }
    _timer = Timer.periodic(tick, (_) => _onTick(session, pauseFor));
  }

  void _onTick(int session, Duration pauseFor) {
    if (session != _session) return;
    _ticks++;
    if (_loudest >= speechLevel) {
      _heard = true;
      _quietTicks = 0;
    } else {
      _quietTicks++;
    }
    _loudest = 0;
    final elapsed = tick * _ticks;
    if ((_heard && tick * _quietTicks >= pauseFor) ||
        (!_heard && elapsed >= waitForSpeech) ||
        elapsed >= maxUtterance) {
      unawaited(_finish(session, transcribe: _heard));
    }
  }

  /// Stops recording and, if [transcribe], has the server write it down.
  Future<void> _finish(int session, {required bool transcribe}) async {
    _timer?.cancel();
    _timer = null;
    final recording = await io.stopRecording();
    if (session != _session) return;
    if (transcribe && recording != null && recording.bytes.isNotEmpty) {
      try {
        final text = (await api.transcribe(
          recording.bytes,
          filename: 'speech.${recording.extension}',
        )).trim();
        if (session == _session && text.isNotEmpty) _onResult?.call(text, isFinal: true);
      } on ApiException catch (e) {
        debugPrint('CloudVoiceService: could not transcribe ($e)');
      }
    }
    _end(session);
  }

  void _end(int session) {
    if (session != _session) return;
    _listening = false;
    final end = _onEnd;
    _onEnd = null;
    _onResult = null;
    end?.call();
  }

  /// Ends the utterance now; what was said is still written down.
  @override
  Future<void> stopListening() async {
    if (!usesServer) return device.stopListening();
    if (_timer == null) return; // not recording (or already writing it down)
    await _finish(_session, transcribe: true);
  }

  @override
  Future<void> cancelListening() async {
    if (!usesServer) return device.cancelListening();
    if (!_listening) return;
    _timer?.cancel();
    _timer = null;
    final end = _onEnd;
    _onEnd = null;
    _onResult = null;
    _session++;
    _listening = false;
    await io.stopRecording();
    end?.call();
  }

  @override
  Future<void> speak(String text) async {
    if (!usesServer) return device.speak(text);
    final line = text.trim();
    if (line.isEmpty) return;
    final utterance = ++_utterance;
    try {
      final audio = await api.speech(
        line.length > maxSpeechChars ? line.substring(0, maxSpeechChars) : line,
      );
      if (utterance != _utterance) return; // stopped while it was being made
      await io.play(audio);
    } on ApiException catch (e) {
      debugPrint('CloudVoiceService: server voice failed, using the device ($e)');
      if (utterance != _utterance) return;
      await device.init();
      if (utterance == _utterance) await device.speak(line);
    }
  }

  @override
  Future<void> stopSpeaking() async {
    _utterance++;
    await io.stopPlaying();
    await device.stopSpeaking();
  }
}
