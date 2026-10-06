import 'package:flutter/foundation.dart';

import '../../api/api.dart';
import '../../api/models.dart';
import '../../app/app_state.dart';
import '../../widgets/error_view.dart';

/// The one long conversation with the front desk (endpoints 18–20), shared by
/// all scenes: the history panel, the speech bubble and the suggestions read
/// it.
class ChatController extends ChangeNotifier {
  ChatController({required this.api, required this.appState, DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc());

  final SelfInfinityApi api;
  final AppState appState;
  final DateTime Function() _clock;

  final List<ChatMessage> _messages = [];
  List<ChatSuggestion> _suggestions = const [];
  bool _historyRequested = false;
  bool _historyLoaded = false;
  bool _sending = false;
  String? _error;
  int _localId = 0;
  bool _disposed = false;

  /// Oldest first. Messages that exist only on this device (a local prompt, a
  /// message still being sent) have a negative id.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  List<ChatSuggestion> get suggestions => _suggestions;

  bool get historyLoaded => _historyLoaded;

  /// True from sending a message until the answer (or the error) arrives.
  bool get sending => _sending;

  /// Text of the last failure of [send], or null.
  String? get error => _error;

  /// The newest assistant message, or null.
  ChatMessage? get lastAssistant {
    for (final m in _messages.reversed) {
      if (!m.isUser) return m;
    }
    return null;
  }

  String? _queued;

  /// A line that another part of the UI (the left panel) wants sent to the
  /// chat. The home scene picks it up with [takeQueued] and sends it, so that
  /// the answer appears in scene 5.
  String? get queuedMessage => _queued;

  void queueMessage(String text) {
    _queued = text;
    _notify();
  }

  /// Returns the queued line and clears it.
  String? takeQueued() {
    final text = _queued;
    _queued = null;
    return text;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Loads the last 50 messages once.
  Future<void> loadHistory() async {
    if (_historyRequested) return;
    _historyRequested = true;
    try {
      final history = await api.getChatHistory(limit: 50);
      // Keep what was added while loading (a message still being sent, or one
      // saved after the history was read), without doubling what is in both.
      final known = {for (final m in history) m.id};
      final added = _messages.where((m) => m.id < 0 || !known.contains(m.id)).toList();
      _messages
        ..clear()
        ..addAll(history)
        ..addAll(added);
    } on Object {
      _historyRequested = false; // try again next time
    }
    _historyLoaded = true;
    _notify();
  }

  /// Reloads the suggestion lines.
  Future<void> loadSuggestions() async {
    try {
      _suggestions = await api.getChatSuggestions();
    } on Object {
      _suggestions = const [];
    }
    _notify();
  }

  /// Sends [text] to the front desk, with the uploaded files [uploadIds].
  /// Returns the messages the server saved (the user's, then the assistant's)
  /// or null on failure — [error] then says why and the caller should put
  /// [text] back into the input.
  ///
  /// With [reflectionPrompt] the text answers that reflection prompt: the
  /// server runs no LLM and returns three messages (the prompt, the answer, the
  /// acknowledgement); the suggestions are reloaded afterwards, since the
  /// prompt of this time window is answered now.
  Future<List<ChatMessage>?> send(
    String text, {
    List<int> uploadIds = const [],
    String? reflectionPrompt,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return null;
    final pending = ChatMessage(
      id: -(++_localId),
      role: ChatRole.user,
      content: trimmed,
      createdAt: _clock(),
    );
    _messages.add(pending);
    _sending = true;
    _error = null;
    _notify();
    try {
      final saved = await api.sendChat(
        trimmed,
        uploadIds: uploadIds,
        reflectionPrompt: reflectionPrompt,
      );
      // A history that was loading meanwhile may already hold the saved lines.
      final savedIds = {for (final m in saved) m.id};
      _messages
        ..remove(pending)
        ..removeWhere((m) => savedIds.contains(m.id))
        ..addAll(saved);
      _sending = false;
      _applySideEffects(saved);
      _notify();
      if (reflectionPrompt != null) await loadSuggestions();
      return saved;
    } on Object catch (e) {
      _messages.remove(pending);
      _sending = false;
      _error = ErrorView.messageFor(e);
      _notify();
      return null;
    }
  }

  void _applySideEffects(List<ChatMessage> saved) {
    for (final m in saved) {
      switch (m.action) {
        case CheckInAction():
          appState.markDataChanged();
        case CourseAction():
          appState.markDataChanged();
        case PlanAction():
          appState.markDataChanged(); // the daily quests in the left panel
        case _:
          break;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
