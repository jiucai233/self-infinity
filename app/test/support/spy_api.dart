import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';

/// A zero-latency [FakeApiClient] that records what the UI asked of it.
class SpyApi extends FakeApiClient {
  SpyApi({super.clock}) : super(latency: Duration.zero);

  /// How many `PUT /profile` calls were made.
  int profileSaves = 0;

  /// The `reflectionPrompt` of every `sendChat` call, in order (null = none).
  final List<String?> chatPrompts = [];

  /// The text of every `sendChat` call.
  final List<String> chatMessages = [];

  /// How many times the suggestions were fetched.
  int suggestionLoads = 0;

  @override
  Future<Profile> updateProfile({
    String? identity,
    String? vision,
    String? antiVision,
    List<String>? rules,
    bool? onboarded,
  }) {
    profileSaves++;
    return super.updateProfile(
      identity: identity,
      vision: vision,
      antiVision: antiVision,
      rules: rules,
      onboarded: onboarded,
    );
  }

  @override
  Future<List<ChatMessage>> sendChat(
    String message, {
    List<int> uploadIds = const [],
    String? reflectionPrompt,
    String? courseTopic,
  }) {
    chatMessages.add(message);
    chatPrompts.add(reflectionPrompt);
    return super.sendChat(
      message,
      uploadIds: uploadIds,
      reflectionPrompt: reflectionPrompt,
      courseTopic: courseTopic,
    );
  }

  @override
  Future<List<ChatSuggestion>> getChatSuggestions() {
    suggestionLoads++;
    return super.getChatSuggestions();
  }
}
