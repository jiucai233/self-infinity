import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'live_link.dart';

/// [LiveIo] over RTCPeerConnection (audio both ways, the `oai-events` data
/// channel for JSON) and fetch + Web Audio (streamed PCM).
LiveIo createLiveIo() => _WebLiveIo();

/// OpenAI's streamed speech: 24 kHz, 16-bit little-endian, mono.
const _pcmRate = 24000;

class _WebLiveIo implements LiveIo {
  web.AudioContext? _context;
  web.HTMLAudioElement? _speaker;

  // The stream being played.
  web.AbortController? _abort;
  final List<web.AudioBufferSourceNode> _scheduled = [];
  Completer<void>? _streamDone;

  web.AudioContext get _audio => _context ??= web.AudioContext();

  @override
  bool get supported {
    try {
      return web.window.navigator.mediaDevices.isA<web.MediaDevices>() &&
          globalContext.has('RTCPeerConnection');
    } on Object {
      return false;
    }
  }

  @override
  void unlock() {
    try {
      final context = _audio;
      if (context.state == 'suspended') unawaited(context.resume().toDart);
      // An element that played once inside the tap may play the model's voice later.
      final speaker = _speaker ??= (web.HTMLAudioElement()..autoplay = true);
      unawaited(speaker.play().toDart.then((_) {}, onError: (_) {}));
    } on Object catch (e) {
      debugPrint('WebLiveIo: no audio output ($e)');
    }
  }

  @override
  Future<LiveLink> connect(
    LiveEndpoint endpoint, {
    required bool playReplies,
    void Function(double level)? onLevel,
  }) async {
    final microphone = await web.window.navigator.mediaDevices
        .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
        .toDart;
    final peer = web.RTCPeerConnection();
    final link = _WebLiveLink(peer, microphone);
    try {
      if (playReplies) {
        final speaker = _speaker ??= (web.HTMLAudioElement()..autoplay = true);
        peer.ontrack = ((web.RTCTrackEvent e) {
          final streams = e.streams.toDart;
          speaker.srcObject = streams.isEmpty ? web.MediaStream([e.track].toJS) : streams.first;
          unawaited(speaker.play().toDart.then((_) {}, onError: (_) {}));
        }).toJS;
        link._speaker = speaker;
      }
      for (final track in microphone.getAudioTracks().toDart) {
        peer.addTrack(track, microphone);
      }
      final channel = peer.createDataChannel('oai-events');
      link._channel = channel;
      final opened = Completer<void>();
      channel.onopen = ((web.Event _) {
        if (!opened.isCompleted) opened.complete();
      }).toJS;
      channel.onmessage = ((web.MessageEvent e) {
        final data = e.data;
        if (data.isA<JSString>()) link._receive((data as JSString).toDart);
      }).toJS;
      channel.onclose = ((web.Event _) => link._closed()).toJS;

      final offer = await peer.createOffer().toDart;
      await peer.setLocalDescription(web.RTCLocalSessionDescriptionInit(type: 'offer', sdp: offer!.sdp)).toDart;
      final response = await _post(endpoint, peer.localDescription!.sdp, 'application/sdp');
      final answer = (await response.text().toDart).toDart;
      if (response.status != 201 && response.status != 200) {
        throw StateError('live session refused (${response.status}): $answer');
      }
      await peer.setRemoteDescription(web.RTCSessionDescriptionInit(type: 'answer', sdp: answer)).toDart;
      await opened.future.timeout(const Duration(seconds: 15));
      if (onLevel != null) link._meter(_audio, onLevel);
      return link;
    } on Object {
      await link.close();
      rethrow;
    }
  }

  Future<web.Response> _post(LiveEndpoint endpoint, String body, String contentType, {web.AbortSignal? signal}) {
    final headers = web.Headers();
    endpoint.headers.forEach((name, value) => headers.append(name, value));
    headers.append('Content-Type', contentType);
    return web.window
        .fetch(
          endpoint.url.toString().toJS,
          web.RequestInit(method: 'POST', headers: headers, body: body.toJS, signal: signal),
        )
        .toDart;
  }

  @override
  Future<void> playStream(LiveEndpoint endpoint, String body) async {
    await stopStream();
    final context = _audio;
    if (context.state == 'suspended') await context.resume().toDart;
    final abort = web.AbortController();
    _abort = abort;
    final done = Completer<void>();
    _streamDone = done;
    var next = 0.0;
    var played = false;
    Uint8List? carry; // an odd byte left over between chunks

    void schedule(Uint8List bytes) {
      var data = bytes;
      if (carry != null) {
        data = Uint8List(carry!.length + bytes.length)
          ..setAll(0, carry!)
          ..setAll(carry!.length, bytes);
        carry = null;
      }
      final even = data.length & ~1;
      if (even < data.length) carry = Uint8List.fromList([data.last]);
      if (even == 0) return;
      final samples = Float32List(even ~/ 2);
      final view = ByteData.sublistView(data, 0, even);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = view.getInt16(i * 2, Endian.little) / 32768;
      }
      final buffer = context.createBuffer(1, samples.length, _pcmRate);
      buffer.copyToChannel(samples.toJS, 0);
      final source = context.createBufferSource()..buffer = buffer;
      source.connect(context.destination);
      // A little headroom the first time, then back to back.
      final at = math.max(next, context.currentTime + (played ? 0.0 : 0.05));
      source.start(at);
      next = at + buffer.duration;
      played = true;
      _scheduled.add(source);
    }

    try {
      final response = await _post(endpoint, body, 'application/json', signal: abort.signal);
      if (response.status != 200) {
        throw StateError('speech stream refused (${response.status})');
      }
      final reader = response.body!.getReader() as web.ReadableStreamDefaultReader;
      while (!done.isCompleted) {
        final chunk = await reader.read().toDart;
        if (chunk.done) break;
        final value = chunk.value;
        if (value != null && value.isA<JSUint8Array>()) schedule((value as JSUint8Array).toDart);
      }
      // Wait for the scheduled audio to play out.
      final left = next - context.currentTime;
      if (!done.isCompleted && left > 0) {
        await Future.any([
          Future<void>.delayed(Duration(milliseconds: (left * 1000).ceil())),
          done.future,
        ]);
      }
    } on Object {
      if (!played && identical(_abort, abort) && !done.isCompleted) rethrow; // nothing played: let the caller fall back
    } finally {
      if (identical(_abort, abort)) {
        _abort = null;
        _scheduled.clear();
      }
      if (!done.isCompleted) done.complete();
    }
  }

  @override
  Future<void> stopStream() async {
    final abort = _abort;
    _abort = null;
    try {
      abort?.abort();
    } on Object {
      // already finished
    }
    for (final source in _scheduled) {
      try {
        source.stop();
      } on Object {
        // not started or already ended
      }
    }
    _scheduled.clear();
    final done = _streamDone;
    if (done != null && !done.isCompleted) done.complete();
  }
}

class _WebLiveLink implements LiveLink {
  _WebLiveLink(this._peer, this._microphone);

  final web.RTCPeerConnection _peer;
  final web.MediaStream _microphone;
  web.RTCDataChannel? _channel;
  web.HTMLAudioElement? _speaker;
  Timer? _meterTimer;
  final _events = StreamController<Map<String, Object?>>.broadcast();
  bool _isClosed = false;

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  void _receive(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, Object?> && !_events.isClosed) _events.add(decoded);
    } on FormatException {
      // not an event
    }
  }

  void _closed() {
    if (!_events.isClosed) unawaited(_events.close());
  }

  void _meter(web.AudioContext context, void Function(double level) onLevel) {
    final analyser = context.createAnalyser()..fftSize = 1024;
    context.createMediaStreamSource(_microphone).connect(analyser);
    final samples = Float32List(1024).toJS;
    _meterTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
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
  void send(Map<String, Object?> event) {
    final channel = _channel;
    if (_isClosed || channel == null || channel.readyState != 'open') return;
    channel.send(jsonEncode(event).toJS);
  }

  @override
  set microphoneOn(bool on) {
    for (final track in _microphone.getAudioTracks().toDart) {
      track.enabled = on;
    }
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    _meterTimer?.cancel();
    try {
      _channel?.close();
      _peer.close();
    } on Object {
      // already closed
    }
    for (final track in _microphone.getTracks().toDart) {
      track.stop();
    }
    final speaker = _speaker;
    if (speaker != null) speaker.srcObject = null;
    _closed();
  }
}
