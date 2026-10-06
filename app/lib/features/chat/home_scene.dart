import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/life_tree.dart';
import '../../api/models.dart';
import '../../app/router.dart';
import '../../theme/tokens.dart';
import '../../upload/file_picker_service.dart';
import '../../voice/voice_mode.dart';
import '../../voice/voice_service.dart';
import '../../widgets/widgets.dart';
import '../stage/last_said.dart';
import '../stage/stage_controller.dart';
import '../stage/stage_input_bar.dart';
import '../stage/stage_scaffold.dart';
import '../stage/uploads_controller.dart';
import 'chat_controller.dart';
import 'chat_history_panel.dart';
import 'chat_navigation.dart';

/// Scene 1 (entering) and scene 5 (text / voice chat) of `docs/ux-chat.md`.
///
/// Route `/`. Until the user sends a message or starts the voice mode it is
/// scene 1: a gradient greeting, the wizard holding the crystal ball (the mini
/// skill tree opens scene 2) and two Gemini suggestion cards (typing hides
/// them). After that it is scene 5: the bubble shows only her latest line
/// (with her name above it), the user's sent line stays above the input until
/// she has answered, and the whole conversation is in the chat panel, which
/// scene 1 does not have.
class HomeScene extends StatefulWidget {
  const HomeScene({super.key});

  @override
  State<HomeScene> createState() => _HomeSceneState();
}

class _HomeSceneState extends State<HomeScene> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  late final ChatController _chat = context.read<ChatController>();
  late final UploadsController _uploads = UploadsController(
    api: context.read<SelfInfinityApi>(),
    picker: context.read<FilePickerService>(),
  );
  late final VoiceModeController _voiceMode;

  final LastSaid _lastSaid = LastSaid();
  bool _chatting = false;
  ChatMessage? _reply;
  String? _error;

  /// The reflection prompt the Guide has asked and the user has not answered
  /// yet (`docs/ux-chat.md` §6.3). It exists only here: nothing is sent until
  /// the answer is, and then it goes along as `reflection_prompt`.
  ChatMessage? _asked;

  @override
  void initState() {
    super.initState();
    _voiceMode = VoiceModeController(
      voice: context.read<VoiceService>(),
      onHeard: _onHeard,
      onUnavailable: _voiceUnavailable,
    );
    _chat.addListener(_sendQueued);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_chat.loadHistory());
      unawaited(_chat.loadSuggestions());
      _sendQueued();
    });
  }

  @override
  void dispose() {
    _chat.removeListener(_sendQueued);
    _voiceMode.dispose();
    _lastSaid.dispose();
    _uploads.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  // -- sending ---------------------------------------------------------------

  /// A line another part of the UI queued (the left panel's `Get today's
  /// quests →`): send it as if it were typed, so the answer shows here.
  void _sendQueued() {
    if (!mounted || _chat.sending) return;
    final text = _chat.takeQueued();
    if (text == null) return;
    setState(() => _asked = null);
    unawaited(_send(text));
  }

  Future<void> _send(String text, {bool fromVoice = false}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _chat.sending) return;
    final asked = _asked;
    setState(() {
      _chatting = true;
      _error = null;
      _reply = null;
    });
    _input.clear();
    _lastSaid.say(trimmed);
    final saved = await _chat.send(
      trimmed,
      uploadIds: asked == null ? _uploads.ids : const [],
      reflectionPrompt: asked?.content,
    );
    if (!mounted) return;
    if (saved == null) {
      _lastSaid.clear();
      setState(() {
        _error = _chat.error;
        _reply = asked; // still waiting for the answer: keep her question up
      });
      if (!fromVoice) _input.text = trimmed;
      return;
    }
    if (asked == null) _uploads.clear();
    _lastSaid.fade();
    final assistants = saved.where((m) => !m.isUser).toList();
    setState(() {
      _asked = null;
      _reply = assistants.isEmpty ? null : assistants.last;
    });
    followNavigation(context, assistants);
  }

  /// A reflection suggestion: the Guide asks the prompt in her bubble and the
  /// cursor goes to the input. Nothing is sent yet.
  void _askReflection(String prompt) {
    final question = ChatMessage(
      id: -1,
      role: ChatRole.assistant,
      content: prompt,
      agent: 'front_desk',
      createdAt: DateTime.now().toUtc(),
    );
    setState(() {
      _chatting = true;
      _asked = question;
      _reply = question;
      _error = null;
    });
    _focus.requestFocus();
  }

  void _onSuggestion(ChatSuggestion s) {
    final skillId = s.skillId;
    if (s.reflection) {
      _askReflection(s.label);
    } else if (skillId != null) {
      context.go(AppRoutes.skill(skillId));
    } else if (s.message.trim().isEmpty) {
      _focus.requestFocus(); // "tell me what you want to learn": just the cursor
    } else {
      unawaited(_send(s.message));
    }
  }

  Future<void> _pickUpload() async {
    final problem = await _uploads.pick();
    if (!mounted || problem == null) return;
    showToast(context, problem);
  }

  // -- voice mode ------------------------------------------------------------

  Future<VoiceReply> _onHeard(String heard) async {
    await _send(heard, fromVoice: true);
    return (speak: _reply?.content, keepGoing: true);
  }

  void _voiceUnavailable() {
    showToast(context, "Voice mode isn't available on this device.");
  }

  Future<void> _startVoice() async {
    final ok = await _voiceMode.start();
    if (!mounted || !ok) return;
    setState(() => _chatting = true);
  }

  // -- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    return StageScaffold(
      history: _chatting ? const ChatHistoryPanel() : null,
      historyTitle: 'Chat',
      stage: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => _voiceMode.stop()},
        child: Focus(
          autofocus: true,
          child: ListenableBuilder(
            listenable: Listenable.merge([_voiceMode, _uploads, _input]),
            builder: (context, _) => Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: AppLayout.chatWidth),
                          child: _chatting || _voiceMode.active
                              ? _chatStage(context, chat, box)
                              : _enterStage(context, chat, box),
                        ),
                      ),
                    ),
                  ),
                ),
                LastSaidBubble(said: _lastSaid),
                StageInputBar(
                  controller: _input,
                  focusNode: _focus,
                  hint: _asked == null ? 'Message…' : 'Your answer…',
                  enabled: !chat.sending,
                  onSubmit: () => _send(_input.text),
                  onUpload: _pickUpload,
                  uploadEnabled: !_uploads.busy,
                  voiceMode: _voiceMode,
                  onVoiceMode: _startVoice,
                  attachments: [
                    for (final f in _uploads.files)
                      InputAttachment(
                        id: f.id,
                        label: f.filename,
                        onRemove: () => _uploads.remove(f.id),
                      ),
                    if (_uploads.uploadingName != null)
                      InputAttachment(id: 'uploading', label: 'Uploading…', busy: true),
                  ],
                  error: _error,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  AvatarState _avatarState(ChatController chat) {
    if (chat.sending) return AvatarState.thinking;
    return switch (_voiceMode.state) {
      VoiceModeState.listening => AvatarState.listening,
      VoiceModeState.thinking => AvatarState.thinking,
      VoiceModeState.speaking => AvatarState.speaking,
      VoiceModeState.off => AvatarState.idle,
    };
  }

  /// The avatar is about 30 % of the stage height.
  static double _avatarSize(BoxConstraints box) => (box.maxHeight * 0.3).clamp(120.0, 300.0);

  /// Scene 1: the headline, the wizard with your life tree in her crystal
  /// ball and the suggestion cards (hidden while typing).
  Widget _enterStage(BuildContext context, ChatController chat, BoxConstraints box) {
    final map = context.select<StageController, CourseMap?>((s) => s.courseMap);
    final tree = context.select<StageController, LifeTree>((s) => s.lifeTree);
    final theme = Theme.of(context).textTheme;
    final avatar = _avatarSize(box);
    final typing = _input.text.isNotEmpty;
    final greeting = map == null
        ? 'What shall we learn today?'
        : 'Continue with “${courseNameOf(map)}”?';
    final hint = map == null
        ? 'Tell the Guide what you want to learn.'
        : 'Tap the crystal ball to open your life tree.';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          greeting,
          key: const Key('greeting'),
          textAlign: TextAlign.center,
          style: AppLayout.isWide(context) ? theme.displayMedium : theme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          hint,
          key: const Key('greeting-hint'),
          textAlign: TextAlign.center,
          style: theme.bodyLarge?.copyWith(color: AppColors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.xl),
        OrbAvatar(
          agent: 'front_desk',
          size: avatar,
          onOrbTap: () => context.go(AppRoutes.map),
          orb: KeyedSubtree(
            key: const Key('mini-tree'),
            child: LifeConstellation(
              tree: tree,
              compact: true,
              boost: OrbAvatar.hoveredOf(context),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (!typing && chat.suggestions.isNotEmpty)
          _SuggestionCards(
            key: const Key('suggestions'),
            suggestions: chat.suggestions.take(2).toList(),
            onTap: _onSuggestion,
          ),
      ],
    );
  }

  /// Scene 5: her latest line in a big bubble, nothing of the user's.
  Widget _chatStage(BuildContext context, ChatController chat, BoxConstraints box) {
    final reply = _reply;
    final agent = reply?.agent ?? 'front_desk';
    final Widget? bubble;
    if (chat.sending) {
      bubble = const ThinkingShimmer();
    } else if (reply != null) {
      bubble = _ReplyBubbleContent(message: reply);
    } else {
      bubble = null;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (bubble != null)
          SpeechBubble(
            key: const Key('reply-bubble'),
            maxWidth: 560,
            speaker: agent,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
            child: bubble,
          ),
        const SizedBox(height: AppSpacing.sm),
        GestureDetector(
          key: const Key('avatar-tap'),
          onTap: _voiceMode.interrupt,
          child: Avatar(
            agent: agent,
            mood: AvatarMood.neutral,
            state: _avatarState(chat),
            size: _avatarSize(box),
          ),
        ),
      ],
    );
  }
}

/// Her line plus the button of its action (`Open life tree →` after a course).
class _ReplyBubbleContent extends StatelessWidget {
  const _ReplyBubbleContent({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final action = message.action;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message.content, key: const Key('bubble-text'), style: theme.bodyLarge),
        if (action is CourseAction) ...[
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            key: const Key('action-map'),
            onPressed: () => context.go(AppRoutes.map),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Open life tree'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
          ),
        ],
      ],
    );
  }
}

/// The suggestions as Gemini cards (`docs/DESIGN.md` Section 3): side by side
/// on a wide stage, stacked on a narrow one.
class _SuggestionCards extends StatelessWidget {
  const _SuggestionCards({super.key, required this.suggestions, required this.onTap});

  final List<ChatSuggestion> suggestions;
  final ValueChanged<ChatSuggestion> onTap;

  static IconData _iconOf(ChatSuggestion s) {
    if (s.reflection) return Icons.psychology_alt_outlined;
    if (s.skillId != null) return Icons.auto_stories_outlined;
    if (s.message.trim().isEmpty) return Icons.lightbulb_outline_rounded;
    return Icons.wb_sunny_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final stacked = box.maxWidth < 500 || suggestions.length == 1 && box.maxWidth < 300;
        final cards = [
          for (var i = 0; i < suggestions.length; i++)
            _SuggestionCard(
              key: Key('suggestion-$i'),
              label: suggestions[i].label,
              icon: _iconOf(suggestions[i]),
              compact: stacked,
              onTap: () => onTap(suggestions[i]),
            ),
        ];
        if (stacked) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.sm),
                cards[i],
              ],
            ],
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: cards.length == 1 ? 280 : 560),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.md),
                    Expanded(child: cards[i]),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One suggestion: a `surfaceHigh` card, a small icon, the text.
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    super.key,
    required this.label,
    required this.icon,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final IconData icon;

  /// Icon and text in one row (the stacked cards of a narrow stage).
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final text = Text(
      label,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: theme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
    );
    final iconWidget = Icon(icon, size: 20, color: AppColors.primary);
    return Material(
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardBorder),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.userBubble,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: compact
              ? Row(
                  children: [
                    iconWidget,
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: text),
                  ],
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 72),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      iconWidget,
                      const SizedBox(height: AppSpacing.md),
                      text,
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
