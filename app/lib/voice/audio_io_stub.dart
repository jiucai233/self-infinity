import 'dart:typed_data';

import 'audio_io.dart';

/// Outside the browser there is no [AudioIo]: the phone's own speech
/// recognition and synthesis are used instead.
AudioIo createAudioIo() => const _NoAudioIo();

class _NoAudioIo implements AudioIo {
  const _NoAudioIo();

  @override
  bool get supported => false;

  @override
  void unlock() {}

  @override
  Future<bool> requestMicrophone() async => false;

  @override
  Future<void> startRecording({required void Function(double level) onLevel}) async =>
      throw UnsupportedError('no audio here');

  @override
  Future<Recording?> stopRecording() async => null;

  @override
  Future<void> play(Uint8List audio) async {}

  @override
  Future<void> stopPlaying() async {}
}
