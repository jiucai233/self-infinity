// Live voice: the audit's streamed turns over one transcription session, and
// the home page's realtime Guide with its tools; both fall back without it.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/api_exception.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/testing/fake_voice.dart';
import 'package:self_infinity/voice/live_guide.dart';
import 'package:self_infinity/voice/live_link.dart';
import 'package:self_infinity/voice/pause_detector.dart';
import 'package:self_infinity/voice/realtime_guide.dart';
import 'package:self_infinity/voice/streaming_voice_service.dart';
import 'package:self_infinity/voice/voice_mode.dart';

class _FakeLink implements LiveLink {
  final _events = StreamController<Map<String, Object?>>.broadcast(sync: true);
  final List<Map<String, Object?>> sent = [];
  bool mic = true;
  bool closed = false;

  void emit(Map<String, Object?> event) => _events.add(event);
  List<String> get sentTypes => [for (final e in sent) '${e['type']}'];

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  @override
  void send(Map<String, Object?> event) => sent.add(event);

  @override
  set microphoneOn(bool on) => mic = on;

  @override
  Future<void> close() async {
    closed = true;
    await _events.close();
  }
}

class _FakeLiveIo implements LiveIo {
  @override
  bool supported = true;
  int connects = 0;
  String? path;
  bool? playReplies;
  void Function(double level)? onLevel;
  void Function(double level)? onReplyLevel;
  /// A path whose sessions are refused (the others connect).
  String? refusePath;
  /// Made by [connect], inside the test's zone.
  late _FakeLink link;
  Object? connectError;
  final List<String> streamed = [];
  Object? streamError;

  void level(double v) => onLevel?.call(v);

  @override
  void unlock() {}

  @override
  Future<LiveLink> connect(
    LiveEndpoint endpoint, {
    required bool playReplies,
    void Function(double level)? onLevel,
    void Function(double level)? onReplyLevel,
  }) async {
    connects++;
    path = endpoint.url.path;
    this.playReplies = playReplies;
    this.onLevel = onLevel;
    this.onReplyLevel = onReplyLevel;
    if (connectError case final e?) throw e;
    if (refusePath != null && endpoint.url.path.endsWith(refusePath!)) throw StateError('refused');
    return link = _FakeLink();
  }

  @override
  Future<void> playStream(LiveEndpoint endpoint, String body) async {
    if (streamError case final e?) throw e;
    streamed.add((jsonDecode(body) as Map)['text'] as String);
  }

  @override
  Future<void> stopStream() async {}
}

class _LiveApi extends FakeApiClient {
  _LiveApi() : super(latency: Duration.zero);

  bool available = true;
  final List<(String, Map<String, Object?>, String)> acts = [];
  final List<List<({ChatRole role, String content})>> logs = [];
  final List<Map<String, Object?>> usage = [];

  @override
  Future<void> reportVoiceUsage(VoiceUsage u) async => usage.add(u.toJson());
  int _id = 1000;

  @override
  Future<bool> voiceAvailable() async => available;

  String guide = 'live';

  @override
  Future<String?> guideVoice() async => available ? guide : null;

  @override
  LiveEndpoint? liveEndpoint(String path) =>
      (url: Uri.parse('http://127.0.0.1:8000/api$path'), headers: const {'Authorization': 'Bearer t'});

  ChatMessage _message(ChatRole role, String content, [ChatAction? action]) => ChatMessage(
    id: _id++,
    role: role,
    content: content,
    action: action,
    createdAt: DateTime.utc(2026, 10, 8),
  );

  @override
  Future<List<ChatMessage>> chatAct(String intent, {Map<String, Object?> args = const {}, String said = ''}) async {
    acts.add((intent, args, said));
    return [
      if (said.isNotEmpty) _message(ChatRole.user, said),
      _message(ChatRole.assistant, 'Logged: sleep 7 h'),
    ];
  }

  @override
  Future<List<ChatMessage>> chatLog(List<({ChatRole role, String content})> lines) async {
    logs.add(lines);
    return [for (final l in lines) _message(l.role, l.content)];
  }
}

void main() {
  late _FakeLiveIo io;
  late _LiveApi api;
  late FakeVoiceService device;

  setUp(() {
    io = _FakeLiveIo();
    api = _LiveApi();
    device = FakeVoiceService();
  });

  group('the audit: streamed turns', () {
    late StreamingVoiceService voice;
    late List<(String, bool)> results;
    late int ends;

    setUp(() {
      voice = StreamingVoiceService(api: api, device: device, io: io);
      results = [];
      ends = 0;
    });

    Future<void> listen() => voice.listen(
      onResult: (text, {required isFinal}) => results.add((text, isFinal)),
      onEnd: () => ends++,
    );

    Future<void> sound(WidgetTester tester, double level, int ticks) async {
      for (var i = 0; i < ticks; i++) {
        io.level(level);
        await tester.pump(PauseDetector.tick);
      }
    }

    testWidgets('words appear while speaking; a pause commits; the final words end it', (
      tester,
    ) async {
      expect(await voice.init(), isTrue);
      await listen();
      final link = io.link;
      expect(io.path, '/api/voice/realtime/transcribe');
      expect(io.playReplies, isFalse);
      expect(link.sentTypes, ['input_audio_buffer.clear']);
      expect(link.mic, isTrue);

      await sound(tester, 0.8, 5);
      link.emit({'type': 'conversation.item.input_audio_transcription.delta', 'item_id': 'i1', 'delta': 'The roots'});
      link.emit({'type': 'conversation.item.input_audio_transcription.delta', 'item_id': 'i1', 'delta': ' are real'});
      expect(results, [('The roots', false), ('The roots are real', false)]);

      await sound(tester, 0, 15); // 1.5 s of quiet
      expect(link.mic, isFalse);
      expect(link.sentTypes.last, 'input_audio_buffer.commit');
      expect(ends, 0);
      link.emit({'type': 'input_audio_buffer.committed', 'item_id': 'i1'});
      link.emit({
        'type': 'conversation.item.input_audio_transcription.completed',
        'item_id': 'i1',
        'transcript': 'The roots are real.',
        'usage': {'type': 'duration', 'seconds': 3.5},
      });
      expect(results.last, ('The roots are real.', true));
      expect(api.usage.last['kind'], 'transcribe');
      expect(api.usage.last['turns'], 1);
      expect(api.usage.last['transcribed_seconds'], 3.5);
      expect(ends, 1);
      expect(link.closed, isFalse); // kept for the next turn

      await listen();
      expect(io.connects, 1);
      await tester.runAsync(voice.cancelListening);
    });

    testWidgets('silence: nothing is committed', (tester) async {
      await voice.init();
      await listen();
      await sound(tester, 0.1, 80);
      expect(io.link.sentTypes, ['input_audio_buffer.clear', 'input_audio_buffer.clear']);
      expect(results, isEmpty);
      expect(ends, 1);
      await tester.runAsync(voice.cancelListening);
    });

    testWidgets('no final words in time: the partial ones are kept', (tester) async {
      await voice.init();
      await listen();
      await sound(tester, 0.8, 3);
      io.link.emit({'type': 'conversation.item.input_audio_transcription.delta', 'item_id': 'i1', 'delta': 'half'});
      await sound(tester, 0, 15);
      await tester.pump(StreamingVoiceService.finalTimeout);
      expect(results.last, ('half', true));
      expect(ends, 1);
      await tester.runAsync(voice.cancelListening);
    });

    testWidgets('leaving voice mode closes the session', (tester) async {
      await voice.init();
      await listen();
      await tester.runAsync(voice.cancelListening);
      expect(io.link.closed, isTrue);
      expect(ends, 1);
      expect(voice.isListening, isFalse);
    });

    test('replies are streamed; a failed stream is spoken by the device', () async {
      await voice.init();
      await voice.speak('  What happens when it is negative?  ');
      expect(io.streamed, ['What happens when it is negative?']);
      io.streamError = StateError('502');
      await voice.speak('Try again.');
      expect(device.spoken, ['Try again.']);
    });

    test('no live voice on the server: the device does it all', () async {
      api.available = false;
      expect(await voice.init(), isTrue);
      expect(voice.usesLive, isFalse);
      await listen();
      expect(device.listenCalls, 1);
      expect(io.connects, 0);
    });

    test('the session cannot be opened: this turn and the next go to the device', () async {
      io.connectError = StateError('refused');
      await voice.init();
      await listen();
      expect(device.listenCalls, 1);
      await listen();
      expect(device.listenCalls, 2);
      expect(io.connects, 1);
    });
  });

  group('the home page: the realtime Guide', () {
    late List<List<ChatMessage>> shown;
    late VoiceModeController turns;
    late RealtimeGuideMode guide;

    setUp(() {
      shown = [];
      turns = VoiceModeController(voice: device, onHeard: (_) async => (speak: null, keepGoing: true));
      guide = RealtimeGuideMode(api: api, io: io, fallback: turns, onMessages: shown.add);
    });

    tearDown(() => guide.dispose());

    test('it connects with the speaker on and follows who is talking', () async {
      expect(await guide.start(), isTrue);
      expect(guide.isRealtime, isTrue);
      expect(io.path, '/api/voice/realtime/guide');
      expect(io.playReplies, isTrue);
      expect(guide.state, VoiceModeState.listening);
      final link = io.link;
      link.emit({'type': 'input_audio_buffer.speech_started', 'item_id': 'u1'});
      link.emit({'type': 'conversation.item.input_audio_transcription.delta', 'item_id': 'u1', 'delta': 'Hello'});
      expect(guide.heard, 'Hello');
      link.emit({'type': 'input_audio_buffer.speech_stopped', 'item_id': 'u1'});
      expect(guide.state, VoiceModeState.thinking);
      link.emit({'type': 'output_audio_buffer.started'});
      expect(guide.state, VoiceModeState.speaking);
      await guide.interrupt();
      expect(link.sentTypes, ['output_audio_buffer.clear', 'response.cancel']);
      link.emit({'type': 'output_audio_buffer.cleared'});
      expect(guide.state, VoiceModeState.listening);
    });

    test('small talk is kept in the history: their words, then hers', () async {
      await guide.start();
      final link = io.link;
      link.emit({'type': 'input_audio_buffer.committed', 'item_id': 'u1'});
      link.emit({
        'type': 'conversation.item.input_audio_transcription.completed',
        'item_id': 'u1',
        'transcript': 'Hi there',
      });
      link.emit({
        'type': 'response.done',
        'response': {
          'status': 'completed',
          'usage': {
            'input_token_details': {
              'text_tokens': 900,
              'audio_tokens': 40,
              'cached_tokens_details': {'text_tokens': 800, 'audio_tokens': 0},
            },
            'output_token_details': {'text_tokens': 20, 'audio_tokens': 60},
          },
          'output': [
            {
              'type': 'message',
              'content': [
                {'type': 'output_audio', 'transcript': 'Hi! What shall we learn today?'},
              ],
            },
          ],
        },
      });
      await pumpEventQueue();
      expect(api.usage.last, containsPair('kind', 'guide'));
      expect(api.usage.last, containsPair('text_in', 900));
      expect(api.usage.last, containsPair('text_in_cached', 800));
      expect(api.usage.last, containsPair('audio_out', 60));
      expect(api.usage.last, containsPair('turns', 1));
      expect(api.logs, hasLength(1));
      expect([for (final l in api.logs.single) l.content], ['Hi there', 'Hi! What shall we learn today?']);
      expect(shown.single, hasLength(2));
    });

    test('a tool call runs on the server with their own words and the answer goes back', () async {
      await guide.start();
      final link = io.link;
      link.emit({'type': 'input_audio_buffer.committed', 'item_id': 'u1'});
      link.emit({
        'type': 'conversation.item.input_audio_transcription.completed',
        'item_id': 'u1',
        'transcript': 'I slept seven hours',
      });
      link.emit({
        'type': 'response.done',
        'response': {
          'status': 'completed',
          'output': [
            {'type': 'function_call', 'name': 'log_checkin', 'call_id': 'c1', 'arguments': '{"said":"slept 7h"}'},
          ],
        },
      });
      await pumpEventQueue();
      expect(api.acts.single.$1, 'checkin');
      expect(api.acts.single.$3, 'I slept seven hours');
      expect(shown.single.map((m) => m.content), ['I slept seven hours', 'Logged: sleep 7 h']);
      final output = link.sent.firstWhere((e) => e['type'] == 'conversation.item.create');
      expect((output['item']! as Map)['call_id'], 'c1');
      expect(jsonDecode((output['item']! as Map)['output'] as String), {'done': 'Logged: sleep 7 h', 'navigating': false});
      expect(link.sentTypes.last, 'response.create');

      // Her spoken answer to the result is kept, their words are not saved twice.
      link.emit({
        'type': 'response.done',
        'response': {
          'status': 'completed',
          'output': [
            {
              'type': 'message',
              'content': [
                {'type': 'output_audio', 'transcript': 'Seven hours, nice.'},
              ],
            },
          ],
        },
      });
      await pumpEventQueue();
      expect([for (final l in api.logs.single) l.content], ['Seven hours, nice.']);
    });

    test('a failing tool tells the model so', () async {
      final g = RealtimeGuideMode(api: _FailingApi(), io: io, fallback: turns, onMessages: shown.add);
      await g.start();
      io.link.emit({
        'type': 'response.done',
        'response': {
          'output': [
            {'type': 'function_call', 'name': 'build_course', 'call_id': 'c9', 'arguments': '{"topic":"Go"}'},
          ],
        },
      });
      await pumpEventQueue();
      final output = io.link.sent.firstWhere((e) => e['type'] == 'conversation.item.create');
      expect(jsonDecode((output['item']! as Map)['output'] as String), contains('error'));
      expect(io.link.sentTypes.last, 'response.create');
    });

    test("without live voice it takes turns over the app's voice", () async {
      api.available = false;
      expect(await guide.start(), isTrue);
      expect(guide.isRealtime, isFalse);
      expect(io.connects, 0);
      expect(device.listenCalls, 1);
      expect(guide.state, VoiceModeState.listening);
      await guide.stop();
      expect(guide.state, VoiceModeState.off);
    });

    test('a session that cannot be opened falls back too', () async {
      io.connectError = StateError('refused');
      expect(await guide.start(), isTrue);
      expect(guide.isRealtime, isFalse);
      expect(device.listenCalls, 1);
    });

    test('stop closes the session and reports its usage once more', () async {
      await guide.start();
      await guide.stop();
      expect(io.link.closed, isTrue);
      expect(api.usage, hasLength(1));
      expect(guide.state, VoiceModeState.off);
    });
  });

  group('the home page: the Guide on GPT-Live', () {
    late List<List<ChatMessage>> shown;
    late VoiceModeController turns;
    late LiveGuideMode guide;
    late DateTime now;

    LiveGuideMode make(_LiveApi on) => LiveGuideMode(
      api: on,
      io: io,
      onMessages: shown.add,
      fallback: RealtimeGuideMode(api: on, io: io, fallback: turns, onMessages: shown.add),
      clock: () => now,
    );

    setUp(() {
      shown = [];
      now = DateTime.utc(2026, 10, 8, 3);
      turns = VoiceModeController(voice: device, onHeard: (_) async => (speak: null, keepGoing: true));
      guide = make(api);
    });

    tearDown(() => guide.dispose());

    Map<String, Object?> backend(String delegation, Map<String, Object?> event) =>
        {'type': 'response.event', 'delegation_id': delegation, 'event': event};

    test('it connects to GPT-Live and follows who is talking by the sound of her voice', () async {
      expect(await guide.start(), isTrue);
      expect(guide.isLive, isTrue);
      expect(io.path, '/api/voice/live/guide');
      expect(io.playReplies, isTrue);
      expect(guide.state, VoiceModeState.listening);
      io.link.emit({'type': 'session.input_transcript.delta', 'delta': 'Hello', 'start_ms': 0, 'end_ms': 300});
      expect(guide.heard, 'Hello');
      io.onReplyLevel!(0.5);
      expect(guide.state, VoiceModeState.speaking);
      io.onReplyLevel!(0.01); // a gap between words
      expect(guide.state, VoiceModeState.speaking);
      await guide.interrupt();
      expect(io.link.sentTypes, ['session.instructions.append']);
      now = now.add(const Duration(milliseconds: 800));
      io.onReplyLevel!(0.01);
      expect(guide.state, VoiceModeState.listening);
    });

    test('small talk is kept turn by turn, and the session is billed by its seconds', () async {
      await guide.start();
      final link = io.link;
      link.emit({'type': 'session.input_transcript.delta', 'delta': 'Hi '});
      link.emit({'type': 'session.input_transcript.delta', 'delta': 'there'});
      link.emit({'type': 'session.output_transcript.delta', 'delta': 'Hi! What shall '});
      link.emit({'type': 'session.output_transcript.delta', 'delta': 'we learn today?'});
      expect(api.logs, isEmpty); // her turn may go on
      link.emit({'type': 'session.input_transcript.delta', 'delta': 'Maths'});
      await pumpEventQueue();
      expect([for (final l in api.logs.single) l.content], ['Hi there', 'Hi! What shall we learn today?']);

      link.emit({'type': 'session.usage.updated', 'usage': {'seconds': 12}});
      final stopping = guide.stop();
      link.emit({'type': 'session.closed', 'reason': 'close_requested', 'usage': {'seconds': 15}});
      await stopping;
      expect(link.sentTypes, contains('session.close'));
      expect(link.closed, isTrue);
      expect(api.usage.last, containsPair('model', 'gpt-live-1'));
      expect(api.usage.last, containsPair('seconds', 15));
      // Their last words, which she never answered, are kept on stop.
      expect([for (final l in api.logs.last) l.content], ['Maths']);
    });

    test("the backend's tool call runs here with their words; the result goes back and it goes on", () async {
      await guide.start();
      final link = io.link;
      link.emit({'type': 'session.input_transcript.delta', 'delta': 'I slept from 11 to 7'});
      link.emit({'type': 'session.delegation.created', 'delegation': {'id': 'd1', 'target': 'responses'}});
      expect(guide.state, VoiceModeState.thinking);
      link.emit(backend('d1', {
        'type': 'response.output_item.done',
        'item': {
          'type': 'function_call',
          'name': 'log_checkin',
          'call_id': 'c1',
          'arguments': '{"said":"I slept from 11 to 7"}',
        },
      }));
      link.emit(backend('d1', {
        'type': 'response.completed',
        'response': {
          'id': 'r1',
          'output': <Object>[],
          'usage': {'input_tokens': 1500, 'input_tokens_details': {'cached_tokens': 1000}, 'output_tokens': 40},
        },
      }));
      await pumpEventQueue();

      final (intent, args, said) = api.acts.single;
      expect((intent, args['said'], said), ('checkin', 'I slept from 11 to 7', 'I slept from 11 to 7'));
      expect(shown.single.map((m) => m.content), ['I slept from 11 to 7', 'Logged: sleep 7 h']);
      final output = link.sent.firstWhere((e) => e['type'] == 'response.item.create');
      expect(output['item'], {
        'type': 'function_call_output',
        'call_id': 'c1',
        'output': jsonEncode({'done': 'Logged: sleep 7 h', 'navigating': false}),
      });
      expect(link.sentTypes.last, 'response.create');
      expect(api.usage.last, containsPair('text_in', 1500));
      expect(api.usage.last, containsPair('text_in_cached', 1000));
      expect(api.usage.last, containsPair('text_out', 40));

      // Her answer is kept; their words, already saved by the tool, are not saved twice.
      link.emit({'type': 'session.output_transcript.delta', 'delta': 'Eight hours, nice.'});
      link.emit({'type': 'session.input_transcript.delta', 'delta': 'Thanks'});
      await pumpEventQueue();
      expect([for (final l in api.logs.single) l.content], ['Eight hours, nice.']);
    });

    test('it closes itself after a minute of silence', () async {
      await guide.start();
      now = now.add(const Duration(seconds: 59));
      guide.checkIdle();
      expect(guide.isLive, isTrue);
      now = now.add(const Duration(seconds: 2));
      guide.checkIdle();
      await pumpEventQueue();
      expect(io.link.sentTypes, contains('session.close'));
      expect(guide.isLive, isFalse);
    });

    test('a server that prefers Realtime gets the Realtime Guide', () async {
      api.guide = 'realtime';
      expect(await guide.start(), isTrue);
      expect(guide.isLive, isFalse);
      expect(io.path, '/api/voice/realtime/guide');
      expect(guide.state, VoiceModeState.listening);
      await guide.stop();
      expect(guide.state, VoiceModeState.off);
    });

    test('a GPT-Live session that cannot be opened falls back to Realtime', () async {
      io.refusePath = '/voice/live/guide';
      expect(await guide.start(), isTrue);
      expect(guide.isLive, isFalse);
      expect(io.connects, 2);
      expect(io.path, '/api/voice/realtime/guide');
    });

    test("without live voice it takes turns over the app's voice", () async {
      api.available = false;
      expect(await guide.start(), isTrue);
      expect(io.connects, 0);
      expect(device.listenCalls, 1);
    });
  });
}

class _FailingApi extends _LiveApi {
  @override
  Future<List<ChatMessage>> chatAct(String intent, {Map<String, Object?> args = const {}, String said = ''}) async =>
      throw const ApiException(502, 'course failed');
}
