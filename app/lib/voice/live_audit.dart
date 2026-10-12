import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api.dart';
import '../api/api_exception.dart';
import 'live_io.dart';
import 'usage_meter.dart';
import 'voice_mode.dart';

/// An audit's voice on GPT-Live (contract #35): a full-duplex voice that
/// listens while it speaks, so she can be interrupted by speaking. It only
/// carries the talk. When it hears that an answer is finished it hands over
/// (`session.delegation.created`, client delegation): the words said since
/// the last answer go to [onHeard] (the audit, where the Auditor judges them
/// as typed text) and what comes back is given to the voice to say
/// (`session.commentary.append`).
///
/// GPT-Live bills every second a session is open, so it closes after
/// [idleClose] without speech or work. Where it cannot run (the server
/// prefers turns, the session cannot be opened), [fallback] runs: live
/// transcription, a pause ends the turn, the reply is read aloud.
class LiveAuditMode extends VoiceMode {
  LiveAuditMode({
    required this.api,
    required this.io,
    required this.fallback,
    required this.onHeard,
    required this.opening,
    this.settle = const Duration(milliseconds: 700),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    fallback.addListener(_relay);
  }

  final SelfInfinityApi api;
  final LiveIo io;
  final VoiceMode fallback;

  /// Handles one answer and returns what she says back.
  final Future<VoiceReply> Function(String heard) onHeard;

  /// Her line on the table when the session opens (the question); null when
  /// there is nothing to say.
  final String? Function() opening;

  /// The words of an answer may still be arriving when it is handed over:
  /// this long without a new one, and it is whole.
  final Duration settle;
  final DateTime Function() _clock;

  static const String auditPath = '/voice/live/audit';

  /// No speech, voice or work for this long closes the session.
  static const Duration idleClose = Duration(seconds: 90);

  /// How often the idle check runs.
  static const Duration idleCheck = Duration(seconds: 5);

  /// The reply's loudness above which she is speaking, and how long it stays
  /// below before she has stopped.
  static const double speakingLevel = 0.12;
  static const Duration quietAfterSpeech = Duration(milliseconds: 700);

  /// The longest wait for an answer's last words, and between two looks.
  static const Duration maxSettle = Duration(seconds: 4);
  static const Duration settleTick = Duration(milliseconds: 100);

  /// If `session.started` was missed, her first line goes out after this.
  static const Duration openingWait = Duration(milliseconds: 1500);

  /// After the last line of an audit, the longest wait for her to say it.
  static const Duration lastLineWait = Duration(seconds: 30);

  /// How long closing waits for the final usage.
  static const Duration closeWait = Duration(seconds: 3);

  /// One append takes 500 tokens; a line longer than this estimate is split.
  static const int maxAppendTokens = 400;

  bool _usingFallback = false;
  String? _voice;
  LiveLink? _link;
  StreamSubscription<Map<String, Object?>>? _events;
  VoiceModeState _state = VoiceModeState.off;
  double _level = 0;
  bool _disposed = false;
  int _connection = 0;
  UsageMeter? _meter;
  Timer? _idleTimer;
  Timer? _openingTimer;
  Timer? _lastLineTimer;
  bool _openingSent = false;
  DateTime _lastActivity = DateTime.now();
  DateTime _lastWords = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastLoud;
  Completer<void>? _closed;

  /// The learner's words since the last answer was handed over.
  final StringBuffer _user = StringBuffer();

  /// An answer is with the Auditor; [_queued] is a hand-over that came meanwhile.
  bool _working = false;
  String? _queued;

  /// Her last line is being said: the session closes when she is done.
  /// [_lastLineLeft] is how much of it must be heard first (she may have been
  /// saying "one moment" when it arrived).
  bool _lastLine = false;
  int _lastLineLeft = 0;

  /// Whether GPT-Live is talking (not the fallback).
  bool get isLive => _link != null;

  @override
  VoiceModeState get state => _usingFallback ? fallback.state : _state;

  @override
  double get level => _usingFallback ? fallback.level : _level;

  @override
  String get heard => _usingFallback ? fallback.heard : _user.toString().trim();

  void _relay() {
    if (_usingFallback && !_disposed) notifyListeners();
  }

  void _set(VoiceModeState s) {
    if (_state == s) return;
    _state = s;
    if (!_disposed) notifyListeners();
  }

  void _touch() => _lastActivity = _clock();

  @override
  Future<bool> start() async {
    if (active) return true;
    if (io.supported) io.unlock(); // still inside the tap
    final endpoint = api.liveEndpoint(auditPath);
    if (!io.supported || endpoint == null) return _startFallback();
    if (_voice == null) {
      try {
        _voice = await api.auditVoice();
      } on ApiException {
        _voice = null;
      }
    }
    if (_voice != 'live') return _startFallback();
    final connection = ++_connection;
    _set(VoiceModeState.thinking); // connecting
    try {
      final link = await io.connect(
        endpoint,
        playReplies: true,
        onLevel: (level) {
          if (connection != _connection) return;
          _level = level;
          if (_state == VoiceModeState.listening && !_disposed) notifyListeners();
        },
        onReplyLevel: (level) {
          if (connection == _connection) _onReplyLevel(level);
        },
      );
      if (connection != _connection || _disposed) {
        await link.close();
        return false;
      }
      _link = link;
      _user.clear();
      _working = false;
      _queued = null;
      _lastLine = false;
      _openingSent = false;
      _lastWords = DateTime.fromMillisecondsSinceEpoch(0);
      _meter = UsageMeter(api: api, kind: 'audit')..usage.model = 'gpt-live-1';
      _events = link.events.listen(_onEvent, onDone: () {
        if (connection == _connection && _link != null) unawaited(stop());
      });
      _touch();
      _idleTimer = Timer.periodic(idleCheck, (_) => checkIdle());
      _openingTimer = Timer(openingWait, _sayOpening);
      _set(VoiceModeState.listening);
      return true;
    } on Object catch (e) {
      debugPrint('LiveAuditMode: no GPT-Live session, taking turns instead ($e)');
      if (connection != _connection) return false;
      _set(VoiceModeState.off);
      return _startFallback();
    }
  }

  Future<bool> _startFallback() async {
    _usingFallback = true;
    final ok = await fallback.start();
    if (!ok) _usingFallback = false;
    if (!_disposed) notifyListeners();
    return ok;
  }

  /// The session is ready: she says the line on the table.
  void _sayOpening() {
    _openingTimer?.cancel();
    _openingTimer = null;
    if (_openingSent || _link == null) return;
    _openingSent = true;
    final line = opening()?.trim() ?? '';
    if (line.isEmpty) return;
    _instruct('Say this to the learner now, then listen for their answer: "$line"');
  }

  void _instruct(String content, {String? delegation}) =>
      _link?.send({'type': 'session.instructions.append', 'delegation_id': delegation, 'content': content});

  /// Closes the session after [idleClose] without speech or work.
  @visibleForTesting
  void checkIdle() {
    if (_link == null || _working || _state == VoiceModeState.speaking) return;
    if (_clock().difference(_lastActivity) >= idleClose) unawaited(stop());
  }

  void _onReplyLevel(double level) {
    final now = _clock();
    if (level >= speakingLevel) {
      _lastLoud = now;
      _touch();
      _set(VoiceModeState.speaking);
    } else if (_state == VoiceModeState.speaking &&
        (_lastLoud == null || now.difference(_lastLoud!) >= quietAfterSpeech)) {
      if (_lastLine && _lastLineLeft <= 0) {
        unawaited(stop());
        return;
      }
      _set(_working ? VoiceModeState.thinking : VoiceModeState.listening);
    }
  }

  void _onEvent(Map<String, Object?> event) {
    switch (event['type']) {
      case 'session.started':
        final session = event['session'];
        if (session is Map && session['model'] is String) _meter?.usage.model = session['model'] as String;
        _sayOpening();
      case 'session.input_transcript.delta':
        _touch();
        _lastWords = _clock();
        _user.write('${event['delta'] ?? ''}');
        if (_state != VoiceModeState.speaking && !_working) _set(VoiceModeState.listening);
        if (!_disposed) notifyListeners();
      case 'session.output_transcript.delta':
        _touch();
        if (_lastLine) _lastLineLeft -= '${event['delta'] ?? ''}'.length;
      case 'session.usage.updated' || 'session.closed':
        final usage = event['usage'];
        if (usage is Map && usage['seconds'] is num) {
          _meter?.billedSeconds = (usage['seconds'] as num).toDouble();
        }
        if (event['type'] == 'session.closed' && !(_closed?.isCompleted ?? true)) _closed!.complete();
      case 'session.delegation.created':
        final delegation = event['delegation'];
        final id = delegation is Map ? delegation['id'] : null;
        if (id is String) unawaited(_answer(id));
      case 'error':
        debugPrint('LiveAuditMode: ${event['error'] ?? event}');
    }
  }

  /// Waits until the answer's last words are in: [settle] without a new one.
  Future<void> _settled(int connection) async {
    var waited = Duration.zero;
    while (connection == _connection && _clock().difference(_lastWords) < settle && waited < maxSettle) {
      await Future<void>.delayed(settleTick);
      waited += settleTick;
    }
  }

  /// The voice handed an answer over: the Auditor judges it, she says the reply.
  Future<void> _answer(String delegation) async {
    if (_lastLine) return;
    if (_working) {
      _queued = delegation;
      return;
    }
    final connection = _connection;
    _working = true;
    _touch();
    if (_state != VoiceModeState.speaking) _set(VoiceModeState.thinking);
    try {
      await _settled(connection);
      if (connection != _connection) return;
      final words = _user.toString().trim();
      _user.clear();
      if (words.isEmpty) {
        _instruct(
          'The learner has not answered yet. Wait for their answer; say the question again only if they ask.',
          delegation: delegation,
        );
        return;
      }
      final meter = _meter;
      if (meter != null) {
        meter.usage.turns++;
        meter.report();
      }
      VoiceReply reply;
      try {
        reply = await onHeard(words);
      } on Object {
        reply = (speak: null, keepGoing: true);
      }
      if (connection != _connection) return;
      _touch();
      final line = reply.speak?.trim() ?? '';
      if (line.isEmpty) {
        _instruct(
          'The answer could not be judged just now. Tell the learner so in one sentence and ask them to look at the screen.',
          delegation: delegation,
        );
      } else {
        for (final part in partsOf(line)) {
          _link?.send({'type': 'session.commentary.append', 'delegation_id': delegation, 'content': part});
        }
      }
      if (!reply.keepGoing) {
        // The audit is over: she says her last line, then the session closes.
        _lastLine = true;
        _lastLineLeft = line.length ~/ 3;
        _lastLineTimer = Timer(lastLineWait, () => unawaited(stop()));
      }
    } finally {
      if (connection == _connection) {
        _working = false;
        if (_state == VoiceModeState.thinking) _set(VoiceModeState.listening);
        final queued = _queued;
        _queued = null;
        if (queued != null && !_lastLine && _user.toString().trim().isNotEmpty) unawaited(_answer(queued));
      }
    }
  }

  /// [line] in pieces one append takes: whole when it fits, else cut at the
  /// ends of sentences.
  @visibleForTesting
  static List<String> partsOf(String line) {
    if (_tokens(line) <= maxAppendTokens) return [line];
    final parts = <String>[];
    final part = StringBuffer();
    for (final sentence in line.splitMapJoin(
      RegExp(r'[.!?。！？]+\s*'),
      onMatch: (m) => '${m[0]}\u0000',
      onNonMatch: (s) => s,
    ).split('\u0000')) {
      if (sentence.isEmpty) continue;
      if (part.isNotEmpty && _tokens('$part$sentence') > maxAppendTokens) {
        parts.add(part.toString().trim());
        part.clear();
      }
      part.write(sentence);
    }
    if (part.toString().trim().isNotEmpty) parts.add(part.toString().trim());
    return parts;
  }

  /// A rough count: a CJK character is a token or more, other text about four
  /// characters a token.
  static int _tokens(String text) {
    var wide = 0;
    for (final rune in text.runes) {
      if (rune >= 0x2E80) wide++;
    }
    return (wide * 1.5 + (text.length - wide) / 3.5).ceil();
  }

  @override
  Future<void> stop() async {
    if (_usingFallback) {
      _usingFallback = false;
      await fallback.stop();
      if (!_disposed) notifyListeners();
      return;
    }
    _connection++;
    _cancelTimers();
    final link = _link;
    _link = null;
    if (link != null) {
      // Graceful close: the final billed seconds arrive with session.closed.
      final closed = _closed = Completer<void>();
      link.send({'type': 'session.close'});
      await closed.future.timeout(closeWait, onTimeout: () {});
    }
    _meter?.close();
    _meter = null;
    await _events?.cancel();
    _events = null;
    _user.clear();
    _working = false;
    _queued = null;
    _lastLine = false;
    _level = 0;
    _set(VoiceModeState.off);
    await link?.close();
  }

  void _cancelTimers() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _openingTimer?.cancel();
    _openingTimer = null;
    _lastLineTimer?.cancel();
    _lastLineTimer = null;
  }

  @override
  Future<void> interrupt() async {
    if (_usingFallback) return fallback.interrupt();
    if (_state != VoiceModeState.speaking) return;
    _instruct('Stop speaking now and listen to the learner.');
  }

  @override
  void dispose() {
    _disposed = true;
    fallback.removeListener(_relay);
    _connection++;
    _cancelTimers();
    _meter?.close();
    _meter = null;
    unawaited(_events?.cancel());
    unawaited(_link?.close());
    _link = null;
    fallback.dispose();
    super.dispose();
  }
}
