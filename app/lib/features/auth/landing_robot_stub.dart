import 'package:flutter/widgets.dart';

/// Whether this platform has the three.js robot.
const bool hasRobot3d = false;

/// Nothing: only the web has the robot.
class Robot3d extends StatelessWidget {
  const Robot3d({
    super.key,
    required this.progress,
    required this.onOrb,
    required this.onReady,
    required this.onFailed,
  });

  final double progress;
  final void Function(Offset center, double radius) onOrb;
  final VoidCallback onReady;
  final VoidCallback onFailed;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
