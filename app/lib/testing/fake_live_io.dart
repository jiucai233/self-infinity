import 'dart:async';
import 'dart:convert';

import '../voice/live_link.dart';

/// A [LiveLink] for tests: [emit] plays the server, [sent] is what the client sent.
class FakeLiveLink implements LiveLink {
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

/// A [LiveIo] for tests: no browser, no microphone; every session is a [FakeLiveLink].
class FakeLiveIo implements LiveIo {
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
  late FakeLiveLink link;
  Object? connectError;
  final List<String> streamed = [];
  Object? streamError;

  /// True: a stream keeps playing until [finishStream] or [stopStream].
  bool holdStream = false;
  Completer<void>? _playing;
  int streamStops = 0;

  /// The stream being played has played out.
  void finishStream() => _playing?.complete();

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
    return link = FakeLiveLink();
  }

  @override
  Future<void> playStream(LiveEndpoint endpoint, String body) async {
    if (streamError case final e?) throw e;
    streamed.add((jsonDecode(body) as Map)['text'] as String);
    if (!holdStream) return;
    final playing = _playing = Completer<void>();
    await playing.future;
  }

  @override
  Future<void> stopStream() async {
    final playing = _playing;
    if (playing == null || playing.isCompleted) return;
    streamStops++;
    playing.complete();
  }
}
