import 'live_link.dart';

/// Outside the browser there is no live voice.
LiveIo createLiveIo() => const _NoLiveIo();

class _NoLiveIo implements LiveIo {
  const _NoLiveIo();

  @override
  bool get supported => false;

  @override
  void unlock() {}

  @override
  Future<LiveLink> connect(
    LiveEndpoint endpoint, {
    required bool playReplies,
    void Function(double level)? onLevel,
    void Function(double level)? onReplyLevel,
  }) async => throw UnsupportedError('no live voice here');

  @override
  Future<void> playStream(LiveEndpoint endpoint, String body) async =>
      throw UnsupportedError('no live voice here');

  @override
  Future<void> stopStream() async {}
}
