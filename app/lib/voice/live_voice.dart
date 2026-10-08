import '../api/api.dart';
import '../api/models.dart';
import 'live_io.dart';
import 'realtime_guide.dart';
import 'streaming_voice_service.dart';
import 'voice_mode.dart';
import 'voice_service.dart';

/// The live voice of the scenes that talk (contract #35): the home page's
/// realtime Guide and the audit's streamed turns. Typing by voice everywhere
/// else stays with the app's [VoiceService]. Both fall back to [device] where
/// live voice is not available.
class LiveVoice {
  LiveVoice({required this.api, required this.device, LiveIo? io}) : io = io ?? createLiveIo();

  final SelfInfinityApi api;
  final VoiceService device;
  final LiveIo io;

  /// The audit's voice: live transcription, streamed speech.
  late final StreamingVoiceService conversation = StreamingVoiceService(api: api, device: device, io: io);

  /// The home page's Guide; [fallback] takes turns where it cannot run.
  RealtimeGuideMode guide({
    required VoiceMode fallback,
    required void Function(List<ChatMessage> saved) onMessages,
  }) => RealtimeGuideMode(api: api, io: io, fallback: fallback, onMessages: onMessages);
}
