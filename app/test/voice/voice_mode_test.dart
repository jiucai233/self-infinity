// The voice loop: listen → send on silence → speak → listen; and its exits.
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/testing/fake_voice.dart';
import 'package:self_infinity/voice/voice_mode.dart';
import 'package:self_infinity/voice/voice_service.dart';

void main() {
  late FakeVoiceService voice;
  late List<String> heard;
  late VoiceReply reply;
  late int unavailable;
  late VoiceModeController mode;

  setUp(() {
    voice = FakeVoiceService();
    heard = [];
    reply = (speak: 'Yes, I heard you.', keepGoing: true);
    unavailable = 0;
    mode = VoiceModeController(
      voice: voice,
      onHeard: (text) async {
        heard.add(text);
        return reply;
      },
      onUnavailable: () => unavailable++,
    );
  });

  tearDown(() => mode.dispose());

  test('the locale is US English and a pause of 1.5 s ends an utterance', () {
    expect(kVoiceLocale, 'en_US');
    expect(kVoicePause, const Duration(milliseconds: 1500));
  });

  test('starts listening; the words and the loudness are exposed', () async {
    expect(mode.state, VoiceModeState.off);
    expect(mode.active, isFalse);
    expect(await mode.start(), isTrue);
    expect(mode.state, VoiceModeState.listening);
    expect(mode.active, isTrue);
    voice.partial('hello');
    voice.level(0.7);
    expect(mode.heard, 'hello');
    expect(mode.level, 0.7);
  });

  test(
    'on silence the words are handed over, her answer is spoken, then it listens again',
    () async {
      await mode.start();
      final states = <VoiceModeState>[];
      mode.addListener(() => states.add(mode.state));
      voice.hear('I want to learn math');
      await pumpEventQueue();
      expect(heard, ['I want to learn math']);
      expect(voice.spoken, ['Yes, I heard you.']);
      expect(
        states,
        containsAllInOrder([
          VoiceModeState.thinking,
          VoiceModeState.speaking,
          VoiceModeState.listening,
        ]),
      );
      expect(mode.state, VoiceModeState.listening);
      expect(voice.listenCalls, 2);
    },
  );

  test('nothing is spoken when there is nothing to say', () async {
    reply = (speak: null, keepGoing: true);
    await mode.start();
    voice.hear('hello');
    await pumpEventQueue();
    expect(voice.spoken, isEmpty);
    expect(mode.state, VoiceModeState.listening);
  });

  test('keepGoing false: she answers and voice mode ends', () async {
    reply = (speak: 'All done.', keepGoing: false);
    await mode.start();
    voice.hear('hello');
    await pumpEventQueue();
    expect(voice.spoken, ['All done.']);
    expect(mode.state, VoiceModeState.off);
  });

  test('a handler that throws does not break the loop', () async {
    final broken = VoiceModeController(
      voice: voice,
      onHeard: (_) async => throw StateError('boom'),
    );
    await broken.start();
    voice.hear('hello');
    await pumpEventQueue();
    expect(broken.state, VoiceModeState.listening);
    await broken.stop();
    broken.dispose();
  });

  test('stop silences the microphone and the speaker', () async {
    voice.holdSpeech = true;
    await mode.start();
    voice.hear('hello');
    await pumpEventQueue();
    expect(mode.state, VoiceModeState.speaking);
    await mode.stop();
    await pumpEventQueue();
    expect(mode.state, VoiceModeState.off);
    expect(voice.listenCalls, 1); // it did not start listening again
  });

  test('interrupt cuts her speech and listening goes on', () async {
    voice.holdSpeech = true;
    await mode.start();
    voice.hear('hello');
    await pumpEventQueue();
    expect(mode.state, VoiceModeState.speaking);
    await mode.interrupt();
    await pumpEventQueue();
    expect(mode.state, VoiceModeState.listening);
    expect(voice.listenCalls, 2);
  });

  test('interrupt while listening does nothing', () async {
    await mode.start();
    await mode.interrupt();
    expect(mode.state, VoiceModeState.listening);
  });

  test('silent rounds: it keeps listening, and gives up after three in a row', () async {
    await mode.start();
    voice.end();
    await pumpEventQueue();
    voice.end();
    await pumpEventQueue();
    expect(mode.state, VoiceModeState.listening);
    voice.end();
    await pumpEventQueue();
    expect(mode.state, VoiceModeState.off);
    expect(voice.listenCalls, 3);
  });

  test('a spoken round resets the silence counter', () async {
    await mode.start();
    voice.end();
    await pumpEventQueue();
    voice.end();
    await pumpEventQueue();
    voice.hear('hello');
    await pumpEventQueue();
    voice.end();
    await pumpEventQueue();
    voice.end();
    await pumpEventQueue();
    expect(mode.active, isTrue);
  });

  test('without speech support: onUnavailable, state stays off, no listening', () async {
    voice.available = false;
    expect(await mode.start(), isFalse);
    expect(unavailable, 1);
    expect(mode.state, VoiceModeState.off);
    expect(voice.listenCalls, 0);
  });

  test('start twice is harmless', () async {
    await mode.start();
    expect(await mode.start(), isTrue);
    expect(voice.listenCalls, 1);
  });

  test('results after stop are ignored', () async {
    await mode.start();
    await mode.stop();
    voice.partial('a late result');
    expect(mode.heard, isNot('a late result'));
  });
}
