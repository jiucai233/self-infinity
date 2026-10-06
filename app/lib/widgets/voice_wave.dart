import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'avatar.dart';

/// The waveform in the voice-mode input bar: bars filled with the Gemini
/// gradient that jump with the microphone's sound level.
///
/// [level] (0–1) is the loudness; [active] false draws a flat line (she is
/// thinking or speaking). The bars ripple only while [animate] (default
/// [Avatar.animationsEnabled]); their height always follows [level].
class VoiceWave extends StatefulWidget {
  const VoiceWave({super.key, required this.level, this.active = true, this.animate});

  final double level;
  final bool active;
  final bool? animate;

  @override
  State<VoiceWave> createState() => _VoiceWaveState();
}

class _VoiceWaveState extends State<VoiceWave> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool get _animate => widget.animate ?? Avatar.animationsEnabled;

  @override
  void initState() {
    super.initState();
    if (_animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(VoiceWave old) {
    super.didUpdateWidget(old);
    if (_animate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('voice-wave'),
      height: 52,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _WavePainter(
            level: widget.active ? widget.level : 0,
            phase: _controller.value,
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.level, required this.phase});

  final double level;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 4.0;
    const gap = 4.0;
    final count = (size.width / (barWidth + gap)).floor();
    final paint = Paint()
      ..shader = const LinearGradient(colors: AppColors.magic).createShader(Offset.zero & size);
    final loud = level.clamp(0.0, 1.0);
    final left = (size.width - (count * (barWidth + gap) - gap)) / 2;
    for (var i = 0; i < count; i++) {
      final wobble = 0.55 + 0.45 * math.sin((i / 2.5) + phase * 2 * math.pi);
      // Louder in the middle, like a spoken word's envelope.
      final envelope = 0.3 + 0.7 * math.sin(math.pi * (i + 0.5) / count);
      final height = 4 + (size.height - 4) * loud * wobble * envelope;
      final x = left + i * (barWidth + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - height) / 2, barWidth, height),
          const Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.level != level || old.phase != phase;
}
