import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../api/api.dart';
import '../api/models.dart';

/// Keeps one live voice session's usage and reports it (contract #37): after
/// each turn, every [interval] while it is open (so an open, silent session
/// counts its minutes too), and once more on [close].
class UsageMeter {
  UsageMeter({required this.api, required String kind}) : usage = VoiceUsage(id: _newId(), kind: kind) {
    _clock.start();
    _timer = Timer.periodic(interval, (_) => report());
  }

  static const Duration interval = Duration(seconds: 30);

  final SelfInfinityApi api;
  final VoiceUsage usage;
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;

  static String _newId() {
    final random = math.Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// Sends the totals so far; a failure only costs this one report.
  void report() {
    usage.seconds = _clock.elapsedMilliseconds / 1000;
    unawaited(
      api.reportVoiceUsage(usage).catchError((Object e) {
        debugPrint('UsageMeter: could not report ($e)');
      }),
    );
  }

  /// The session is over: the last report.
  void close() {
    if (_timer == null) return;
    _timer?.cancel();
    _timer = null;
    _clock.stop();
    report();
  }
}
