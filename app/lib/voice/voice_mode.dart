import 'package:flutter/foundation.dart';

import 'voice_service.dart';

/// What the voice loop is doing.
enum VoiceModeState { off, listening, thinking, speaking }

/// The answer to an utterance: [speak] is read aloud (null = nothing), and the
/// loop goes on listening only if [keepGoing].
typedef VoiceReply = ({String? speak, bool keepGoing});

/// The voice mode loop of `docs/ux-chat.md` (3, scene 5): listen → on silence
/// hand the words to [onHeard] → speak its answer → listen again, until
/// [stop] is called.
class VoiceModeController extends ChangeNotifier {
  VoiceModeController({required this.voice, required this.onHeard, this.onUnavailable});

  final VoiceService voice;

  /// Handles one utterance (sends it somewhere) and returns what to say back.
  final Future<VoiceReply> Function(String heard) onHeard;

  /// Called when speech is not available on this platform.
  final VoidCallback? onUnavailable;

  /// Silent rounds in a row after which the loop gives up.
  static const int maxSilentRounds = 3;

  VoiceModeState _state = VoiceModeState.off;
  double _level = 0;
  String _heard = '';
  int _generation = 0;
  int _silentRounds = 0;
  bool _disposed = false;

  VoiceModeState get state => _state;

  /// Whether voice mode is on.
  bool get active => _state != VoiceModeState.off;

  /// Input loudness 0–1 while listening.
  double get level => _level;

  /// The words heard in the current round.
  String get heard => _heard;

  /// Turns voice mode on. Returns false (after [onUnavailable]) when this
  /// platform has no speech support.
  Future<bool> start() async {
    if (active) return true;
    final ok = await voice.init();
    if (_disposed) return false;
    if (!ok) {
      onUnavailable?.call();
      return false;
    }
    _generation++;
    _silentRounds = 0;
    _listen(_generation);
    return true;
  }

  /// Turns voice mode off and silences the microphone and the speaker.
  Future<void> stop() async {
    _generation++;
    _setState(VoiceModeState.off);
    _level = 0;
    await voice.cancelListening();
    await voice.stopSpeaking();
  }

  /// Cuts her speech short; the loop goes on with listening.
  Future<void> interrupt() async {
    if (_state == VoiceModeState.speaking) await voice.stopSpeaking();
  }

  void _setState(VoiceModeState s) {
    _state = s;
    if (!_disposed) notifyListeners();
  }

  void _listen(int generation) {
    _heard = '';
    _level = 0;
    _setState(VoiceModeState.listening);
    voice.listen(
      onResult: (text, {required isFinal}) {
        if (generation != _generation) return;
        _heard = text;
        if (!_disposed) notifyListeners();
      },
      onLevel: (level) {
        if (generation != _generation) return;
        _level = level;
        if (!_disposed) notifyListeners();
      },
      onEnd: () => _afterListening(generation),
    );
  }

  Future<void> _afterListening(int generation) async {
    if (generation != _generation) return;
    final text = _heard.trim();
    if (text.isEmpty) {
      if (++_silentRounds >= maxSilentRounds) {
        await stop();
      } else {
        _listen(generation);
      }
      return;
    }
    _silentRounds = 0;
    _setState(VoiceModeState.thinking);
    VoiceReply reply;
    try {
      reply = await onHeard(text);
    } on Object {
      reply = (speak: null, keepGoing: true);
    }
    if (generation != _generation) return;
    final line = reply.speak;
    if (line != null && line.trim().isNotEmpty) {
      _setState(VoiceModeState.speaking);
      await voice.speak(line);
      if (generation != _generation) return;
    }
    if (!reply.keepGoing) {
      await stop();
      return;
    }
    _listen(generation);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    voice.cancelListening();
    voice.stopSpeaking();
    super.dispose();
  }
}
