import '../api/api.dart';
import '../api/models.dart';
import 'live_audit.dart';
import 'live_guide.dart';
import 'live_io.dart';
import 'realtime_guide.dart';
import 'streaming_voice_service.dart';
import 'voice_mode.dart';
import 'voice_service.dart';

/// The live voice of the scenes that talk (contract #35): the home page's
/// Guide (GPT-Live or Realtime) and the audit (GPT-Live or streamed turns).
/// Typing by voice everywhere else stays with the app's [VoiceService]. Both
/// fall back to [device] where live voice is not available.
class LiveVoice {
  LiveVoice({required this.api, required this.device, LiveIo? io}) : io = io ?? createLiveIo();

  final SelfInfinityApi api;
  final VoiceService device;
  final LiveIo io;

  /// The audit's turns where GPT-Live cannot run: live transcription,
  /// streamed speech.
  late final StreamingVoiceService conversation = StreamingVoiceService(api: api, device: device, io: io);

  /// The audit's voice: GPT-Live, else [fallback] taking turns. [onHeard]
  /// judges one answer; [opening] is her line on the table.
  VoiceMode audit({
    required VoiceMode fallback,
    required Future<VoiceReply> Function(String heard) onHeard,
    required String? Function() opening,
  }) => LiveAuditMode(api: api, io: io, fallback: fallback, onHeard: onHeard, opening: opening);

  /// The home page's Guide: GPT-Live, else the Realtime Guide, else
  /// [fallback] taking turns.
  VoiceMode guide({
    required VoiceMode fallback,
    required void Function(List<ChatMessage> saved) onMessages,
  }) => LiveGuideMode(
    api: api,
    io: io,
    onMessages: onMessages,
    fallback: RealtimeGuideMode(api: api, io: io, fallback: fallback, onMessages: onMessages),
  );
}
