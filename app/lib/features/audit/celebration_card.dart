import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../../l10n/l10n.dart';

/// A node that a pass opened: shown as a blue chip on the [CelebrationCard].
@immutable
class UnlockedNode {
  const UnlockedNode({required this.id, required this.title});

  final int id;
  final String title;
}

/// The card that floats up in the middle of the stage when an audit passes
/// (`docs/ux-chat.md` 5.8): gradient sparkles burst around it, `Cleared!` and the
/// score, `+N XP` in green, `Lv N → N+1` when the level went up and the newly
/// opened nodes as blue chips (a tap opens that node).
///
/// The burst and the pop-in run once, unless [animate] is false (default
/// [Avatar.animationsEnabled]): then the sparkles are drawn mid-burst, still.
class CelebrationCard extends StatefulWidget {
  const CelebrationCard({
    super.key,
    required this.score,
    required this.onClose,
    required this.onContinue,
    required this.onOpenSkill,
    this.xp,
    this.levelBefore,
    this.levelAfter,
    this.unlocked = const [],
    this.boss = false,
    this.animate,
  });

  final int score;

  /// XP earned, or null when the server did not say.
  final int? xp;

  /// The level before and after the pass; both set and different = level up.
  final int? levelBefore;
  final int? levelAfter;
  final List<UnlockedNode> unlocked;

  /// A root or branch node was cleared: the title reads `Boss cleared!`.
  final bool boss;

  /// Dismiss: stay on the audit result.
  final VoidCallback onClose;

  /// Go back to the node (scene 4).
  final VoidCallback onContinue;

  /// A chip was tapped: open that node (scene 4).
  final ValueChanged<int> onOpenSkill;
  final bool? animate;

  static const double width = 340;

  bool get leveledUp => levelBefore != null && levelAfter != null && levelAfter! > levelBefore!;

  @override
  State<CelebrationCard> createState() => _CelebrationCardState();
}

class _CelebrationCardState extends State<CelebrationCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  bool get _animate => widget.animate ?? Avatar.animationsEnabled;

  @override
  void initState() {
    super.initState();
    if (_animate) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final card = DecoratedBox(
      key: const Key('celebration-card'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.panelBorder,
        border: Border.all(color: AppColors.outline),
        boxShadow: AppShadows.float,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: CelebrationCard.width),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GradientText(
                widget.boss ? context.l10n.bossCleared : context.l10n.cleared,
                key: const Key('celebration-title'),
                style: theme.displaySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.l10n.points(widget.score),
                key: const Key('celebration-score'),
                textAlign: TextAlign.center,
                style: theme.headlineMedium,
              ),
              if (widget.xp != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '+${widget.xp} XP',
                  key: const Key('celebration-xp'),
                  textAlign: TextAlign.center,
                  style: theme.titleMedium?.copyWith(color: AppColors.success),
                ),
              ],
              if (widget.leveledUp) ...[
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: StatusChip.primary(
                    'Lv ${widget.levelBefore} → ${widget.levelAfter}',
                    key: const Key('celebration-level'),
                  ),
                ),
              ],
              if (widget.unlocked.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                Text(
                  context.l10n.newNodesUnlocked,
                  textAlign: TextAlign.center,
                  style: theme.labelMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final n in widget.unlocked)
                      _UnlockedChip(
                        key: Key('unlocked-${n.id}'),
                        title: n.title,
                        onTap: () => widget.onOpenSkill(n.id),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: AppSpacing.sm,
                children: [
                  TextButton(
                    key: const Key('celebration-close'),
                    onPressed: widget.onClose,
                    child: Text(context.l10n.close),
                  ),
                  FilledButton(
                    key: const Key('celebration-continue'),
                    onPressed: widget.onContinue,
                    child: Text(context.l10n.backToNode),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) => SizedBox(
        width: math.min(CelebrationCard.width, box.maxWidth - 2 * AppSpacing.lg),
        child: _animated(card),
      ),
    );
  }

  Widget _animated(Widget card) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _animate ? _controller.value : 1.0;
        final pop = Curves.easeOutBack.transform(math.min(1.0, t / 0.3));
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // The burst fills a box a good deal bigger than the card.
            Positioned.fill(
              top: -90,
              bottom: -90,
              left: -90,
              right: -90,
              child: IgnorePointer(
                child: CustomPaint(
                  key: const Key('celebration-sparkles'),
                  painter: _BurstPainter(progress: _animate ? t : 0.5),
                ),
              ),
            ),
            Opacity(
              opacity: math.min(1.0, t / 0.2),
              child: Transform.scale(scale: 0.88 + 0.12 * pop, child: card),
            ),
          ],
        );
      },
    );
  }
}

class _UnlockedChip extends StatelessWidget {
  const _UnlockedChip({super.key, required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primarySoft,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.chipBorder),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_open_rounded, size: 14, color: AppColors.primary),
              const SizedBox(width: AppSpacing.xs + 2),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.primary,
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

/// Four-point stars flying outward from the card, in the Gemini colors; they
/// fade out over the last third of the burst.
class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.progress});

  /// 0–1.
  final double progress;

  static const int _count = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final eased = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final fade = progress < 0.6 ? 1.0 : (1 - (progress - 0.6) / 0.4).clamp(0.0, 1.0);
    if (fade <= 0) return;
    final rng = math.Random(7);
    for (var i = 0; i < _count; i++) {
      final angle = 2 * math.pi * i / _count + rng.nextDouble() * 0.3;
      // The box is the card plus a margin: stars end near its rim and corners.
      final reach = 0.72 + 0.28 * rng.nextDouble();
      final dx = math.cos(angle) * size.width * 0.5 * reach;
      final dy = math.sin(angle) * size.height * 0.5 * reach;
      final at = center + Offset(dx, dy) * (0.5 + 0.5 * eased);
      final radius = 6 + 8 * rng.nextDouble();
      final color = AppColors.magic[i % AppColors.magic.length];
      canvas.drawPath(
        _star(at, radius * (0.6 + 0.4 * eased)),
        Paint()..color = color.withValues(alpha: 0.85 * fade),
      );
    }
  }

  static Path _star(Offset c, double r) => Path()
    ..moveTo(c.dx, c.dy - r)
    ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
    ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
    ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
    ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
    ..close();

  @override
  bool shouldRepaint(_BurstPainter old) => old.progress != progress;
}
