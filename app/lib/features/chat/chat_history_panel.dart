import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'chat_controller.dart';
import 'chat_thread.dart';

/// The body of the right panel “Chat” on scene 5: the whole conversation as a
/// Gemini-style [ChatThread] (`docs/ux-chat.md` 1.2, 5.3).
class ChatHistoryPanel extends StatelessWidget {
  const ChatHistoryPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final messages = context.watch<ChatController>().messages;
    return ChatThread(
      listKey: const Key('chat-history'),
      entries: [for (final m in messages) ChatEntry.fromMessage(m)],
    );
  }
}
