import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/tokens.dart';
import '../voice/voice_service.dart';
import 'toast.dart';
import 'morph_icon.dart';
import 'voice_wave.dart';

/// A microphone for a text field (the `suffixIcon`): tap it and speak, and
/// the words are typed into [controller] after what is already there.
///
/// It stops after [pauseFor] of silence, or when tapped again. While it
/// listens it shows a small waveform and a stop icon. A device without speech
/// recognition gets a toast. Changing [controller] or disabling the button
/// ends the session.
class DictationButton extends StatefulWidget {
  const DictationButton({
    super.key,
    required this.controller,
    this.maxLength,
    this.enabled = true,
    this.pauseFor = const Duration(seconds: 3),
  });

  final TextEditingController controller;

  /// Longer dictation is cut here (the field's own `maxLength`).
  final int? maxLength;

  final bool enabled;

  /// Thinking out loud takes longer pauses than chatting, hence 3 s.
  final Duration pauseFor;

  static const String unavailableText = "Voice input isn't available on this device.";

  @override
  State<DictationButton> createState() => _DictationButtonState();
}

class _DictationButtonState extends State<DictationButton> {
  bool _listening = false;
  double _level = 0;

  /// Bumped per session (and on dispose), so a late callback of an old
  /// session never writes into the field.
  int _session = 0;

  /// Keeps the icon's morph alive across the button's key change.
  final GlobalKey _icon = GlobalKey();

  /// Kept here: a provider can't be looked up in [dispose].
  late VoiceService _voice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _voice = context.read<VoiceService>();
  }

  @override
  void didUpdateWidget(DictationButton old) {
    super.didUpdateWidget(old);
    if (_listening && (old.controller != widget.controller || !widget.enabled)) {
      _session++;
      _listening = false; // this build already shows it
      _voice.stopListening();
    }
  }

  @override
  void dispose() {
    _session++;
    if (_listening) _voice.stopListening();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_listening) {
      _stop();
      return;
    }
    final voice = _voice;
    final ok = await voice.init();
    if (!mounted) return;
    if (!ok) {
      showToast(context, DictationButton.unavailableText);
      return;
    }
    final session = ++_session;
    final controller = widget.controller;
    final base = controller.text;
    final glue = base.isEmpty || base.endsWith(' ') || base.endsWith('\n') ? '' : ' ';
    setState(() {
      _listening = true;
      _level = 0;
    });
    await voice.listen(
      pauseFor: widget.pauseFor,
      onResult: (heard, {required isFinal}) {
        if (session != _session || heard.isEmpty) return;
        _write(controller, '$base$glue$heard');
      },
      onLevel: (level) {
        if (session == _session && mounted) setState(() => _level = level);
      },
      onEnd: () {
        if (session == _session && mounted) setState(() => _listening = false);
      },
    );
  }

  void _stop() {
    _session++;
    setState(() => _listening = false);
    _voice.stopListening();
  }

  void _write(TextEditingController controller, String text) {
    final max = widget.maxLength;
    final clipped = max != null && text.length > max ? text.substring(0, max) : text;
    controller.value = TextEditingValue(
      text: clipped,
      selection: TextSelection.collapsed(offset: clipped.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    // One button: the mic morphs into a stop square while it listens.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_listening) SizedBox(width: 56, height: 22, child: VoiceWave(level: _level)),
        IconButton(
          key: Key(_listening ? 'dictation-stop' : 'dictation-button'),
          tooltip: _listening ? 'Stop listening' : 'Speak your answer',
          onPressed: _listening || widget.enabled ? _toggle : null,
          icon: MorphIcon(
            key: _icon,
            from: MorphShapes.mic,
            to: MorphShapes.stop,
            morphed: _listening,
            color: _listening ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
