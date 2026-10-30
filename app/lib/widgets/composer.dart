import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import 'dictation_button.dart';
import 'morph_icon.dart';

/// What sits in front of the text.
enum ComposerLeading {
  none,

  /// ⊕: attach a file ([Composer.onAttach]).
  attach,

  /// A magnifier: the field searches.
  search,
}

/// The one input bar of the app (`docs/DESIGN.md` Section 3): a filled
/// `surfaceHigh` pill (1 px ink edge while focused) holding `[leading] text
/// [→]`, and outside it on the right the 40 px round voice key.
///
/// * The voice key is always there: ∿ (talk with her) when [onVoiceMode] is
///   set, otherwise a microphone that types what is said into [controller].
/// * Send (the ink round key, grey while empty) shows when [onSend] is set and
///   [showSend]; Enter sends unless [multiline] (then Enter is a new line).
/// * [enabled] false closes sending, attaching and the voice key; the field
///   itself can always be typed in. [busy] turns the send arrow into a spinner.
///
/// Every screen gets the same height, radius, edge, colours and padding.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.hint,
    this.fieldKey = const Key('composer-input'),
    this.focusNode,
    this.leading = ComposerLeading.none,
    this.onAttach,
    this.attachEnabled = true,
    this.multiline = false,
    this.onSend,
    this.showSend = true,
    this.onVoiceMode,
    this.enabled = true,
    this.busy = false,
    this.maxLength,
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;

  /// The key of the [TextField] (tests and screenshots find it by this).
  final Key fieldKey;
  final FocusNode? focusNode;
  final ComposerLeading leading;
  final VoidCallback? onAttach;
  final bool attachEnabled;

  /// Grows to several lines; Enter starts a new line instead of sending.
  final bool multiline;
  final VoidCallback? onSend;

  /// False keeps Enter sending but hides the send key (the screen has its
  /// own button, like `Continue`).
  final bool showSend;

  /// ∿ voice mode; null gives the dictation microphone.
  final VoidCallback? onVoiceMode;
  final bool enabled;
  final bool busy;

  /// Typed and dictated text is cut here (no counter is shown).
  final int? maxLength;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  /// The pill's height with one line of text.
  static const double barHeight = 52;

  /// The round voice key outside the pill.
  static const double voiceKeySize = 40;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  bool _focused = false;

  /// The pill minus its 1 px edge: the band the keys are centred in.
  static const double _band = Composer.barHeight - 2;

  bool get _canSend => widget.enabled && !widget.busy;

  void _submit() {
    if (!_canSend) {
      widget.focusNode?.requestFocus();
      return;
    }
    widget.onSend!();
    // The field keeps the cursor so that she can be answered at once.
    widget.focusNode?.requestFocus();
  }

  /// Keys sit in the bottom band, so they stay level with the last line.
  Widget _inBand(Widget child) => SizedBox(height: _band, child: Center(child: child));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final w = widget;
    final attach = w.leading == ComposerLeading.attach;
    final search = w.leading == ComposerLeading.search;
    final sends = w.onSend != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Focus(
            canRequestFocus: false,
            onFocusChange: (focused) => setState(() => _focused = focused),
            child: Container(
              constraints: const BoxConstraints(minHeight: Composer.barHeight),
              padding: EdgeInsets.only(
                left: attach ? AppSpacing.sm : AppSpacing.xl,
                right: sends && w.showSend ? AppSpacing.sm : AppSpacing.xl,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: AppRadius.pillBorder,
                border: Border.all(color: _focused ? AppColors.primary : Colors.transparent),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (attach)
                    _inBand(
                      IconButton(
                        key: const Key('upload'),
                        tooltip: context.l10n.uploadFile,
                        onPressed: w.enabled && w.attachEnabled ? w.onAttach : null,
                        icon: const Icon(Icons.add_circle_outline_rounded, size: 24),
                      ),
                    ),
                  if (search)
                    _inBand(
                      const Padding(
                        padding: EdgeInsets.only(right: AppSpacing.sm),
                        child: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  Expanded(
                    child: TextField(
                      key: w.fieldKey,
                      controller: w.controller,
                      focusNode: w.focusNode,
                      autofocus: w.autofocus,
                      // Never disabled: on the web a disabled field drops its
                      // browser input and, enabled again, keeps the focus without
                      // taking keys until it is rebuilt.
                      minLines: 1,
                      maxLines: w.multiline ? 8 : 5,
                      maxLength: w.maxLength,
                      buildCounter: _noCounter,
                      keyboardType: w.multiline ? TextInputType.multiline : TextInputType.text,
                      textInputAction: w.multiline
                          ? TextInputAction.newline
                          : sends
                          ? TextInputAction.send
                          : TextInputAction.done,
                      onChanged: w.onChanged,
                      onSubmitted: w.multiline || !sends ? null : (_) => _submit(),
                      // Enter keeps the cursor here.
                      onEditingComplete: w.multiline || !sends ? null : () {},
                      style: theme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: w.hint,
                        hintStyle: theme.bodyLarge?.copyWith(color: AppColors.textTertiary),
                        hintMaxLines: 1,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                      ),
                    ),
                  ),
                  if (sends && w.showSend) ...[
                    const SizedBox(width: AppSpacing.sm),
                    _inBand(
                      ListenableBuilder(
                        listenable: w.controller,
                        builder: (context, _) => ComposerSendButton(
                          key: const Key('send'),
                          tooltip: search ? context.l10n.search : context.l10n.send,
                          busy: w.busy,
                          onPressed: _canSend && w.controller.text.trim().isNotEmpty
                              ? _submit
                              : null,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          height: Composer.barHeight,
          child: Center(
            child: w.onVoiceMode != null
                ? ComposerVoiceModeButton(onPressed: w.enabled ? w.onVoiceMode : null)
                : DictationButton(
                    controller: w.controller,
                    maxLength: w.maxLength,
                    enabled: w.enabled,
                    round: true,
                  ),
          ),
        ),
      ],
    );
  }

  static Widget? _noCounter(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    required int? maxLength,
  }) => null;
}

/// ∿, the 40 px round voice-mode key: its bars jump to another beat while
/// hovered.
class ComposerVoiceModeButton extends StatefulWidget {
  const ComposerVoiceModeButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  State<ComposerVoiceModeButton> createState() => _ComposerVoiceModeButtonState();
}

class _ComposerVoiceModeButtonState extends State<ComposerVoiceModeButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: IconButton(
        key: const Key('voice-mode'),
        tooltip: context.l10n.voiceMode,
        onPressed: widget.onPressed,
        style: composerVoiceKeyStyle(),
        icon: MorphIcon(
          from: MorphShapes.bars,
          to: MorphShapes.barsBeat,
          morphed: _hover && widget.onPressed != null,
          color: widget.onPressed == null ? AppColors.textTertiary : AppColors.textPrimary,
        ),
      ),
    );
  }
}

/// The look of the round voice key outside the pill (∿ and the microphone).
ButtonStyle composerVoiceKeyStyle() => IconButton.styleFrom(
  backgroundColor: AppColors.surfaceHigh,
  disabledBackgroundColor: AppColors.surfaceHigh,
  fixedSize: const Size.square(Composer.voiceKeySize),
  minimumSize: const Size.square(Composer.voiceKeySize),
  padding: EdgeInsets.zero,
  shape: const CircleBorder(),
);

/// The ink round send key (grey while there is nothing to send). While
/// [busy], its arrow morphs into a turning spinner.
class ComposerSendButton extends StatelessWidget {
  const ComposerSendButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null || busy;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: on ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Semantics(
            button: true,
            enabled: on,
            label: tooltip,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: on ? AppColors.primary : AppColors.outline,
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(
                dimension: 36,
                child: Center(
                  child: MorphIcon(
                    key: const Key('send-icon'),
                    from: MorphShapes.arrow,
                    to: MorphShapes.ring,
                    morphed: busy,
                    spin: true,
                    color: on ? AppColors.onAccent : AppColors.textTertiary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
