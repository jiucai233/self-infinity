import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
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
/// (`docs/ux-chat.md` 5.8): gradient sparkles burst around it, she says it
/// clicked ([CharacterSituation.gotIt]), `Cleared!` and the score, `+N XP` in
/// green, `Lv N → N+1` when the level went up, then — when the node took more
/// than one try — its score curve ([scores], the pass in gold) and the user's
/// first explanation beside this one; she reads their own [identity] back
/// ("One step closer."), and the newly opened nodes come as chips (a tap
/// opens that node). Taller than the screen, it scrolls.
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
    this.scores = const [],
    this.firstAnswer,
    this.thisAnswer,
    this.identity,
    this.identityIsQuest = false,
  });

  final int score;

  /// The node's scores, oldest first, this pass last; fewer than two hide
  /// the curve.
  final List<int> scores;

  /// The user's first answer on the first attempt and on this one; the pair
  /// is shown only when both are known and this was not the first attempt.
  final String? firstAnswer;
  final String? thisAnswer;

  /// Who the user is becoming, in their own words (or, with
  /// [identityIsQuest], the main quest this node serves); null: none.
  final String? identity;
  final bool identityIsQuest;

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

  bool get _history => scores.length >= 2;

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

  Widget _card(BuildContext context, double maxHeight) {
    final theme = Theme.of(context).textTheme;
    return DecoratedBox(
      key: const Key('celebration-card'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.panelBorder,
        border: Border.all(color: AppColors.outline),
        boxShadow: AppShadows.float,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: CelebrationCard.width, maxHeight: maxHeight),
        child: SingleChildScrollView(
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
                // She got it: her face and her line come first.
                Row(
                  key: const Key('celebration-line'),
                  children: [
                    // A still happy face: the card's own burst is the movement here.
                    const Avatar(agent: 'auditor', mood: AvatarMood.happy, size: 52, animate: false),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        keepAll(CharacterLines.of(context).say(CharacterSituation.gotIt)),
                        key: const Key('celebration-line-text'),
                        style: AppTheme.serif(theme.headlineMedium)?.copyWith(height: 1.2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
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
                if (widget._history) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ScoreCurve(key: const Key('celebration-curve'), scores: widget.scores),
                  if (_has(widget.firstAnswer) && _has(widget.thisAnswer)) ...[
                    const SizedBox(height: AppSpacing.md),
                    _Excerpt(
                      key: const Key('celebration-first'),
                      label: context.l10n.attemptFirst,
                      text: widget.firstAnswer!,
                      muted: true,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _Excerpt(
                      key: const Key('celebration-this'),
                      label: context.l10n.attemptThis,
                      text: widget.thisAnswer!,
                    ),
                  ],
                ],
                if (_has(widget.identity)) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.lg),
                  // Their own words, as a quote (the identity line of the character sheet).
                  Text(
                    keepAll('“${widget.identity!.trim()}”'),
                    key: const Key('celebration-identity'),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.serif(theme.titleLarge)?.copyWith(
                      fontStyle: FontStyle.italic,
                      height: 1.25,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    keepAll(
                      CharacterLines.of(context).say(
                        widget.identityIsQuest ? CharacterSituation.closerQuest : CharacterSituation.closer,
                      ),
                    ),
                    key: const Key('celebration-closer'),
                    textAlign: TextAlign.center,
                    style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
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
      ),
    );
  }

  static bool _has(String? s) => s != null && s.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SizedBox(
        width: math.min(CelebrationCard.width, box.maxWidth - 2 * AppSpacing.lg),
        child: _animated(
          _card(
            context,
            box.maxHeight.isFinite ? box.maxHeight - 2 * AppSpacing.lg : double.infinity,
          ),
        ),
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

/// The node's scores as a small line, first attempt to this one: the
/// failed ones muted, the pass a gold dot; the first and this score at the
/// ends, the count of attempts above.
class _ScoreCurve extends StatelessWidget {
  const _ScoreCurve({super.key, required this.scores});

  final List<int> scores;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.attemptNth(scores.length),
          key: const Key('celebration-attempts'),
          textAlign: TextAlign.center,
          style: theme.labelMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Text('${scores.first}', style: theme.labelMedium?.copyWith(color: AppColors.textTertiary)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: SizedBox(
                height: 36,
                child: CustomPaint(painter: _CurvePainter(scores)),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text('${scores.last}', style: theme.labelLarge?.copyWith(color: AppColors.success)),
          ],
        ),
      ],
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.scores);

  final List<int> scores;

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.length < 2) return;
    const pad = 5.0;
    final lo = scores.reduce(math.min).toDouble();
    final hi = scores.reduce(math.max).toDouble();
    final span = math.max(10.0, hi - lo);
    Offset at(int i) => Offset(
      pad + (size.width - 2 * pad) * i / (scores.length - 1),
      size.height - pad - (size.height - 2 * pad) * (scores[i] - lo) / span,
    );
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < scores.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.outlineStrong
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
    final muted = Paint()..color = AppColors.locked;
    for (var i = 0; i < scores.length - 1; i++) {
      canvas.drawCircle(at(i), 2.5, muted);
    }
    final pass = at(scores.length - 1);
    canvas.drawCircle(pass, 7, Paint()..color = AppColors.emberHot);
    canvas.drawCircle(pass, 4.5, Paint()..color = AppColors.ember);
  }

  @override
  bool shouldRepaint(_CurvePainter old) => !listEquals(old.scores, scores);
}

/// "First" / "This time" and a few lines of what the user said then.
class _Excerpt extends StatelessWidget {
  const _Excerpt({super.key, required this.label, required this.text, this.muted = false});

  final String label;
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(label, style: theme.labelSmall?.copyWith(color: AppColors.textTertiary)),
          ),
        ),
        Expanded(
          child: Text(
            keepAll(text.trim()),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.bodySmall?.copyWith(
              color: muted ? AppColors.textTertiary : AppColors.textPrimary,
              height: 1.4,
            ),
          ),
        ),
      ],
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
