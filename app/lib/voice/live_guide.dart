import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/api.dart';
import '../api/api_exception.dart';
import '../api/models.dart';
import 'live_io.dart';
import 'realtime_guide.dart';
import 'usage_meter.dart';
import 'voice_mode.dart';

/// The home page's Guide on GPT-Live (contract #35, #36): a full-duplex
/// voice that listens while it speaks and hands tool use to a text backend
/// the server configures. The backend's function calls arrive on the data
/// channel inside `response.event`; they run here on `POST /chat/act` (as the
/// Realtime Guide's do), their results go back as `function_call_output`, and
/// `response.create` lets the backend finish. What is said is kept with
/// `POST /chat/log`, grouped into turns from the transcript fragments.
///
/// GPT-Live bills every second a session is open, so it closes after
/// [idleClose] without speech or work. Where it cannot run (the server
/// prefers Realtime, the session cannot be opened), [fallback] runs: the
/// Realtime Guide, which falls back to taking turns itself.
class LiveGuideMode extends VoiceMode {
  LiveGuideMode({
    required this.api,
    required this.io,
    required this.fallback,
    required this.onMessages,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    fallback.addListener(_relay);
  }

  final SelfInfinityApi api;
  final LiveIo io;
  final VoiceMode fallback;
  final void Function(List<ChatMessage> saved) onMessages;
  final DateTime Function() _clock;

  static const String guidePath = '/voice/live/guide';

  /// No speech, voice or work for this long closes the session.
  static const Duration idleClose = Duration(seconds: 60);

  /// How often the idle check runs.
  static const Duration idleCheck = Duration(seconds: 5);

  /// The reply's loudness above which she is speaking, and how long it stays
  /// below before she has stopped.
  static const double speakingLevel = 0.12;
  static const Duration quietAfterSpeech = Duration(milliseconds: 700);

  /// How long closing waits for the final usage.
  static const Duration closeWait = Duration(seconds: 3);

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
  DateTime _lastActivity = DateTime.now();
  DateTime? _lastLoud;
  Completer<void>? _closed;

  /// The user's words since the last turn was kept; [_userRead] once a tool
  /// call has taken them (the log then leaves them out).
  final StringBuffer _user = StringBuffer();
  bool _userRead = false;

  /// What she said since the user last spoke.
  final StringBuffer _assistant = StringBuffer();

  /// Tool calls running, per delegation.
  final Map<String, List<Future<void>>> _calls = {};
  int _toolsRunning = 0;

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
    final endpoint = api.liveEndpoint(guidePath);
    if (!io.supported || endpoint == null) return _startFallback();
    if (_voice == null) {
      try {
        _voice = await api.guideVoice();
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
      _meter = UsageMeter(api: api, kind: 'guide')..usage.model = 'gpt-live-1';
      _events = link.events.listen(_onEvent, onDone: () {
        if (connection == _connection && _link != null) unawaited(stop());
      });
      _touch();
      _idleTimer = Timer.periodic(idleCheck, (_) => checkIdle());
      _set(VoiceModeState.listening);
      return true;
    } on Object catch (e) {
      debugPrint('LiveGuideMode: no GPT-Live session, trying the Realtime Guide ($e)');
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

  /// Closes the session after [idleClose] without speech or work.
  @visibleForTesting
  void checkIdle() {
    if (_link == null || _toolsRunning > 0 || _state == VoiceModeState.speaking) return;
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
      _set(_toolsRunning > 0 ? VoiceModeState.thinking : VoiceModeState.listening);
    }
  }

  void _onEvent(Map<String, Object?> event) {
    switch (event['type']) {
      case 'session.started':
        final session = event['session'];
        if (session is Map && session['model'] is String) _meter?.usage.model = session['model'] as String;
      case 'session.input_transcript.delta':
        _touch();
        // The user speaks after her reply: that turn is over.
        if (_assistant.isNotEmpty) _keepTurn();
        if (_userRead) {
          _user.clear();
          _userRead = false;
        }
        _user.write('${event['delta'] ?? ''}');
        if (_state != VoiceModeState.speaking) _set(VoiceModeState.listening);
        if (!_disposed) notifyListeners();
      case 'session.output_transcript.delta':
        _touch();
        _assistant.write('${event['delta'] ?? ''}');
      case 'session.usage.updated' || 'session.closed':
        final usage = event['usage'];
        if (usage is Map && usage['seconds'] is num) {
          _meter?.billedSeconds = (usage['seconds'] as num).toDouble();
        }
        if (event['type'] == 'session.closed' && !(_closed?.isCompleted ?? true)) _closed!.complete();
      case 'session.delegation.created':
        _touch();
        if (_state != VoiceModeState.speaking) _set(VoiceModeState.thinking);
      case 'response.event':
        final inner = event['event'];
        if (inner is Map) _onBackend('${event['delegation_id'] ?? ''}', inner);
      case 'error':
        debugPrint('LiveGuideMode: ${event['error'] ?? event}');
    }
  }

  /// One of the backend's Responses events, by its delegation.
  void _onBackend(String delegation, Map<dynamic, dynamic> event) {
    switch (event['type']) {
      case 'response.output_item.done':
        final item = event['item'];
        if (item is Map && item['type'] == 'function_call') {
          (_calls[delegation] ??= []).add(_runTool(item));
        }
      case 'response.completed' || 'response.failed' || 'response.incomplete':
        final response = event['response'];
        final meter = _meter;
        if (meter != null) {
          meter.usage.addBackend(response is Map ? response['usage'] : null);
          meter.report();
        }
        final calls = _calls.remove(delegation);
        if (calls != null && event['type'] == 'response.completed') {
          // Every result is in before the backend goes on.
          unawaited(Future.wait(calls).then((_) => _link?.send({'type': 'response.create'})));
        }
    }
  }

  Future<void> _runTool(Map<dynamic, dynamic> call) async {
    final name = '${call['name']}';
    final callId = call['call_id'];
    Map<String, Object?> args;
    try {
      final decoded = jsonDecode('${call['arguments'] ?? '{}'}');
      args = decoded is Map<String, Object?> ? decoded : {};
    } on FormatException {
      args = {};
    }
    _toolsRunning++;
    _touch();
    if (_state != VoiceModeState.speaking) _set(VoiceModeState.thinking);
    String output;
    try {
      final intent = RealtimeGuideMode.intents[name];
      if (intent == null) {
        output = jsonEncode({'error': 'unknown tool $name'});
      } else {
        // The user's own words since the last turn go with the backend's summary.
        final words = _userRead ? '' : _user.toString().trim();
        _userRead = true;
        final apiArgs = switch (name) {
          'log_checkin' => {'said': args['said']},
          'build_course' => {'topic': args['topic']},
          'open_node' => {'skill': args['node']},
          _ => <String, Object?>{},
        };
        try {
          final saved = await api.chatAct(intent, args: apiArgs, said: words);
          if (!_disposed) onMessages(saved);
          final results = [for (final m in saved) if (!m.isUser) m.content];
          output = jsonEncode({
            'done': results.join(' '),
            'navigating': saved.any((m) => m.action is NavigateAction),
          });
        } on ApiException catch (e) {
          output = jsonEncode({'error': e.userMessage});
        }
      }
    } finally {
      _toolsRunning--;
      _touch();
    }
    _link?.send({
      'type': 'response.item.create',
      'item': {'type': 'function_call_output', 'call_id': callId, 'output': output},
    });
  }

  /// Keeps the turn so far in the history: the user's words no tool took,
  /// and what she said.
  void _keepTurn() {
    final said = _userRead ? '' : _user.toString().trim();
    final spoken = _assistant.toString().trim();
    _user.clear();
    _userRead = false;
    _assistant.clear();
    if (said.isEmpty && spoken.isEmpty) return;
    unawaited(_log([if (said.isNotEmpty) said], spoken));
  }

  Future<void> _log(List<String> said, String spoken) async {
    try {
      final saved = await api.chatLog([
        for (final s in said) (role: ChatRole.user, content: s),
        if (spoken.isNotEmpty) (role: ChatRole.assistant, content: spoken),
      ]);
      if (!_disposed && saved.isNotEmpty) onMessages(saved);
    } on ApiException catch (e) {
      debugPrint('LiveGuideMode: could not keep the exchange ($e)');
    }
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
    _idleTimer?.cancel();
    _idleTimer = null;
    _keepTurn();
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
    _calls.clear();
    _level = 0;
    _set(VoiceModeState.off);
    await link?.close();
  }

  @override
  Future<void> interrupt() async {
    if (_usingFallback) return fallback.interrupt();
    if (_state != VoiceModeState.speaking) return;
    _link?.send({
      'type': 'session.instructions.append',
      'delegation_id': null,
      'content': 'Stop speaking now and listen to the player.',
    });
  }

  @override
  void dispose() {
    _disposed = true;
    fallback.removeListener(_relay);
    _connection++;
    _idleTimer?.cancel();
    _meter?.close();
    _meter = null;
    unawaited(_events?.cancel());
    unawaited(_link?.close());
    _link = null;
    fallback.dispose();
    super.dispose();
  }
}
