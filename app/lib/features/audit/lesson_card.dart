import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../../l10n/l10n.dart';

/// The lesson card the Recorder made (`docs/ux-chat.md` 5.9): once the
/// reflection is sent it flips from its back (a quiet `Lesson card`) to its
/// front — the title, the body and the misconception as a small red label.
///
/// The flip takes [flipDuration]; with [animate] false (default
/// [Avatar.animationsEnabled]) the front shows at once.
class LessonCard extends StatefulWidget {
  const LessonCard({super.key, required this.principle, this.animate});

  final Principle principle;
  final bool? animate;

  static const Duration flipDuration = Duration(milliseconds: 300);

  @override
  State<LessonCard> createState() => _LessonCardState();
}

class _LessonCardState extends State<LessonCard> with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: LessonCard.flipDuration,
  );

  bool get _animate => widget.animate ?? Avatar.animationsEnabled;

  @override
  void initState() {
    super.initState();
    if (_animate) {
      _flip.forward();
    } else {
      _flip.value = 1;
    }
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: AnimatedBuilder(
        animation: _flip,
        builder: (context, _) {
          // 0 -> pi: the back turns away, the front turns toward us.
          final angle = Curves.easeInOut.transform(_flip.value) * math.pi;
          final showFront = angle >= math.pi / 2;
          final turn = showFront ? angle - math.pi : angle;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(turn),
            child: Stack(
              children: [
                // The front sizes the card; the back fills the same box.
                Visibility(
                  visible: showFront,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: _Front(principle: widget.principle),
                ),
                if (!showFront) const Positioned.fill(child: _Back()),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Front extends StatelessWidget {
  const _Front({required this.principle});

  final Principle principle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return DecoratedBox(
      key: const Key('lesson-card-front'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(color: AppColors.outline),
        boxShadow: AppShadows.input,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.primary),
                const SizedBox(width: AppSpacing.xs + 2),
                Text(context.l10n.lessonCard, style: theme.labelMedium?.copyWith(color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(principle.title, key: const Key('lesson-title'), style: theme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(principle.body, key: const Key('lesson-body'), style: theme.bodyMedium),
            if (principle.hasMisconception) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(context.l10n.misconception, style: theme.labelSmall),
              const SizedBox(height: AppSpacing.xs),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: AppRadius.chipBorder,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(Icons.close_rounded, size: 14, color: AppColors.danger),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          principle.misconception!,
                          key: const Key('lesson-misconception'),
                          style: theme.labelSmall?.copyWith(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Back extends StatelessWidget {
  const _Back();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('lesson-card-back'),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: AppRadius.cardBorder),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome_rounded, size: 28, color: AppColors.primary),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.l10n.lessonCard,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
