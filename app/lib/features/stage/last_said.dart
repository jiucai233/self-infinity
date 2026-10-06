import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// The user's last sent line on the stage (`docs/ux-chat.md` 5.4): it appears
/// above the input bar as a small right-aligned bubble when a line is sent
/// and fades out once her reply has arrived (it is in the chat panel by then).
class LastSaid extends ChangeNotifier {
  String? _text;
  bool _fading = false;

  /// The line on show, or null.
  String? get text => _text;

  /// Whether it is fading out.
  bool get fading => _fading;

  /// A line was sent.
  void say(String text) {
    _text = text;
    _fading = false;
    notifyListeners();
  }

  /// Her reply arrived: fade the line out (it is removed when the fade ends).
  void fade() {
    if (_text == null || _fading) return;
    _fading = true;
    notifyListeners();
  }

  /// Removes the line at once (the send failed).
  void clear() {
    if (_text == null) return;
    _text = null;
    _fading = false;
    notifyListeners();
  }
}

/// Shows the line of a [LastSaid] above the input bar.
class LastSaidBubble extends StatefulWidget {
  const LastSaidBubble({super.key, required this.said});

  final LastSaid said;

  /// How long the fade-out takes.
  static const Duration fadeDuration = Duration(milliseconds: 400);

  @override
  State<LastSaidBubble> createState() => _LastSaidBubbleState();
}

class _LastSaidBubbleState extends State<LastSaidBubble> with SingleTickerProviderStateMixin {
  // 1 = fully visible; the fade runs it down to 0, then the line is removed.
  late final AnimationController _opacity = AnimationController(
    vsync: this,
    duration: LastSaidBubble.fadeDuration,
    value: 1,
  );
  bool _fadeStarted = false;

  @override
  void initState() {
    super.initState();
    widget.said.addListener(_onChange);
    _onChange();
  }

  @override
  void didUpdateWidget(LastSaidBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.said != widget.said) {
      oldWidget.said.removeListener(_onChange);
      widget.said.addListener(_onChange);
      _onChange();
    }
  }

  @override
  void dispose() {
    widget.said.removeListener(_onChange);
    _opacity.dispose();
    super.dispose();
  }

  void _onChange() {
    final said = widget.said;
    if (said.text == null) {
      _fadeStarted = false;
    } else if (said.fading) {
      if (_fadeStarted) return;
      _fadeStarted = true;
      _opacity.reverse().whenComplete(() {
        if (mounted && widget.said.fading) widget.said.clear();
      });
    } else {
      _fadeStarted = false;
      _opacity.value = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.said,
      builder: (context, _) {
        final text = widget.said.text;
        if (text == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppLayout.gutter,
            AppSpacing.sm,
            AppLayout.gutter,
            0,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppLayout.chatWidth),
              child: Align(
                alignment: Alignment.centerRight,
                child: FadeTransition(
                  opacity: _opacity,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: DecoratedBox(
                      key: const Key('last-said'),
                      decoration: BoxDecoration(
                        color: AppColors.userBubble,
                        borderRadius: AppRadius.userBubbleBorder,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.sm + 2,
                        ),
                        child: Text(
                          text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
