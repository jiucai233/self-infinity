import 'package:flutter/material.dart';

import 'avatar.dart';

/// A new line arriving: it fades in and rises [rise] px into place, once,
/// over [duration] (220 ms). With "reduce motion" on (Android: remove
/// animations, iOS: Reduce Motion) or [animate] false it is simply there.
class EnterIn extends StatefulWidget {
  const EnterIn({
    super.key,
    required this.child,
    this.animate = true,
    this.duration = defaultDuration,
    this.rise = 12,
  });

  static const Duration defaultDuration = Duration(milliseconds: 220);

  final Widget child;

  /// False for lines that were already there (a resumed conversation): only
  /// what is new moves, one thing at a time.
  final bool animate;
  final Duration duration;
  final double rise;

  @override
  State<EnterIn> createState() => _EnterInState();
}

class _EnterInState extends State<EnterIn> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this, duration: widget.duration);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final still =
        !widget.animate || !Avatar.animationsEnabled || MediaQuery.disableAnimationsOf(context);
    if (still) {
      _t.value = 1;
    } else {
      _t.forward();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    child: widget.child,
    builder: (context, child) {
      final v = Curves.easeOutCubic.transform(_t.value);
      return Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, widget.rise * (1 - v)), child: child),
      );
    },
  );
}
