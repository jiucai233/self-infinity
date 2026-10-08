/// The microphone and the speaker the server voice works through: the
/// browser's on the web (`audio_io_web.dart`), none elsewhere
/// (`audio_io_stub.dart`, the phone keeps its own speech).
library;

import 'dart:typed_data';

export 'audio_io_stub.dart' if (dart.library.js_interop) 'audio_io_web.dart';

/// One recorded utterance: the bytes and the extension of their format
/// (`webm` from Chrome and Firefox, `mp4` from Safari).
typedef Recording = ({Uint8List bytes, String extension});

/// Raw audio in and out, no speech logic.
abstract class AudioIo {
  /// Whether this platform can record and play here.
  bool get supported;

  /// Wakes the audio output up. Call it synchronously inside a tap: browsers
  /// only let a page make sound after a gesture.
  void unlock();

  /// Asks for the microphone (the browser prompts once); false when refused.
  Future<bool> requestMicrophone();

  /// Starts recording; [onLevel] gets the loudness, 0–1, many times a second.
  Future<void> startRecording({required void Function(double level) onLevel});

  /// Stops recording and releases the microphone; null when nothing was recording.
  Future<Recording?> stopRecording();

  /// Plays [audio] (MP3) and completes when it ends or is stopped.
  Future<void> play(Uint8List audio);

  /// Cuts the playing audio short.
  Future<void> stopPlaying();
}
