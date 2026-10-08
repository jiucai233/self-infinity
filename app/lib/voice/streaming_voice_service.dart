import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/api.dart';
import '../api/api_exception.dart';
import 'live_io.dart';
import 'pause_detector.dart';
import 'usage_meter.dart';
import 'voice_service.dart';

/// [VoiceService] for a spoken audit (contract #35): live transcription over
/// one WebRTC session (the words appear while the learner speaks; a pause
/// commits the turn), and replies read aloud as the server streams them.
///
/// The session opens on the first [listen] and stays open between turns, the
/// microphone muted while it is not listening; [cancelListening] (leaving
/// voice mode) closes it. Without live voice here (a phone, no OpenAI key, the
/// offline fake) or when the session cannot be opened, [device] does it all.
class StreamingVoiceService implements VoiceService {
  StreamingVoiceService({required this.api, required this.device, LiveIo? io})
    : io = io ?? createLiveIo();

  final SelfInfinityApi api;
  final VoiceService device;
  final LiveIo io;

  static const String transcribePath = '/voice/realtime/transcribe';
  static const String speechPath = '/voice/speech/stream';

  /// How long the final words may take after a turn is committed.
  static const Duration finalTimeout = Duration(seconds: 6);

  /// The longest text the server reads aloud.
  static const int maxSpeechChars = 4096;

  bool? _live; // null: not asked yet (or the server could not be reached)
  LiveLink? _link;
  StreamSubscription<Map<String, Object?>>? _events;
  bool _listening = false;
  int _session = 0;
  int _utterance = 0;
  VoiceResultCallback? _onResult;
  void Function()? _onEnd;
  void Function(double level)? _onLevel;
  PauseDetector? _pause;
  Timer? _waitForFinal;
  String _partial = '';
  bool _committed = false;

  /// What the open session costs (contract #37).
  UsageMeter? _meter;
  String? _turnItem;

  /// Whether this goes through the live session (decided by the first [init]).
  bool get usesLive => _live == true;

  @override
  Future<bool> init() async {
    if (io.supported) io.unlock(); // still inside the tap
    if (_live == true) return true;
    if (_live == null && io.supported && api.liveEndpoint(transcribePath) != null) {
      try {
        _live = await api.voiceAvailable();
      } on ApiException catch (e) {
        debugPrint('StreamingVoiceService: live voice unknown ($e)');
      }
      if (_live == true) return true;
    }
    return device.init();
  }

  @override
  bool get isListening => usesLive ? _listening : device.isListening;

  Future<LiveLink> _open() async {
    final open = _link;
    if (open != null) return open;
    final link = await io.connect(
      api.liveEndpoint(transcribePath)!,
      playReplies: false,
      onLevel: (level) {
        _pause?.level(level);
        _onLevel?.call(level);
      },
    );
    link.microphoneOn = false;
    _link = link;
    _meter = UsageMeter(api: api, kind: 'transcribe')..usage.model = 'gpt-live-transcribe';
    _events = link.events.listen(_onEvent, onDone: () {
      if (identical(_link, link)) _link = null;
    });
    return link;
  }

  @override
  Future<void> listen({
    required VoiceResultCallback onResult,
    required void Function() onEnd,
    void Function(double level)? onLevel,
    Duration pauseFor = kVoicePause,
  }) async {
    if (!usesLive) {
      return device.listen(onResult: onResult, onEnd: onEnd, onLevel: onLevel, pauseFor: pauseFor);
    }
    if (_listening) _drop();
    final session = ++_session;
    _onResult = onResult;
    _onEnd = onEnd;
    _onLevel = onLevel;
    _partial = '';
    _committed = false;
    _turnItem = null;
    _listening = true;
    final LiveLink link;
    try {
      link = await _open();
    } on Object catch (e) {
      debugPrint('StreamingVoiceService: no live session, using the device ($e)');
      _live = false;
      _listening = false;
      _onResult = _onEnd = null;
      _onLevel = null;
      if (session != _session) return;
      await device.init();
      return device.listen(onResult: onResult, onEnd: onEnd, onLevel: onLevel, pauseFor: pauseFor);
    }
    if (session != _session) return;
    link.send({'type': 'input_audio_buffer.clear'});
    link.microphoneOn = true;
    _pause = PauseDetector(
      pauseFor: pauseFor,
      onEnd: ({required heard}) => _endTurn(session, heard: heard),
    )..start();
  }

  void _onEvent(Map<String, Object?> event) {
    if (!_listening) return;
    switch (event['type']) {
      case 'input_audio_buffer.committed':
        _turnItem ??= event['item_id'] as String?;
      case 'conversation.item.input_audio_transcription.delta':
        final item = event['item_id'] as String?;
        if (_turnItem != null && item != _turnItem) return;
        _partial += '${event['delta'] ?? ''}';
        final text = _partial.trim();
        if (text.isNotEmpty) _onResult?.call(text, isFinal: false);
      case 'conversation.item.input_audio_transcription.completed':
        final item = event['item_id'] as String?;
        if (!_committed || (_turnItem != null && item != _turnItem)) return;
        final meter = _meter;
        if (meter != null) {
          meter.usage
            ..turns += 1
            ..addTranscription(event['usage']);
          meter.report();
        }
        _deliver(_session, '${event['transcript'] ?? ''}');
      case 'error':
        debugPrint('StreamingVoiceService: ${event['error'] ?? event}');
        if (_committed) _deliver(_session, _partial);
    }
  }

  /// A pause (or [stopListening]): mute, and commit what was said.
  void _endTurn(int session, {required bool heard}) {
    if (session != _session || _committed) return;
    _pause?.stop();
    _pause = null;
    final link = _link;
    link?.microphoneOn = false;
    if (!heard || link == null) {
      link?.send({'type': 'input_audio_buffer.clear'});
      _end(session);
      return;
    }
    _committed = true;
    link.send({'type': 'input_audio_buffer.commit'});
    _waitForFinal = Timer(finalTimeout, () => _deliver(session, _partial));
  }

  void _deliver(int session, String text) {
    if (session != _session || !_listening) return;
    final words = text.trim();
    if (words.isNotEmpty) _onResult?.call(words, isFinal: true);
    _end(session);
  }

  void _end(int session) {
    if (session != _session) return;
    _waitForFinal?.cancel();
    _waitForFinal = null;
    _listening = false;
    final end = _onEnd;
    _onEnd = null;
    _onResult = null;
    _onLevel = null;
    end?.call();
  }

  /// Ends the running turn without a result (no onEnd).
  void _drop() {
    _session++;
    _pause?.stop();
    _pause = null;
    _waitForFinal?.cancel();
    _waitForFinal = null;
    _listening = false;
    _onResult = _onEnd = null;
    _onLevel = null;
    _link?.microphoneOn = false;
  }

  @override
  Future<void> stopListening() async {
    if (!usesLive) return device.stopListening();
    if (!_listening) return;
    _endTurn(_session, heard: (_pause?.heard ?? false) || _partial.trim().isNotEmpty);
  }

  @override
  Future<void> cancelListening() async {
    if (!usesLive) return device.cancelListening();
    final end = _listening ? _onEnd : null;
    _drop();
    _link?.send({'type': 'input_audio_buffer.clear'});
    await _close();
    end?.call();
  }

  Future<void> _close() async {
    _meter?.close();
    _meter = null;
    final link = _link;
    _link = null;
    await _events?.cancel();
    _events = null;
    await link?.close();
  }

  @override
  Future<void> speak(String text) async {
    if (!usesLive) return device.speak(text);
    final line = text.trim();
    if (line.isEmpty) return;
    final utterance = ++_utterance;
    final clipped = line.length > maxSpeechChars ? line.substring(0, maxSpeechChars) : line;
    try {
      await io.playStream(api.liveEndpoint(speechPath)!, jsonEncode({'text': clipped}));
    } on Object catch (e) {
      debugPrint('StreamingVoiceService: streamed speech failed, using the device ($e)');
      if (utterance != _utterance) return;
      await device.init();
      if (utterance == _utterance) await device.speak(line);
    }
  }

  @override
  Future<void> stopSpeaking() async {
    _utterance++;
    await io.stopStream();
    await device.stopSpeaking();
  }
}
