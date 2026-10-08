import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/api.dart';
import '../api/api_exception.dart';
import '../api/models.dart';
import 'live_io.dart';
import 'usage_meter.dart';
import 'voice_mode.dart';

/// The home page's Guide as one speech-to-speech model (contract #35, #36):
/// a WebRTC session with OpenAI's Realtime API whose instructions and tools
/// the server sets. It hears the pause itself, answers in its own voice and
/// can be interrupted by speaking. What it does goes through its tools, run
/// here on `POST /chat/act`; what is said is kept with `POST /chat/log`. Both
/// hand the saved messages to [onMessages] (the chat, the navigation).
///
/// Without live voice here (a phone, no OpenAI key, the offline fake) or when
/// the session cannot be opened, [fallback] (turn-taking over the app's
/// voice) runs instead.
class RealtimeGuideMode extends VoiceMode {
  RealtimeGuideMode({
    required this.api,
    required this.io,
    required this.fallback,
    required this.onMessages,
  }) {
    fallback.addListener(_relay);
  }

  final SelfInfinityApi api;
  final LiveIo io;
  final VoiceMode fallback;
  final void Function(List<ChatMessage> saved) onMessages;

  static const String guidePath = '/voice/realtime/guide';

  /// How long a reply waits for the user's words to be written down.
  static const Duration transcriptWait = Duration(seconds: 2);

  /// The Guide's tools and the chat intents they run.
  static const Map<String, String> intents = {
    'log_checkin': 'checkin',
    'build_course': 'generate_course',
    'open_node': 'open_skill',
    'open_map': 'open_map',
    'todays_plan': 'plan',
    'briefing': 'briefing',
  };

  bool _usingFallback = false;
  bool? _live;
  LiveLink? _link;
  StreamSubscription<Map<String, Object?>>? _events;
  VoiceModeState _state = VoiceModeState.off;
  double _level = 0;
  String _heard = '';
  bool _disposed = false;
  int _connection = 0;

  /// The user's words per input item, as they are written down.
  final Map<String, Completer<String>> _said = {};

  /// Input items whose words a tool call already saved.
  final Set<String> _acted = {};
  String? _lastInput;
  int _toolsRunning = 0;

  /// What this session costs (contract #37).
  UsageMeter? _meter;

  /// Whether the realtime model is talking (not the fallback).
  bool get isRealtime => _link != null;

  @override
  VoiceModeState get state => _usingFallback ? fallback.state : _state;

  @override
  double get level => _usingFallback ? fallback.level : _level;

  @override
  String get heard => _usingFallback ? fallback.heard : _heard;

  void _relay() {
    if (_usingFallback && !_disposed) notifyListeners();
  }

  void _set(VoiceModeState s) {
    _state = s;
    if (!_disposed) notifyListeners();
  }

  @override
  Future<bool> start() async {
    if (active) return true;
    if (io.supported) io.unlock(); // still inside the tap
    final endpoint = api.liveEndpoint(guidePath);
    if (_live == null && io.supported && endpoint != null) {
      try {
        _live = await api.voiceAvailable();
      } on ApiException {
        _live = null;
      }
    }
    if (_live != true || endpoint == null) return _startFallback();
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
      );
      if (connection != _connection || _disposed) {
        await link.close();
        return false;
      }
      _link = link;
      _meter = UsageMeter(api: api, kind: 'guide');
      _events = link.events.listen(_onEvent, onDone: () {
        if (connection == _connection && _link != null) unawaited(stop());
      });
      _heard = '';
      _set(VoiceModeState.listening);
      return true;
    } on Object catch (e) {
      debugPrint('RealtimeGuideMode: no live session, taking turns instead ($e)');
      if (connection != _connection) return false;
      _set(VoiceModeState.off);
      return _startFallback();
    }
  }

  Future<bool> _startFallback() async {
    _usingFallback = true;
    final ok = await fallback.start();
    if (!ok) _usingFallback = false;
    return ok;
  }

  Completer<String> _saidFor(String item) => _said.putIfAbsent(item, Completer<String>.new);

  void _onEvent(Map<String, Object?> event) {
    switch (event['type']) {
      case 'session.created':
        final session = event['session'];
        if (session is Map && session['model'] is String) _meter?.usage.model = session['model'] as String;
      case 'input_audio_buffer.speech_started':
        _heard = '';
        _set(VoiceModeState.listening);
      case 'input_audio_buffer.speech_stopped':
        _set(VoiceModeState.thinking);
      case 'input_audio_buffer.committed':
        _lastInput = event['item_id'] as String?;
      case 'conversation.item.input_audio_transcription.delta':
        _heard += '${event['delta'] ?? ''}';
        if (!_disposed) notifyListeners();
      case 'conversation.item.input_audio_transcription.completed':
        final item = event['item_id'] as String?;
        final words = '${event['transcript'] ?? ''}'.trim();
        _meter?.usage.addTranscription(event['usage']);
        if (item != null && !_saidFor(item).isCompleted) _saidFor(item).complete(words);
        if (words.isNotEmpty) {
          _heard = words;
          if (!_disposed) notifyListeners();
        }
      case 'output_audio_buffer.started':
        _set(VoiceModeState.speaking);
      case 'output_audio_buffer.stopped' || 'output_audio_buffer.cleared':
        if (_state == VoiceModeState.speaking) {
          _set(_toolsRunning > 0 ? VoiceModeState.thinking : VoiceModeState.listening);
        }
      case 'response.done':
        unawaited(_onResponse(event['response']));
      case 'error':
        debugPrint('RealtimeGuideMode: ${event['error'] ?? event}');
    }
  }

  Future<String> _wordsOf(String? item) async {
    if (item == null) return '';
    try {
      return await _saidFor(item).future.timeout(transcriptWait);
    } on TimeoutException {
      return '';
    }
  }

  Future<void> _onResponse(Object? response) async {
    if (response is! Map) return;
    final meter = _meter;
    if (meter != null) {
      meter.usage.addResponse(response['usage']);
      meter.report();
    }
    final output = (response['output'] as List?) ?? const [];
    final input = _lastInput;
    final calls = [
      for (final item in output)
        if (item is Map && item['type'] == 'function_call') item,
    ];
    final spoken = [
      for (final item in output)
        if (item is Map && item['type'] == 'message')
          for (final part in (item['content'] as List?) ?? const [])
            if (part is Map && (part['transcript'] ?? part['text']) != null) '${part['transcript'] ?? part['text']}',
    ].join(' ').trim();

    if (calls.isNotEmpty) {
      _toolsRunning++;
      _set(VoiceModeState.thinking);
      try {
        for (final call in calls) {
          await _runTool(call, input);
        }
      } finally {
        _toolsRunning--;
      }
      _link?.send({'type': 'response.create'});
      // A line it said before calling the tool is kept too.
      if (spoken.isNotEmpty) await _log(const [], spoken);
      return;
    }
    if (spoken.isEmpty) return;
    final said = input == null || _acted.contains(input) ? '' : await _wordsOf(input);
    if (input != null) _acted.add(input);
    await _log([if (said.isNotEmpty) said], spoken);
  }

  Future<void> _runTool(Map<dynamic, dynamic> call, String? input) async {
    final name = '${call['name']}';
    final callId = call['call_id'];
    Map<String, Object?> args;
    try {
      final decoded = jsonDecode('${call['arguments'] ?? '{}'}');
      args = decoded is Map<String, Object?> ? decoded : {};
    } on FormatException {
      args = {};
    }
    final intent = intents[name];
    String output;
    if (intent == null) {
      output = jsonEncode({'error': 'unknown tool $name'});
    } else {
      final words = input == null || _acted.contains(input) ? '' : await _wordsOf(input);
      if (input != null) _acted.add(input);
      final apiArgs = switch (name) {
        'log_checkin' => {'said': args['said']},
        'build_course' => {'topic': args['topic']},
        'open_node' => {'skill': args['node']},
        _ => <String, Object?>{},
      };
      // The check-in reads the user's own words; the model's paraphrase is the fallback.
      final said = words.isNotEmpty ? words : (name == 'log_checkin' ? '${args['said'] ?? ''}' : '');
      try {
        final saved = await api.chatAct(intent, args: apiArgs, said: said);
        if (!_disposed) onMessages(saved);
        final results = [for (final m in saved) if (!m.isUser) m.content];
        output = jsonEncode({'done': results.join(' '), 'navigating': saved.any((m) => m.action is NavigateAction)});
      } on ApiException catch (e) {
        output = jsonEncode({'error': e.userMessage});
      }
    }
    _link?.send({
      'type': 'conversation.item.create',
      'item': {'type': 'function_call_output', 'call_id': callId, 'output': output},
    });
  }

  Future<void> _log(List<String> said, String spoken) async {
    try {
      final saved = await api.chatLog([
        for (final s in said) (role: ChatRole.user, content: s),
        (role: ChatRole.assistant, content: spoken),
      ]);
      if (!_disposed && saved.isNotEmpty) onMessages(saved);
    } on ApiException catch (e) {
      debugPrint('RealtimeGuideMode: could not keep the exchange ($e)');
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
    _meter?.close();
    _meter = null;
    final link = _link;
    _link = null;
    await _events?.cancel();
    _events = null;
    _level = 0;
    _heard = '';
    _set(VoiceModeState.off);
    await link?.close();
  }

  @override
  Future<void> interrupt() async {
    if (_usingFallback) return fallback.interrupt();
    if (_state != VoiceModeState.speaking) return;
    _link?.send({'type': 'output_audio_buffer.clear'});
    _link?.send({'type': 'response.cancel'});
  }

  @override
  void dispose() {
    _disposed = true;
    fallback.removeListener(_relay);
    _connection++;
    _meter?.close();
    _meter = null;
    unawaited(_events?.cancel());
    unawaited(_link?.close());
    _link = null;
    fallback.dispose();
    super.dispose();
  }
}
