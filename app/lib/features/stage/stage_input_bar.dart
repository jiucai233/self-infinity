import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../voice/voice_mode.dart';
import '../../widgets/widgets.dart';
import '../../l10n/l10n.dart';

/// A file chip above the input (`report.pdf ✕`).
class InputAttachment {
  const InputAttachment({required this.id, required this.label, this.busy = false, this.onRemove});

  final Object id;
  final String label;

  /// Shows a spinner instead of the ✕ (the file is being uploaded).
  final bool busy;
  final VoidCallback? onRemove;
}

/// The input bar at the bottom of the stage (`docs/DESIGN.md` Section 3,
/// `docs/ux-chat.md` 1.3): a filled `surfaceHigh` pill (a blue 1 px edge while
/// focused) with `[⊕] text [→]` and, outside it on the right, the round ∿ voice
/// button.
///
/// * [onUpload] != null shows ⊕ (scenes 1 and 5).
/// * [onVoiceMode] != null shows ∿ (all but the search bar of scene 2).
/// * [search] draws a magnifier in front of the text (scene 2).
/// * [voiceMode] active replaces the whole bar with a live waveform and no
///   buttons, with a status line (`Listening…`) and the caption of what she
///   hears above it; tapping the wave (or pressing Esc) leaves voice mode.
/// * [attachments] are chips above the pill; [error] a red line above it.
///
/// Enter sends; the field grows to a few lines for long answers.
class StageInputBar extends StatefulWidget {
  const StageInputBar({
    super.key,
    required this.controller,
    required this.hint,
    required this.onSubmit,
    this.focusNode,
    this.enabled = true,
    this.search = false,
    this.onUpload,
    this.uploadEnabled = true,
    this.voiceMode,
    this.onVoiceMode,
    this.onChanged,
    this.attachments = const [],
    this.error,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onSubmit;
  final FocusNode? focusNode;

  /// Whether sending (and uploading, and voice) is open. The field itself can
  /// always be typed in.
  final bool enabled;
  final bool search;
  final VoidCallback? onUpload;
  final bool uploadEnabled;
  final VoiceModeController? voiceMode;
  final VoidCallback? onVoiceMode;
  final ValueChanged<String>? onChanged;
  final List<InputAttachment> attachments;

  /// A failure to show above the field.
  final String? error;

  static const double barHeight = 52;

  /// The status line above the waveform for a voice-mode state.
  static String statusOf(VoiceModeState state) => switch (state) {
    VoiceModeState.listening => l10nNow.voiceListening,
    VoiceModeState.thinking => l10nNow.voiceThinking,
    VoiceModeState.speaking => l10nNow.voiceSpeaking,
    VoiceModeState.off => '',
  };

  @override
  State<StageInputBar> createState() => _StageInputBarState();
}

class _StageInputBarState extends State<StageInputBar> {
  bool _focused = false;

  TextEditingController get controller => widget.controller;
  String get hint => widget.hint;
  FocusNode? get focusNode => widget.focusNode;
  bool get enabled => widget.enabled;
  bool get search => widget.search;
  VoidCallback? get onUpload => widget.onUpload;
  bool get uploadEnabled => widget.uploadEnabled;
  VoidCallback? get onVoiceMode => widget.onVoiceMode;
  ValueChanged<String>? get onChanged => widget.onChanged;
  List<InputAttachment> get attachments => widget.attachments;
  String? get error => widget.error;
  double get barHeight => StageInputBar.barHeight;

  @override
  Widget build(BuildContext context) {
    final mode = widget.voiceMode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppLayout.gutter,
        AppSpacing.sm,
        AppLayout.gutter,
        AppSpacing.lg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.chatWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null) _errorLine(context),
              if (attachments.isNotEmpty) _chips(context),
              if (mode == null)
                _fieldRow(context)
              else
                ListenableBuilder(
                  listenable: mode,
                  builder: (context, _) =>
                      mode.active ? _waveRow(context, mode) : _fieldRow(context),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorLine(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm, left: AppSpacing.sm),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.danger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              error!,
              key: const Key('input-error'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chips(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final a in attachments)
            DecoratedBox(
              key: Key('attachment-${a.id}'),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: AppRadius.chipBorder,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.description_outlined,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        a.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.labelLarge,
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (a.busy)
                      const Padding(
                        padding: EdgeInsets.all(4),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      InkResponse(
                        key: Key('attachment-remove-${a.id}'),
                        onTap: a.onRemove,
                        radius: 14,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// A filled pill; a blue edge shows the focus.
  BoxDecoration _pill({bool focused = false}) => BoxDecoration(
    color: AppColors.surfaceHigh,
    borderRadius: AppRadius.pillBorder,
    border: Border.all(color: focused ? AppColors.primary : Colors.transparent),
  );

  Widget _waveRow(BuildContext context, VoiceModeController mode) {
    final theme = Theme.of(context).textTheme;
    final listening = mode.state == VoiceModeState.listening;
    final caption = mode.heard.trim();
    final showCaption = caption.isNotEmpty && mode.state != VoiceModeState.speaking;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showCaption)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              caption,
              key: const Key('voice-caption'),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.bodyLarge?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            StageInputBar.statusOf(mode.state),
            key: const Key('voice-status'),
            textAlign: TextAlign.center,
            style: theme.labelLarge?.copyWith(color: AppColors.primary),
          ),
        ),
        Tooltip(
          message: context.l10n.voiceTapToTurnOff,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: const Key('voice-wave-row'),
              behavior: HitTestBehavior.opaque,
              onTap: () => mode.stop(),
              child: Container(
                height: barHeight,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                decoration: _pill(),
                child: Center(
                  child: VoiceWave(level: mode.level, active: listening),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fieldRow(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final showVoice = onVoiceMode != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Focus(
            canRequestFocus: false,
            onFocusChange: (focused) => setState(() => _focused = focused),
            child: Container(
              constraints: const BoxConstraints(minHeight: StageInputBar.barHeight),
              padding: EdgeInsets.only(
                left: onUpload == null ? AppSpacing.xl : AppSpacing.sm,
                right: 8,
              ),
              decoration: _pill(focused: _focused),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (onUpload != null)
                    IconButton(
                      key: const Key('upload'),
                      tooltip: context.l10n.uploadFile,
                      onPressed: enabled && uploadEnabled ? onUpload : null,
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 24),
                    ),
                  if (search)
                    const Padding(
                      padding: EdgeInsets.only(right: AppSpacing.sm),
                      child: Icon(Icons.search_rounded, size: 20, color: AppColors.textTertiary),
                    ),
                  Expanded(
                    child: TextField(
                      key: const Key('stage-input'),
                      controller: controller,
                      focusNode: focusNode,
                      // Never disabled: on the web a disabled field drops its
                      // browser input and, enabled again, keeps the focus without
                      // taking keys until it is rebuilt. While her answer is on its
                      // way the next one can be typed; only sending waits.
                      minLines: 1,
                      maxLines: 5,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.send,
                      onChanged: onChanged,
                      onSubmitted: (_) => enabled ? _submit() : focusNode?.requestFocus(),
                      onEditingComplete: () {}, // Enter keeps the cursor here
                      style: theme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: hint,
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
                  const SizedBox(width: AppSpacing.sm),
                  ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => _SendButton(
                      key: const Key('send'),
                      tooltip: search ? context.l10n.search : context.l10n.send,
                      // Disabled while her answer is on its way: the arrow turns into a spinner.
                      busy: !enabled,
                      onPressed: enabled && controller.text.trim().isNotEmpty ? _submit : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showVoice) ...[
          const SizedBox(width: AppSpacing.sm),
          _VoiceModeButton(onPressed: enabled ? onVoiceMode : null),
        ],
      ],
    );
  }

  void _submit() {
    widget.onSubmit();
    // The field keeps the cursor so that she can be answered at once.
    focusNode?.requestFocus();
  }
}

/// ∿: its bars jump to another beat while hovered.
class _VoiceModeButton extends StatefulWidget {
  const _VoiceModeButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  State<_VoiceModeButton> createState() => _VoiceModeButtonState();
}

class _VoiceModeButtonState extends State<_VoiceModeButton> {
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
        style: IconButton.styleFrom(
          backgroundColor: AppColors.surfaceHigh,
          fixedSize: const Size(40, 40),
          shape: const CircleBorder(),
        ),
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

/// The ink round send button (grey while there is nothing to send). While
/// [busy], its arrow morphs into a turning spinner.
class _SendButton extends StatelessWidget {
  const _SendButton({
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
