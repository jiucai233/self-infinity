import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'avatar.dart';
import 'vocabulary.dart';

/// Where the small tail of a [SpeechBubble] points (toward the avatar).
enum BubbleTail { none, bottomLeft, bottomCenter, bottomRight, left, right }

/// Her speech bubble (`docs/DESIGN.md` Section 3): `surfaceHigh` fill, no
/// border, radius 20, a small tail toward the avatar. With [speaker] the
/// agent's name is written above it.
///
/// ```dart
/// SpeechBubble(tail: BubbleTail.bottomCenter, child: Text('Hello'))
/// ```
///
/// With [circle] the bubble is round (the mini skill tree of the home scene).
class SpeechBubble extends StatelessWidget {
  const SpeechBubble({
    super.key,
    required this.child,
    this.tail = BubbleTail.bottomCenter,
    this.maxWidth = 480,
    this.circle = false,
    this.onTap,
    this.speaker,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
  });

  final Widget child;
  final BubbleTail tail;
  final double maxWidth;
  final bool circle;
  final VoidCallback? onTap;

  /// The agent that talks; its display name is shown above the bubble.
  final String? speaker;
  final EdgeInsetsGeometry padding;

  static const double _tail = 10;

  @override
  Widget build(BuildContext context) {
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(AppRadius.bubble),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap != null) {
      body = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: body),
      );
    }
    final Widget laidOut;
    switch (tail) {
      case BubbleTail.none:
        laidOut = body;
      case BubbleTail.bottomLeft:
      case BubbleTail.bottomCenter:
      case BubbleTail.bottomRight:
        laidOut = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: switch (tail) {
            BubbleTail.bottomLeft => CrossAxisAlignment.start,
            BubbleTail.bottomRight => CrossAxisAlignment.end,
            _ => CrossAxisAlignment.center,
          },
          children: [
            body,
            Padding(
              padding: EdgeInsets.symmetric(horizontal: tail == BubbleTail.bottomCenter ? 0 : 28),
              child: const CustomPaint(
                size: Size(_tail * 1.6, _tail),
                painter: _TailPainter(_Dir.down),
              ),
            ),
          ],
        );
      case BubbleTail.left:
        laidOut = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const CustomPaint(
              size: Size(_tail, _tail * 1.6),
              painter: _TailPainter(_Dir.left),
            ),
            Flexible(child: body),
          ],
        );
      case BubbleTail.right:
        laidOut = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(child: body),
            const CustomPaint(
              size: Size(_tail, _tail * 1.6),
              painter: _TailPainter(_Dir.right),
            ),
          ],
        );
    }
    final name = speaker;
    if (name == null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: laidOut,
      );
    }
    final align = switch (tail) {
      BubbleTail.bottomLeft || BubbleTail.left || BubbleTail.right => CrossAxisAlignment.start,
      BubbleTail.bottomRight => CrossAxisAlignment.end,
      _ => CrossAxisAlignment.center,
    };
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: align,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              bottom: AppSpacing.xs,
              left: AppSpacing.sm,
              right: AppSpacing.sm,
            ),
            child: Text(
              agentLabel(name),
              key: const Key('speaker-name'),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          laidOut,
        ],
      ),
    );
  }
}

enum _Dir { down, left, right }

class _TailPainter extends CustomPainter {
  const _TailPainter(this.dir);

  final _Dir dir;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    switch (dir) {
      case _Dir.down:
        path
          ..moveTo(0, -1)
          ..lineTo(size.width, -1)
          ..lineTo(size.width / 2, size.height);
      case _Dir.left:
        path
          ..moveTo(size.width + 1, 0)
          ..lineTo(size.width + 1, size.height)
          ..lineTo(0, size.height / 2);
      case _Dir.right:
        path
          ..moveTo(-1, 0)
          ..lineTo(-1, size.height)
          ..lineTo(size.width, size.height / 2);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = AppColors.surfaceHigh);
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.dir != dir;
}

/// What her bubble shows while she thinks (`docs/DESIGN.md` Section 3): three
/// skeleton lines filled with a flowing Gemini gradient.
///
/// Static when [animate] (default [Avatar.animationsEnabled]) is false.
class ThinkingShimmer extends StatefulWidget {
  const ThinkingShimmer({super.key, this.animate, this.width = 260});

  final bool? animate;
  final double width;

  /// How wide each of the three lines is, as a share of [width].
  static const List<double> lineShares = [1, 0.88, 0.56];

  @override
  State<ThinkingShimmer> createState() => ThinkingShimmerState();
}

class ThinkingShimmerState extends State<ThinkingShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  bool get _animate => widget.animate ?? Avatar.animationsEnabled;

  /// Whether the gradient is flowing right now.
  bool get flowing => _controller.isAnimating;

  @override
  void initState() {
    super.initState();
    if (_animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(ThinkingShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
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

  static const double _lineHeight = 12;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('thinking-shimmer'),
      width: widget.width,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(
            colors: [
              for (final c in [...AppColors.magic, AppColors.magic.first]) c.withAlpha(0x99),
            ],
            tileMode: TileMode.repeated,
            transform: _Slide(rect.width * _controller.value),
          ).createShader(rect),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < ThinkingShimmer.lineShares.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                  child: FractionallySizedBox(
                    widthFactor: ThinkingShimmer.lineShares[i],
                    child: const SizedBox(
                      height: _lineHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.onAccent,
                          borderRadius: BorderRadius.all(Radius.circular(_lineHeight / 2)),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Slide extends GradientTransform {
  const _Slide(this.dx);

  final double dx;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}
