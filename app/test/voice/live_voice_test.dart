// Live voice: the audit's streamed turns over one transcription session, and
// the home page's realtime Guide with its tools; both fall back without it.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/api_exception.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/testing/fake_live_io.dart';
import 'package:self_infinity/testing/fake_voice.dart';
import 'package:self_infinity/voice/live_audit.dart';
import 'package:self_infinity/voice/live_guide.dart';
import 'package:self_infinity/voice/live_link.dart';
import 'package:self_infinity/voice/pause_detector.dart';
import 'package:self_infinity/voice/realtime_guide.dart';
import 'package:self_infinity/voice/streaming_voice_service.dart';
import 'package:self_infinity/voice/voice_mode.dart';

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

  String audit = 'live';

  @override
  Future<String?> auditVoice() async => available ? audit : null;

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
  late FakeLiveIo io;
  late _LiveApi api;
  late FakeVoiceService device;

  setUp(() {
    io = FakeLiveIo();
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

    /// One turn heard and answered, so the session is open and she can speak.
    Future<void> firstTurn(WidgetTester tester) async {
      await voice.init();
      await listen();
      await sound(tester, 0.8, 3);
      await sound(tester, 0, 15);
      io.link.emit({'type': 'input_audio_buffer.committed', 'item_id': 'i1'});
      io.link.emit({
        'type': 'conversation.item.input_audio_transcription.completed',
        'item_id': 'i1',
        'transcript': 'First answer.',
      });
      expect(ends, 1);
      io.link.sent.clear();
    }

    testWidgets('speaking over her cuts her short, and the turn keeps the words said from then on', (
      tester,
    ) async {
      await firstTurn(tester);
      final link = io.link;
      io.holdStream = true;
      var spoken = false;
      unawaited(voice.speak('Right. Now a longer question about the softmax.').then((_) => spoken = true));
      await tester.pump();
      expect(link.mic, isTrue); // open while she speaks
      expect(link.sentTypes, ['input_audio_buffer.clear']);

      // A cough: loud, but not for long enough.
      for (var i = 0; i < StreamingVoiceService.bargeSamples - 1; i++) {
        io.level(0.8);
      }
      io.level(0.1);
      await tester.pump();
      expect((spoken, io.streamStops), (false, 0));

      // They start talking: the first loud level drops what the microphone held before it.
      link.sent.clear();
      for (var i = 0; i < StreamingVoiceService.bargeSamples; i++) {
        io.level(0.8);
      }
      await tester.pump();
      expect(io.streamStops, 1);
      expect(spoken, isTrue);
      expect(link.sentTypes, ['input_audio_buffer.clear']);
      expect(link.mic, isTrue);

      // The next turn is already running: nothing is cleared, and a pause alone commits it.
      link.sent.clear();
      await listen();
      expect(link.sentTypes, isEmpty);
      await sound(tester, 0, 15);
      expect(link.sentTypes, ['input_audio_buffer.commit']);
      link.emit({'type': 'input_audio_buffer.committed', 'item_id': 'i2'});
      link.emit({
        'type': 'conversation.item.input_audio_transcription.completed',
        'item_id': 'i2',
        'transcript': 'Wait, I meant the keys.',
      });
      expect(results.last, ('Wait, I meant the keys.', true));
      await tester.runAsync(voice.cancelListening);
    });

    testWidgets('left to finish, she is not cut short and the microphone closes again', (tester) async {
      await firstTurn(tester);
      final link = io.link;
      io.holdStream = true;
      var spoken = false;
      unawaited(voice.speak('A question.').then((_) => spoken = true));
      await tester.pump();
      io.level(0.3); // her own voice, what echo cancellation left of it
      io.level(0.3);
      io.finishStream();
      await tester.pump();
      expect((spoken, io.streamStops, link.mic), (true, 0, false));

      // The turn after it starts clean.
      link.sent.clear();
      await listen();
      expect(link.sentTypes, ['input_audio_buffer.clear']);
      await tester.runAsync(voice.cancelListening);
    });

    testWidgets('a tap that stops her closes the microphone too', (tester) async {
      await firstTurn(tester);
      io.holdStream = true;
      unawaited(voice.speak('A question.'));
      await tester.pump();
      expect(io.link.mic, isTrue);
      await voice.stopSpeaking();
      await tester.pump();
      expect((io.streamStops, io.link.mic), (1, false));
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

  group('the audit on GPT-Live', () {
    late VoiceModeController turns;
    late LiveAuditMode mode;
    late DateTime now;
    late List<String> answers;
    late VoiceReply reply;
    String? question;

    setUp(() {
      now = DateTime.utc(2026, 10, 12, 3);
      answers = [];
      reply = (speak: 'Right: weights come from a softmax. What would happen without it?', keepGoing: true);
      question = 'How does self-attention weigh the tokens?';
      turns = VoiceModeController(voice: device, onHeard: (_) async => (speak: null, keepGoing: true));
      mode = LiveAuditMode(
        api: api,
        io: io,
        fallback: turns,
        onHeard: (heard) async {
          answers.add(heard);
          return reply;
        },
        opening: () => question,
        settle: Duration.zero,
        clock: () => now,
      );
    });

    tearDown(() => mode.dispose());

    List<Map<String, Object?>> sentOf(String type) => [
      for (final e in io.link.sent)
        if (e['type'] == type) e,
    ];

    void handOver(String id) =>
        io.link.emit({'type': 'session.delegation.created', 'delegation': {'id': id, 'type': 'delegation', 'target': 'client'}});

    test('it opens a GPT-Live session and she says the question on the table, once', () async {
      expect(await mode.start(), isTrue);
      expect(mode.isLive, isTrue);
      expect(io.path, '/api/voice/live/audit');
      expect(io.playReplies, isTrue);
      expect(mode.state, VoiceModeState.listening);
      io.link.emit({'type': 'session.started', 'session': {'model': 'gpt-live-1'}});
      io.link.emit({'type': 'session.started', 'session': {'model': 'gpt-live-1'}});
      final said = sentOf('session.instructions.append').single;
      expect(said['delegation_id'], isNull);
      expect(said['content'], contains('How does self-attention weigh the tokens?'));
    });

    test('a finished answer goes to the Auditor with their words, and she says what comes back', () async {
      await mode.start();
      final link = io.link;
      link.emit({'type': 'session.started'});
      link.emit({'type': 'session.input_transcript.delta', 'delta': 'It scores every pair '});
      link.emit({'type': 'session.input_transcript.delta', 'delta': 'and normalises the scores'});
      expect(mode.heard, 'It scores every pair and normalises the scores');
      handOver('d1');
      expect(mode.state, VoiceModeState.thinking);
      await pumpEventQueue();

      expect(answers, ['It scores every pair and normalises the scores']);
      expect(sentOf('session.commentary.append').single, {
        'type': 'session.commentary.append',
        'delegation_id': 'd1',
        'content': 'Right: weights come from a softmax. What would happen without it?',
      });
      expect(mode.heard, ''); // the next answer starts empty
      expect(mode.state, VoiceModeState.listening);
      expect(api.usage.last, containsPair('kind', 'audit'));
      expect(api.usage.last, containsPair('turns', 1));
    });

    test('she can be cut short: while she speaks their words are still heard', () async {
      await mode.start();
      io.onReplyLevel!(0.5);
      expect(mode.state, VoiceModeState.speaking);
      io.link.emit({'type': 'session.input_transcript.delta', 'delta': 'Wait, I meant the keys'});
      expect(mode.heard, 'Wait, I meant the keys');
      await mode.interrupt(); // a tap on her face does it too
      expect(sentOf('session.instructions.append').last['content'], contains('Stop speaking now'));
    });

    test('a hand-over with nothing said judges nothing', () async {
      await mode.start();
      io.link.emit({'type': 'session.started'});
      handOver('d1');
      await pumpEventQueue();
      expect(answers, isEmpty);
      expect(sentOf('session.commentary.append'), isEmpty);
      final told = sentOf('session.instructions.append').last;
      expect(told['delegation_id'], 'd1');
      expect(told['content'], contains('has not answered yet'));
    });

    test('an answer that could not be judged: she says so instead of making something up', () async {
      await mode.start();
      reply = (speak: null, keepGoing: true);
      io.link.emit({'type': 'session.input_transcript.delta', 'delta': 'It is a weighted sum'});
      handOver('d1');
      await pumpEventQueue();
      expect(answers, ['It is a weighted sum']);
      expect(sentOf('session.commentary.append'), isEmpty);
      expect(sentOf('session.instructions.append').last['content'], contains('could not be judged'));
    });

    test('a hand-over while the Auditor is judging waits its turn', () async {
      final judging = Completer<VoiceReply>();
      final slow = LiveAuditMode(
        api: api,
        io: io,
        fallback: VoiceModeController(voice: device, onHeard: (_) async => (speak: null, keepGoing: true)),
        onHeard: (heard) {
          answers.add(heard);
          return answers.length == 1 ? judging.future : Future.value(reply);
        },
        opening: () => null,
        settle: Duration.zero,
        clock: () => now,
      );
      addTearDown(slow.dispose);
      await slow.start();
      final link = io.link;
      link.emit({'type': 'session.input_transcript.delta', 'delta': 'First answer'});
      handOver('d1');
      await pumpEventQueue();
      link.emit({'type': 'session.input_transcript.delta', 'delta': 'and one more thing'});
      handOver('d2');
      await pumpEventQueue();
      expect(answers, ['First answer']);
      judging.complete((speak: 'Good. Next question?', keepGoing: true));
      await pumpEventQueue();
      expect(answers, ['First answer', 'and one more thing']);
      expect([for (final e in link.sent) if (e['type'] == 'session.commentary.append') e['delegation_id']], ['d1', 'd2']);
    });

    test('after the verdict she says her last line and the session closes', () async {
      await mode.start();
      final link = io.link;
      reply = (speak: 'Not quite. The softmax was missing from your account.', keepGoing: false);
      link.emit({'type': 'session.input_transcript.delta', 'delta': 'I do not know'});
      handOver('d1');
      await pumpEventQueue();
      expect(sentOf('session.commentary.append'), hasLength(1));

      // "One moment" ending is not her last line: it has not been said yet.
      io.onReplyLevel!(0.5);
      now = now.add(const Duration(seconds: 1));
      io.onReplyLevel!(0.01);
      expect(mode.isLive, isTrue);

      link.emit({'type': 'session.output_transcript.delta', 'delta': 'Not quite. The softmax was missing.'});
      io.onReplyLevel!(0.5);
      now = now.add(const Duration(seconds: 1));
      io.onReplyLevel!(0.01);
      await pumpEventQueue();
      expect(link.sentTypes, contains('session.close'));
      expect(mode.isLive, isFalse);
      link.emit({'type': 'session.closed', 'reason': 'close_requested', 'usage': {'seconds': 42}});
      await pumpEventQueue();
    });

    test('it closes itself after a minute and a half of silence', () async {
      await mode.start();
      now = now.add(const Duration(seconds: 89));
      mode.checkIdle();
      expect(mode.isLive, isTrue);
      now = now.add(const Duration(seconds: 2));
      mode.checkIdle();
      await pumpEventQueue();
      expect(io.link.sentTypes, contains('session.close'));
      expect(mode.isLive, isFalse);
    });

    test('a server that prefers turns, or no session: it takes turns', () async {
      api.audit = 'turns';
      expect(await mode.start(), isTrue);
      expect(mode.isLive, isFalse);
      expect(io.connects, 0);
      expect(device.listenCalls, 1);
      await mode.stop();
      expect(mode.state, VoiceModeState.off);
    });

    test('a GPT-Live session that cannot be opened falls back to turns', () async {
      io.refusePath = '/voice/live/audit';
      expect(await mode.start(), isTrue);
      expect(mode.isLive, isFalse);
      expect(device.listenCalls, 1);
    });

    test('a line too long for one append is cut at the ends of sentences', () {
      expect(LiveAuditMode.partsOf('Right. What next?'), ['Right. What next?']);
      final long = List.filled(60, 'This sentence is about thirty-five chars.').join(' ');
      final parts = LiveAuditMode.partsOf(long);
      expect(parts.length, greaterThan(1));
      expect(parts.join(' '), long);
      expect(parts.every((p) => p.endsWith('.')), isTrue);
      final chinese = List.filled(40, '这一句话大约有十五个汉字左右。').join();
      expect(LiveAuditMode.partsOf(chinese).length, greaterThan(1));
      expect(LiveAuditMode.partsOf(chinese).join(), chinese);
    });
  });
}

class _FailingApi extends _LiveApi {
  @override
  Future<List<ChatMessage>> chatAct(String intent, {Map<String, Object?> args = const {}, String said = ''}) async =>
      throw const ApiException(502, 'course failed');
}
