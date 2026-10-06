import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/tokens.dart';
import '../../l10n/l10n.dart';

/// How an [InlineEditField] is drawn.
enum InlineEditVariant {
  /// A filled card with a small label on top (`Win condition`, `Stakes`).
  card,

  /// Plain text on the panel (the identity line, a rule).
  line,
}

/// Text that turns into a field when tapped (the left panel's character
/// sheet).
///
/// * Shows [value], or the muted [placeholder] when it is empty.
/// * Tap → a [TextField] (limited to [maxLength]). Enter or leaving the field
///   saves, Esc cancels. A text that did not change is not saved.
/// * [onSave] returns `null` when the change was accepted, else the message to
///   show under the field; the field then stays open with what was typed.
/// * A small spinner shows while saving and a check mark for two seconds after.
/// * [prefill] is put into an empty field when editing starts (the stem of the
///   identity sentence); leaving it untouched counts as empty.
/// * [startEditing] opens the field at once (a new rule); [onClosed] tells the
///   parent when an open field closed without a change.
class InlineEditField extends StatefulWidget {
  const InlineEditField({
    super.key,
    required this.value,
    required this.placeholder,
    required this.onSave,
    required this.maxLength,
    this.label,
    this.variant = InlineEditVariant.line,
    this.maxLines = 4,
    this.displayLines,
    this.prefill = '',
    this.startEditing = false,
    this.onClosed,
    this.inputKey,
    this.errorKey,
    this.textStyle,
  });

  final String value;
  final String placeholder;
  final Future<String?> Function(String text) onSave;
  final int maxLength;

  /// The small label of a [InlineEditVariant.card].
  final String? label;
  final InlineEditVariant variant;

  /// Lines the field grows to while editing.
  final int maxLines;

  /// Lines of the shown text before it is cut with `…` ([maxLines] when null);
  /// the panel stays calm, the full text is one tap away.
  final int? displayLines;
  final String prefill;
  final bool startEditing;
  final VoidCallback? onClosed;
  final Key? inputKey;
  final Key? errorKey;
  final TextStyle? textStyle;

  @override
  State<InlineEditField> createState() => _InlineEditFieldState();
}

class _InlineEditFieldState extends State<InlineEditField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _editing = false;
  bool _saving = false;
  bool _saved = false;
  String? _error;
  Timer? _savedTimer;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    if (widget.startEditing) _open();
  }

  @override
  void dispose() {
    _savedTimer?.cancel();
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    _editing = true;
    _error = null;
    _saved = false;
    _controller.text = widget.value.isEmpty ? widget.prefill : widget.value;
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _focus.requestFocus();
    });
  }

  void _onFocus() {
    if (!_focus.hasFocus && _editing && !_saving) unawaited(_commit(fromBlur: true));
  }

  void _cancel() {
    setState(() {
      _editing = false;
      _error = null;
    });
    widget.onClosed?.call();
  }

  Future<void> _commit({bool fromBlur = false}) async {
    if (_saving || !_editing) return;
    var text = _controller.text.trim();
    if (widget.prefill.isNotEmpty && text == widget.prefill.trim()) text = '';
    if (text == widget.value) {
      _cancel();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave(text);
    if (!mounted) return;
    if (error == null) {
      setState(() {
        _saving = false;
        _editing = false;
        _saved = true;
      });
      _savedTimer?.cancel();
      _savedTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _saved = false);
      });
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
      // Enter closed the keyboard before the answer came; put the cursor back so
      // that Enter retries. After leaving the field the user is elsewhere.
      if (!fromBlur) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _editing) _focus.requestFocus();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.variant == InlineEditVariant.card) _labelRow(theme),
        _editing ? _editor(theme) : _display(theme),
        if (_error != null) _errorLine(theme),
      ],
    );
    if (widget.variant == InlineEditVariant.line) return body;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(color: _editing ? AppColors.primary : Colors.transparent),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: body,
      ),
    );
  }

  Widget _labelRow(TextTheme theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.label ?? '',
              style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
          if (_saving)
            const SizedBox(
              key: Key('saving-mark'),
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (_saved)
            const Icon(
              Icons.check_rounded,
              key: Key('saved-mark'),
              size: 14,
              color: AppColors.success,
            ),
        ],
      ),
    );
  }

  TextStyle _style(TextTheme theme) =>
      widget.textStyle ?? theme.bodyMedium!.copyWith(color: AppColors.textPrimary);

  Widget _display(TextTheme theme) {
    final empty = widget.value.isEmpty;
    final style = _style(theme);
    return Semantics(
      button: true,
      label: widget.label ?? widget.placeholder,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(_open),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: widget.variant == InlineEditVariant.line ? 4 : 2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    empty ? widget.placeholder : widget.value,
                    maxLines: widget.displayLines ?? widget.maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: empty ? style.copyWith(color: AppColors.textTertiary) : style,
                  ),
                ),
                if (widget.variant == InlineEditVariant.line && _saved)
                  const Padding(
                    padding: EdgeInsets.only(left: AppSpacing.xs, top: 3),
                    child: Icon(
                      Icons.check_rounded,
                      key: Key('saved-mark'),
                      size: 14,
                      color: AppColors.success,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _editor(TextTheme theme) {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        key: widget.inputKey,
        controller: _controller,
        focusNode: _focus,
        minLines: 1,
        maxLines: widget.maxLines,
        maxLength: widget.maxLength,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.done,
        style: _style(theme),
        onSubmitted: (_) => unawaited(_commit()),
        buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
          final limit = maxLength ?? widget.maxLength;
          if (currentLength < limit * 0.8) return null;
          return Text(
            '$currentLength/$limit',
            style: theme.labelSmall?.copyWith(
              color: currentLength >= limit ? AppColors.danger : AppColors.textTertiary,
            ),
          );
        },
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          hintText: widget.placeholder,
          hintStyle: _style(theme).copyWith(color: AppColors.textTertiary),
        ),
      ),
    );
  }

  Widget _errorLine(TextTheme theme) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.error_outline_rounded, size: 14, color: AppColors.danger),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              context.l10n.saveFailed('$_error'),
              key: widget.errorKey ?? const Key('field-error'),
              style: theme.bodySmall?.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
