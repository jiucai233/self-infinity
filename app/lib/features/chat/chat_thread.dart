import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../../l10n/l10n.dart';

/// One line of a conversation as the chat panel shows it.
@immutable
class ChatEntry {
  const ChatEntry({required this.fromUser, required this.text, required this.time, this.agent});

  /// A line of the user (right-aligned bubble) or of [agent] (left, with
  /// a portrait).
  final bool fromUser;
  final String text;
  final DateTime time;

  /// The speaking agent of an assistant line (`front_desk`, `auditor`, ...).
  final String? agent;

  factory ChatEntry.fromMessage(ChatMessage m) =>
      ChatEntry(fromUser: m.isUser, text: m.content, time: m.createdAt, agent: m.agent);
}

/// The Gemini-style conversation of the chat panel (`docs/DESIGN.md` Section 3):
/// the user's lines in right-aligned `userBubble`s (radius 20, top right 4),
/// the agents' lines on the left without a bubble, each with a 28 px portrait,
/// the agent's name and the time; a small centered date between days. The list
/// scrolls to the newest line whenever one is added.
class ChatThread extends StatefulWidget {
  const ChatThread({
    super.key,
    required this.entries,
    this.listKey,
    this.emptyText,
  });

  /// Oldest first.
  final List<ChatEntry> entries;

  /// The key of the scrolling list.
  final Key? listKey;
  /// Defaults to “No conversation yet.”
  final String? emptyText;

  /// Size of the agent portraits.
  static const double portrait = 28;

  @override
  State<ChatThread> createState() => _ChatThreadState();
}

class _ChatThreadState extends State<ChatThread> {
  final ScrollController _scroll = ScrollController();
  int _shown = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (Avatar.animationsEnabled && _shown > 1) {
        _scroll.animateTo(
          end,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scroll.jumpTo(end);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    if (entries.length != _shown) {
      _shown = entries.length;
      _toEnd();
    }
    if (entries.isEmpty) return EmptyView(message: widget.emptyText ?? context.l10n.noConversationYet);
    final theme = Theme.of(context).textTheme;
    final children = <Widget>[];
    String? day;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final d = formatLocal(e.time);
      if (d != day) {
        day = d;
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg, top: AppSpacing.xs),
            child: Center(
              child: Text(
                d,
                key: Key('chat-date-$d'),
                style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
            ),
          ),
        );
      }
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          child: e.fromUser ? _UserLine(entry: e) : _AgentLine(entry: e),
        ),
      );
    }
    return ListView(
      key: widget.listKey,
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      children: children,
    );
  }
}

class _UserLine extends StatelessWidget {
  const _UserLine({required this.entry});

  final ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: FractionallySizedBox(
        widthFactor: 0.86,
        alignment: Alignment.centerRight,
        child: Align(
          alignment: Alignment.centerRight,
          child: DecoratedBox(
            key: const Key('chat-user-bubble'),
            decoration: BoxDecoration(
              color: AppColors.userBubble,
              borderRadius: AppRadius.userBubbleBorder,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Text(entry.text, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentLine extends StatelessWidget {
  const _AgentLine({required this.entry});

  final ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final agent = entry.agent ?? 'front_desk';
    return Row(
      key: const Key('chat-agent-line'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AvatarHead(agent: agent, size: ChatThread.portrait),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      agentLabel(context.l10n, agent),
                      key: const Key('chat-agent-name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.labelLarge,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    formatLocal(entry.time, style: DateStyle.time),
                    key: const Key('chat-time'),
                    style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(entry.text, style: theme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
