import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';

/// A movement shown by its frames in turn (start pose, end pose), cross-faded.
/// Still (the first frame) while [Avatar.animationsEnabled] is off.
class ExerciseMotion extends StatefulWidget {
  const ExerciseMotion({super.key, required this.images, this.size, this.period = const Duration(milliseconds: 900)});

  /// Asset paths of the frames.
  final List<String> images;

  /// The width; the height follows the frames (4:3) when null bounds allow.
  final double? size;
  final Duration period;

  @override
  State<ExerciseMotion> createState() => _ExerciseMotionState();
}

class _ExerciseMotionState extends State<ExerciseMotion> {
  int _frame = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (Avatar.animationsEnabled && widget.images.length > 1) {
      _timer = Timer.periodic(widget.period, (_) {
        if (mounted) setState(() => _frame = (_frame + 1) % widget.images.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    final child = images.isEmpty
        ? const ColoredBox(
            color: AppColors.surfaceHigh,
            child: Center(child: Icon(Icons.fitness_center_rounded, color: AppColors.textTertiary)),
          )
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: Image.asset(
              images[_frame],
              key: ValueKey(_frame),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.surfaceHigh),
            ),
          );
    return ClipRRect(
      borderRadius: AppRadius.chipBorder,
      child: SizedBox(
        width: widget.size,
        child: AspectRatio(aspectRatio: 4 / 3, child: child),
      ),
    );
  }
}
