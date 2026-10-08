import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'audio_io.dart';

/// [AudioIo] over MediaRecorder (recording), an AnalyserNode (loudness) and
/// an AudioContext (playback; one context, woken up by a tap, so later
/// replies can play without one).
AudioIo createAudioIo() => _WebAudioIo();

/// Recording formats in order of preference, with the extension the server
/// expects: Opus in WebM (Chrome, Firefox, Edge), AAC in MP4 (Safari).
const _formats = [
  ('audio/webm;codecs=opus', 'webm'),
  ('audio/webm', 'webm'),
  ('audio/mp4', 'mp4'),
];

class _WebAudioIo implements AudioIo {
  web.AudioContext? _context;
  web.MediaStream? _stream;
  web.MediaRecorder? _recorder;
  String _extension = 'webm';
  final List<web.Blob> _chunks = [];
  Completer<void>? _stopped;
  Timer? _meter;
  web.AudioBufferSourceNode? _source;
  Completer<void>? _playing;

  @override
  bool get supported {
    try {
      return web.window.navigator.mediaDevices.isA<web.MediaDevices>() &&
          _formats.any((f) => web.MediaRecorder.isTypeSupported(f.$1));
    } on Object {
      return false;
    }
  }

  web.AudioContext get _audio => _context ??= web.AudioContext();

  @override
  void unlock() {
    try {
      final context = _audio;
      if (context.state == 'suspended') unawaited(context.resume().toDart);
    } on Object catch (e) {
      debugPrint('WebAudioIo: no audio output ($e)');
    }
  }

  Future<web.MediaStream> _open() => web.window.navigator.mediaDevices
      .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
      .toDart;

  void _release(web.MediaStream? stream) {
    if (stream == null) return;
    for (final track in stream.getTracks().toDart) {
      track.stop();
    }
  }

  @override
  Future<bool> requestMicrophone() async {
    try {
      _release(await _open());
      return true;
    } on Object catch (e) {
      debugPrint('WebAudioIo: microphone refused ($e)');
      return false;
    }
  }

  @override
  Future<void> startRecording({required void Function(double level) onLevel}) async {
    await stopRecording();
    final stream = await _open();
    _stream = stream;
    final format = _formats.firstWhere((f) => web.MediaRecorder.isTypeSupported(f.$1));
    _extension = format.$2;
    _chunks.clear();
    final recorder = web.MediaRecorder(stream, web.MediaRecorderOptions(mimeType: format.$1));
    final stopped = Completer<void>();
    _stopped = stopped;
    recorder.ondataavailable = ((web.BlobEvent e) {
      if (e.data.size > 0) _chunks.add(e.data);
    }).toJS;
    recorder.onstop = ((web.Event _) {
      if (!stopped.isCompleted) stopped.complete();
    }).toJS;
    recorder.start();
    _recorder = recorder;

    // Loudness: the RMS of the last ~20 ms, in dB, mapped -60..-10 dBFS → 0..1.
    final context = _audio;
    final analyser = context.createAnalyser()..fftSize = 1024;
    context.createMediaStreamSource(stream).connect(analyser);
    final samples = Float32List(1024).toJS;
    _meter = Timer.periodic(const Duration(milliseconds: 50), (_) {
      analyser.getFloatTimeDomainData(samples);
      final data = samples.toDart;
      var sum = 0.0;
      for (final s in data) {
        sum += s * s;
      }
      final rms = math.sqrt(sum / data.length);
      final db = rms <= 0 ? -100.0 : 20 * math.log(rms) / math.ln10;
      onLevel(((db + 60) / 50).clamp(0.0, 1.0));
    });
  }

  @override
  Future<Recording?> stopRecording() async {
    _meter?.cancel();
    _meter = null;
    final recorder = _recorder;
    final stream = _stream;
    _recorder = null;
    _stream = null;
    if (recorder == null) {
      _release(stream);
      return null;
    }
    if (recorder.state != 'inactive') recorder.stop();
    await _stopped?.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    _release(stream);
    if (_chunks.isEmpty) return null;
    final blob = web.Blob(_chunks.toJS, web.BlobPropertyBag(type: recorder.mimeType));
    _chunks.clear();
    final buffer = await blob.arrayBuffer().toDart;
    return (bytes: buffer.toDart.asUint8List(), extension: _extension);
  }

  @override
  Future<void> play(Uint8List audio) async {
    await stopPlaying();
    final context = _audio;
    final playing = Completer<void>();
    _playing = playing;
    try {
      if (context.state == 'suspended') await context.resume().toDart;
      // decodeAudioData takes the buffer over, so hand it a copy.
      final decoded = await context.decodeAudioData(Uint8List.fromList(audio).buffer.toJS).toDart;
      if (!identical(_playing, playing)) return; // stopped while decoding
      final source = context.createBufferSource()..buffer = decoded;
      source.connect(context.destination);
      source.onended = ((web.Event _) {
        if (!playing.isCompleted) playing.complete();
      }).toJS;
      source.start();
      _source = source;
    } on Object catch (e) {
      debugPrint('WebAudioIo: could not play ($e)');
      if (!playing.isCompleted) playing.complete();
    }
    await playing.future;
    if (identical(_playing, playing)) {
      _playing = null;
      _source = null;
    }
  }

  @override
  Future<void> stopPlaying() async {
    final playing = _playing;
    final source = _source;
    _playing = null;
    _source = null;
    try {
      source?.stop();
    } on Object {
      // already ended
    }
    if (playing != null && !playing.isCompleted) playing.complete();
  }
}
