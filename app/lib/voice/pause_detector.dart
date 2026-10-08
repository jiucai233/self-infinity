import 'dart:async';
import 'dart:math' as math;

/// Ends an utterance from the microphone's loudness: after [pauseFor] of quiet
/// once speech was heard, after [waitForSpeech] without any, or after
/// [maxUtterance]. Feed it [level]s; [onEnd] is called once.
class PauseDetector {
  PauseDetector({required this.pauseFor, required this.onEnd});

  /// How often the loudness is checked against the pause.
  static const Duration tick = Duration(milliseconds: 100);

  /// The loudness (0–1) that counts as speech; a quiet room is far below it.
  static const double speechLevel = 0.35;

  /// No speech for this long ends the utterance with nothing heard.
  static const Duration waitForSpeech = Duration(seconds: 8);

  /// The longest utterance.
  static const Duration maxUtterance = Duration(seconds: 60);

  final Duration pauseFor;

  /// [heard]: whether any speech was heard.
  final void Function({required bool heard}) onEnd;

  Timer? _timer;
  bool _heard = false;
  int _ticks = 0;
  int _quietTicks = 0;
  double _loudest = 0;

  /// Whether speech was heard so far.
  bool get heard => _heard;

  bool get running => _timer != null;

  void start() {
    stop();
    _heard = false;
    _ticks = 0;
    _quietTicks = 0;
    _loudest = 0;
    _timer = Timer.periodic(tick, (_) => _onTick());
  }

  void level(double value) => _loudest = math.max(_loudest, value);

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _onTick() {
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
      stop();
      onEnd(heard: _heard);
    }
  }
}
