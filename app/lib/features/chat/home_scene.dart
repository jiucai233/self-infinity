import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/life_tree.dart';
import '../../api/models.dart';
import '../../app/router.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../upload/file_picker_service.dart';
import '../../voice/live_voice.dart';
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
import '../../l10n/l10n.dart';

/// Scene 1 (entering) and scene 5 (text / voice chat) of `docs/ux-chat.md`.
///
/// Route `/`. Until the user sends a message or starts the voice mode it is
/// scene 1: a gradient greeting, the wizard holding the crystal ball (the mini
/// skill tree opens scene 2) and two Gemini suggestion cards (typing hides
/// them). After that it is scene 5: the bubble shows only her latest line
/// (with her name above it), the user's sent line stays above the input until
/// she has answered, and the whole conversation is in the chat panel, which
/// scene 1 does not have.
///
/// On a phone (below [AppLayout.wideBreakpoint]) it is only a talk with her:
/// scene 1 is her figure with the ball, the greeting as her speech bubble and
/// the suggestions as quick-reply chips under it; scene 5 is the thread of
/// this visit, her small figure pinned on top.
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
  late final VoiceMode _voiceMode;

  final LastSaid _lastSaid = LastSaid();
  final ScrollController _thread = ScrollController();
  bool _chatting = false;

  /// The messages there were when the chat began: the phone's thread shows
  /// only what came after (the rest is in the history drawer).
  Set<int> _earlier = const {};
  ChatMessage? _reply;

  /// Everything she said in answer to the last message (a reply and, say, the
  /// check-in receipt): what voice mode reads aloud.
  String? _spokenReply;
  String? _error;

  /// The reflection prompt the Guide has asked and the user has not answered
  /// yet (`docs/ux-chat.md` §6.3). It exists only here: nothing is sent until
  /// the answer is, and then it goes along as `reflection_prompt`.
  ChatMessage? _asked;

  @override
  void initState() {
    super.initState();
    final turns = VoiceModeController(
      voice: context.read<VoiceService>(),
      onHeard: _onHeard,
      onUnavailable: _voiceUnavailable,
    );
    // The Guide talks as one realtime model where it can; turns over the app's voice elsewhere.
    _voiceMode = context.read<LiveVoice?>()?.guide(fallback: turns, onMessages: _onGuideSaved) ?? turns;
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
    _thread.dispose();
    _uploads.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// The chat begins (scene 1 turns into scene 5): what was said before
  /// stays out of the phone's thread.
  void _beginChat() {
    if (_chatting) return;
    _earlier = {for (final m in _chat.messages) m.id};
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
    _beginChat();
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
    _spokenReply = assistants.isEmpty ? null : assistants.map((m) => m.content.trim()).join(' ');
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
    _beginChat();
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
    _spokenReply = null;
    await _send(heard, fromVoice: true);
    return (speak: _spokenReply, keepGoing: true);
  }

  /// What the realtime Guide did or said, saved by the server: into the chat,
  /// and her last line into the bubble; a navigation is followed.
  void _onGuideSaved(List<ChatMessage> saved) {
    if (!mounted) return;
    _beginChat();
    _chat.addSaved(saved);
    final assistants = saved.where((m) => !m.isUser).toList();
    if (assistants.isEmpty) return;
    setState(() {
      _chatting = true;
      _reply = assistants.last;
    });
    followNavigation(context, assistants);
  }

  void _voiceUnavailable() {
    showToast(context, context.l10n.voiceModeUnavailable);
  }

  Future<void> _startVoice() async {
    final ok = await _voiceMode.start();
    if (!mounted || !ok) return;
    _beginChat();
    setState(() => _chatting = true);
  }

  // -- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final phone = !AppLayout.isWide(context);
    return StageScaffold(
      history: const ChatHistoryPanel(),
      showHistoryPanel: _chatting,
      stage: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_voiceMode.active) {
              _voiceMode.stop();
            } else {
              _endChat();
            }
          },
        },
        child: Focus(
          autofocus: true,
          child: ListenableBuilder(
            listenable: Listenable.merge([_voiceMode, _uploads, _input]),
            builder: (context, _) => Column(
              children: [
                if (_chatting) _chatBar(context, phone),
                Expanded(
                  child: phone && (_chatting || _voiceMode.active)
                      ? _phoneThread(context, chat)
                      : LayoutBuilder(
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
                // A phone's thread shows the sent line itself.
                if (!phone || !_chatting) LastSaidBubble(said: _lastSaid),
                StageInputBar(
                  controller: _input,
                  focusNode: _focus,
                  hint: _asked == null ? context.l10n.messageHint : context.l10n.answerHint,
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
                      InputAttachment(id: 'uploading', label: context.l10n.uploading, busy: true),
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

  /// Back to her with the crystal ball (the conversation stays in the
  /// history drawer).
  void _endChat() {
    if (!_chatting) return;
    _voiceMode.stop();
    setState(() {
      _chatting = false;
      _reply = null;
    });
  }

  /// Over the conversation: the way back to her, and on a wide screen (no
  /// bottom tabs) the way to the life tree.
  Widget _chatBar(BuildContext context, bool phone) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, 0),
      child: Row(
        children: [
          IconButton(
            key: const Key('end-chat'),
            tooltip: context.l10n.back,
            onPressed: _endChat,
            icon: const Icon(Icons.arrow_back_rounded, size: 20, color: AppColors.textSecondary),
          ),
          const Spacer(),
          if (!phone)
            TextButton.icon(
              key: const Key('chat-open-map'),
              onPressed: () => context.go(AppRoutes.map),
              style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
              icon: const Icon(Icons.blur_on_rounded, size: 18),
              label: Text(context.l10n.lifeTree),
            ),
        ],
      ),
    );
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
        ? context.l10n.greetingNew
        : context.l10n.greetingContinue(courseNameOf(map));
    final hint = map == null
        ? context.l10n.hintNew
        : context.l10n.hintContinue;
    if (!AppLayout.isWide(context)) {
      // A phone: she, her line, the quick replies. The ball's glow invites the
      // tap; the hint is only its tooltip.
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OrbAvatar(
            agent: 'front_desk',
            size: (box.maxHeight * 0.36).clamp(140.0, 260.0),
            hint: hint,
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
          const SizedBox(height: AppSpacing.sm),
          SpeechBubble(
            key: const Key('greeting-bubble'),
            tail: BubbleTail.top,
            maxWidth: 340,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
            child: Text(
              keepAll(greeting),
              key: const Key('greeting'),
              textAlign: TextAlign.center,
              style: AppTheme.serif(theme.headlineSmall)?.copyWith(height: 1.3),
            ),
          ),
          if (!typing && chat.suggestions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _QuickReplies(
              key: const Key('suggestions'),
              suggestions: chat.suggestions.take(3).toList(),
              onTap: _onSuggestion,
            ),
          ],
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          keepAll(greeting),
          key: const Key('greeting'),
          textAlign: TextAlign.center,
          style: AppLayout.isWide(context) ? theme.displayMedium : theme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          keepAll(hint),
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

  /// How many lines the phone's thread showed when it last scrolled down.
  int _threadShown = 0;

  /// Scene 5 on a phone: her small figure pinned on top (tap: interrupt her),
  /// then this visit's conversation as bubbles. Her latest line (or her
  /// thinking) is the `reply-bubble`, with its action.
  Widget _phoneThread(BuildContext context, ChatController chat) {
    final theme = Theme.of(context).textTheme;
    final reply = chat.sending ? null : _reply;
    final lines = chat.messages.where((m) => !_earlier.contains(m.id)).toList();
    var replyShown = false;
    final items = <Widget>[];
    for (final m in lines) {
      final Widget line;
      if (m.isUser) {
        line = ThreadBubble(
          fromUser: true,
          child: Text(keepAll(m.content), style: theme.bodyLarge),
        );
      } else if (reply != null && m.id == reply.id) {
        replyShown = true;
        line = _HerLine(key: const Key('reply-bubble'), message: m, current: true);
      } else {
        line = _HerLine(message: m);
      }
      items.add(Padding(padding: const EdgeInsets.only(bottom: AppSpacing.md), child: line));
    }
    if (chat.sending) {
      items.add(
        const ThreadBubble(
          key: Key('reply-bubble'),
          child: ThinkingShimmer(width: 200),
        ),
      );
    } else if (reply != null && !replyShown) {
      // A reflection prompt she asks here: not sent, so not in the chat yet.
      items.add(_HerLine(key: const Key('reply-bubble'), message: reply, current: true));
    }
    if (items.length != _threadShown) {
      _threadShown = items.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_thread.hasClients) return;
        _thread.jumpTo(_thread.position.maxScrollExtent);
      });
    }
    return Column(
      children: [
        GestureDetector(
          key: const Key('avatar-tap'),
          onTap: _voiceMode.interrupt,
          child: Avatar(
            agent: _reply?.agent ?? 'front_desk',
            mood: AvatarMood.neutral,
            state: _avatarState(chat),
            size: 96,
          ),
        ),
        Expanded(
          child: ListView(
            key: const Key('phone-thread'),
            controller: _thread,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            children: items,
          ),
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

/// The suggestions on a phone: small quick-reply chips under her bubble,
/// with the keys of the cards.
class _QuickReplies extends StatelessWidget {
  const _QuickReplies({super.key, required this.suggestions, required this.onTap});

  final List<ChatSuggestion> suggestions;
  final ValueChanged<ChatSuggestion> onTap;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    // Two lines round off less than a pill would.
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.bubble),
      side: const BorderSide(color: AppColors.outlineStrong),
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (var i = 0; i < suggestions.length; i++)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Material(
              key: Key('suggestion-$i'),
              type: MaterialType.transparency,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: shape,
                onTap: () => onTap(suggestions[i]),
                hoverColor: AppColors.surfaceHigh,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  child: Text(
                    keepAll(suggestions[i].label),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: style,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One of her lines in the phone's thread, in the serif; another agent's
/// name stands small above it. The [current] one has the `bubble-text` key
/// and its action.
class _HerLine extends StatelessWidget {
  const _HerLine({super.key, required this.message, this.current = false});

  final ChatMessage message;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final agent = message.agent ?? 'front_desk';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (agent != 'front_desk')
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.sm, bottom: AppSpacing.xs),
            child: Text(
              agentLabel(context.l10n, agent),
              key: const Key('speaker-name'),
              style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
        ThreadBubble(
          child: current
              ? _ReplyBubbleContent(message: message, serif: true)
              : Text(keepAll(message.content), style: AppTheme.serif(theme.titleLarge)),
        ),
      ],
    );
  }
}

/// Her line plus the button of its action (`Open life tree →` after a course).
class _ReplyBubbleContent extends StatelessWidget {
  const _ReplyBubbleContent({required this.message, this.serif = false});

  final ChatMessage message;

  /// Her line in the serif (the phone's thread).
  final bool serif;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final action = message.action;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          keepAll(message.content),
          key: const Key('bubble-text'),
          style: serif ? AppTheme.serif(theme.titleLarge) : theme.bodyLarge,
        ),
        if (action is CourseAction) ...[
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            key: const Key('action-map'),
            onPressed: () => context.go(AppRoutes.map),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(context.l10n.openLifeTree),
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
      keepAll(label),
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
