// The server's voice in the browser: utterances end on a pause, the server
// writes them down and reads replies aloud; without it, the device's speech.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/api_exception.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/testing/fake_voice.dart';
import 'package:self_infinity/voice/audio_io.dart';
import 'package:self_infinity/voice/cloud_voice_service.dart';

/// The browser's microphone and speaker, scripted.
class _FakeIo implements AudioIo {
  bool micAllowed = true;
  bool recording = false;
  int unlocks = 0;
  void Function(double level)? _onLevel;
  final List<Uint8List> played = [];

  @override
  bool supported = true;

  void level(double v) => _onLevel?.call(v);

  @override
  void unlock() => unlocks++;

  @override
  Future<bool> requestMicrophone() async => micAllowed;

  @override
  Future<void> startRecording({required void Function(double level) onLevel}) async {
    recording = true;
    _onLevel = onLevel;
  }

  @override
  Future<Recording?> stopRecording() async {
    if (!recording) return null;
    recording = false;
    _onLevel = null;
    return (bytes: Uint8List.fromList([1, 2, 3]), extension: 'webm');
  }

  @override
  Future<void> play(Uint8List audio) async => played.add(audio);

  @override
  Future<void> stopPlaying() async {}
}

/// The server's voice endpoints, scripted.
class _VoiceApi extends FakeApiClient {
  _VoiceApi() : super(latency: Duration.zero);

  bool available = true;
  String transcript = 'the discriminant is b squared minus 4ac';
  ApiException? speechError;
  final List<String> uploads = [];
  final List<String> spoken = [];

  @override
  Future<bool> voiceAvailable() async => available;

  @override
  Future<String> transcribe(Uint8List audio, {required String filename}) async {
    uploads.add(filename);
    return transcript;
  }

  @override
  Future<Uint8List> speech(String text) async {
    spoken.add(text);
    if (speechError case final e?) throw e;
    return Uint8List.fromList([9, 9]);
  }
}

void main() {
  late _FakeIo io;
  late _VoiceApi api;
  late FakeVoiceService device;
  late CloudVoiceService voice;
  late List<(String, bool)> results;
  late int ends;

  setUp(() {
    io = _FakeIo();
    api = _VoiceApi();
    device = FakeVoiceService();
    voice = CloudVoiceService(api: api, device: device, io: io);
    results = [];
    ends = 0;
  });

  Future<void> listen({Duration pauseFor = const Duration(milliseconds: 1500)}) => voice.listen(
    pauseFor: pauseFor,
    onResult: (text, {required isFinal}) => results.add((text, isFinal)),
    onEnd: () => ends++,
  );

  /// [ticks] of 100 ms at loudness [level].
  Future<void> sound(WidgetTester tester, double level, int ticks) async {
    for (var i = 0; i < ticks; i++) {
      io.level(level);
      await tester.pump(CloudVoiceService.tick);
    }
  }

  testWidgets('speech, then a pause: the server writes it down', (tester) async {
    expect(await voice.init(), isTrue);
    expect(voice.usesServer, isTrue);
    expect(io.unlocks, 1);
    await listen();
    expect(voice.isListening, isTrue);
    await sound(tester, 0.8, 10); // a second of speech
    await sound(tester, 0.05, 14); // 1.4 s of quiet: not yet
    expect(io.recording, isTrue);
    await sound(tester, 0.05, 1); // 1.5 s
    await tester.pump();
    expect(io.recording, isFalse);
    expect(api.uploads, ['speech.webm']);
    expect(results, [('the discriminant is b squared minus 4ac', true)]);
    expect(ends, 1);
    expect(voice.isListening, isFalse);
    expect(device.listenCalls, 0);
  });

  testWidgets('no speech at all: it gives up after 8 s and uploads nothing', (tester) async {
    await voice.init();
    await listen();
    await sound(tester, 0.1, 79);
    expect(io.recording, isTrue);
    await sound(tester, 0.1, 1);
    await tester.pump();
    expect(io.recording, isFalse);
    expect(api.uploads, isEmpty);
    expect(results, isEmpty);
    expect(ends, 1);
  });

  testWidgets('stop keeps what was said; cancel drops it', (tester) async {
    await voice.init();
    await listen(pauseFor: const Duration(seconds: 3));
    await sound(tester, 0.8, 5);
    await voice.stopListening();
    expect(results, hasLength(1));
    expect(ends, 1);

    await listen();
    await sound(tester, 0.8, 5);
    await voice.cancelListening();
    await tester.pump(const Duration(seconds: 5));
    expect(api.uploads, hasLength(1));
    expect(results, hasLength(1));
    expect(ends, 2);
  });

  testWidgets('a silent transcript is no result', (tester) async {
    api.transcript = '  ';
    await voice.init();
    await listen();
    await sound(tester, 0.8, 3);
    await sound(tester, 0, 15);
    await tester.pump();
    expect(api.uploads, hasLength(1));
    expect(results, isEmpty);
    expect(ends, 1);
  });

  test('replies are read aloud by the server; if it fails, by the device', () async {
    await voice.init();
    await voice.speak('  What does it tell you?  ');
    expect(api.spoken, ['What does it tell you?']);
    expect(io.played, hasLength(1));
    expect(device.spoken, isEmpty);

    api.speechError = const ApiException(502, 'speech failed');
    await voice.speak('And when it is negative?');
    expect(io.played, hasLength(1));
    expect(device.spoken, ['And when it is negative?']);
  });

  test('no server voice: everything goes to the device', () async {
    api.available = false;
    expect(await voice.init(), isTrue);
    expect(voice.usesServer, isFalse);
    expect(device.initCalls, 1);
    await voice.listen(onResult: (_, {required isFinal}) {}, onEnd: () {});
    expect(device.listenCalls, 1);
    await voice.speak('hi');
    expect(device.spoken, ['hi']);
    expect(api.spoken, isEmpty);
  });

  test('no recording here (a phone): the device, and the server is not asked', () async {
    io.supported = false;
    expect(await voice.init(), isTrue);
    expect(voice.usesServer, isFalse);
    expect(io.unlocks, 0);
    expect(device.initCalls, 1);
  });

  test('a refused microphone is unavailable; it asks again next time', () async {
    io.micAllowed = false;
    expect(await voice.init(), isFalse);
    expect(voice.usesServer, isFalse);
    io.micAllowed = true;
    expect(await voice.init(), isTrue);
    expect(voice.usesServer, isTrue);
  });
}
