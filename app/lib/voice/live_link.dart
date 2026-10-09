/// The pieces of live voice that do not touch the browser, so the logic built
/// on them runs (and is tested) anywhere.
library;

/// Where a live request goes and the headers it carries (the account's token,
/// the language).
typedef LiveEndpoint = ({Uri url, Map<String, String> headers});

/// One open session with the Realtime API or GPT-Live: audio flows on its
/// own; JSON events travel both ways here.
abstract class LiveLink {
  /// The server's events, decoded.
  Stream<Map<String, Object?>> get events;

  /// Sends a client event.
  void send(Map<String, Object?> event);

  /// Mutes the microphone (silence is sent) or opens it again.
  set microphoneOn(bool on);

  /// Ends the session and releases the microphone.
  Future<void> close();
}

/// The browser's side of live voice.
abstract class LiveIo {
  /// Whether this platform can hold a live session here.
  bool get supported;

  /// Wakes the audio output; call it synchronously inside a tap.
  void unlock();

  /// Opens a session: the microphone goes in, and with [playReplies] the
  /// model's voice comes out of the speaker. [endpoint] takes the SDP offer and
  /// answers with OpenAI's SDP. [onLevel] gets the microphone's loudness, 0–1;
  /// [onReplyLevel] the loudness of the model's voice as it plays (GPT-Live
  /// sends no event when it starts or stops speaking).
  Future<LiveLink> connect(
    LiveEndpoint endpoint, {
    required bool playReplies,
    void Function(double level)? onLevel,
    void Function(double level)? onReplyLevel,
  });

  /// Plays the raw 24 kHz 16-bit PCM that [endpoint] streams back for the JSON
  /// [body] while it is still arriving; completes when it has played out (or
  /// [stopStream] was called). Throws when the request fails before any sound.
  Future<void> playStream(LiveEndpoint endpoint, String body);

  /// Cuts the playing stream short.
  Future<void> stopStream();
}
