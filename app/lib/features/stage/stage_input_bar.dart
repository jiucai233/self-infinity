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
/// `docs/ux-chat.md` 1.3): the app's one [Composer] (`[⊕] text [→]` in a
/// `surfaceHigh` pill, the round voice key outside it), with what only the
/// stage has around it.
///
/// * [onUpload] != null shows ⊕ (scenes 1 and 5).
/// * [onVoiceMode] != null makes the voice key ∿; otherwise it is the
///   dictation microphone.
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
  final VoiceMode? voiceMode;
  final VoidCallback? onVoiceMode;

  final ValueChanged<String>? onChanged;
  final List<InputAttachment> attachments;

  /// A failure to show above the field.
  final String? error;

  static const double barHeight = Composer.barHeight;

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

  /// The waveform's pill: the composer's, without the voice key beside it.
  BoxDecoration _pill() => BoxDecoration(
    color: AppColors.surfaceHigh,
    borderRadius: AppRadius.pillBorder,
    border: Border.all(color: Colors.transparent),
  );

  Widget _waveRow(BuildContext context, VoiceMode mode) {
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
    return Composer(
      controller: controller,
      focusNode: focusNode,
      fieldKey: const Key('stage-input'),
      hint: hint,
      leading: onUpload != null
          ? ComposerLeading.attach
          : search
          ? ComposerLeading.search
          : ComposerLeading.none,
      onAttach: onUpload,
      attachEnabled: uploadEnabled,
      onSend: widget.onSubmit,
      onVoiceMode: onVoiceMode,
      // While her answer is on its way the next one can be typed; only
      // sending waits (the arrow turns into a spinner).
      enabled: enabled,
      busy: !enabled,
      onChanged: onChanged,
    );
  }
}
