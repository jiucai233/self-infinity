import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/models.dart';
import '../../app/router.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../stage/stage_controller.dart';

/// One node the home stage points to: its title, a short line (what to do,
/// about how long) and where a tap goes.
@immutable
class OrbPick {
  const OrbPick({required this.skillId, required this.title, required this.meta});

  final int skillId;
  final String title;
  final String meta;
}

/// What the home stage points to (at most [max]): today's quests not done
/// yet, in order, then open nodes of the current course.
List<OrbPick> orbPicksOf(BuildContext context, StageController stage, {int max = 3}) {
  final l10n = context.l10n;
  final picks = <OrbPick>[];
  final seen = <int>{};
  for (final step in stage.plan?.steps ?? const <PlanStep>[]) {
    if (picks.length >= max) break;
    if (stage.isQuestDone(step) || !seen.add(step.skillId)) continue;
    picks.add(
      OrbPick(
        skillId: step.skillId,
        title: step.skillTitle,
        meta: [
          switch (step.kind) {
            QuestKind.learn => l10n.questLearn,
            QuestKind.challenge => l10n.questChallenge,
            QuestKind.review => l10n.questReview,
          },
          if (step.minutes > 0) l10n.questMinutes(step.minutes),
        ].join(' · '),
      ),
    );
  }
  final map = stage.courseMap;
  if (map != null) {
    for (final n in map.nodes) {
      if (picks.length >= max) break;
      if (n.status != SkillStatus.available || n.unexpanded || !seen.add(n.id)) continue;
      picks.add(OrbPick(skillId: n.id, title: n.title, meta: l10n.questLearn));
    }
  }
  return picks;
}

/// Drawn over the night panel of the home stage (2026-11-04 review: the home
/// and the life tree are one page): her line at the bottom left, and the
/// nodes to do next, each tied by a thin line to its own point in the sky —
/// the line follows the point as the sky turns. A tap on a node opens it.
///
/// The character herself is not drawn here (2026-11-25): the tree is the
/// picture on this page. On a phone the nodes are a row at the top.
class HomeSky extends StatefulWidget {
  const HomeSky({
    super.key,
    required this.sky,
    required this.box,
    required this.picks,
    required this.greeting,
  });

  final GlobalKey<LifeConstellationState> sky;
  final BoxConstraints box;
  final List<OrbPick> picks;
  final String greeting;

  /// How wide her line may be.
  static double lineWidth({required bool phone}) => phone ? 220 : 320;

  /// The room her line takes at the bottom left (the legend starts after it).
  static double lineRoom({required bool phone}) => lineWidth(phone: phone) + AppSpacing.md;

  static const double listWidth = 260;

  @override
  State<HomeSky> createState() => _HomeSkyState();
}

class _HomeSkyState extends State<HomeSky> {
  final GlobalKey _stack = GlobalKey();
  final List<GlobalKey> _rows = [];

  /// The sky's frames, once it is built.
  Listenable? _frames;

  /// Where each pick's line starts (local), by skill id.
  Map<int, Offset> _ends = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback(_attach);
  }

  void _attach(Duration _) {
    if (!mounted) return;
    final frames = widget.sky.currentState?.frames;
    if (frames != null && frames != _frames) setState(() => _frames = frames);
    _measure();
  }

  /// Where the rows are; they only move when the layout does.
  void _measure() {
    final stack = _stack.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || !stack.hasSize) return;
    final phone = _phone;
    final ends = <int, Offset>{};
    for (var i = 0; i < widget.picks.length && i < _rows.length; i++) {
      final row = _rows[i].currentContext?.findRenderObject() as RenderBox?;
      if (row == null || !row.hasSize) continue;
      final anchor = phone
          ? Offset(row.size.width / 2, row.size.height)
          : Offset(0, row.size.height / 2);
      ends[widget.picks[i].skillId] = stack.globalToLocal(row.localToGlobal(anchor));
    }
    if (!_sameEnds(ends, _ends)) setState(() => _ends = ends);
  }

  static bool _sameEnds(Map<int, Offset> a, Map<int, Offset> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  bool get _phone => MediaQuery.sizeOf(context).width < AppLayout.wideBreakpoint;

  @override
  Widget build(BuildContext context) {
    final picks = widget.picks;
    while (_rows.length < picks.length) {
      _rows.add(GlobalKey());
    }
    WidgetsBinding.instance.addPostFrameCallback(_attach);
    final phone = _phone;
    final tree = context.select<StageController, Map<int, String>>(
      (s) => {
        for (final n in s.lifeTree.nodes)
          if (n.skillId != null) n.skillId!: n.key,
      },
    );
    final links = <(String, Offset)>[
      for (final p in picks)
        if (tree[p.skillId] case final key? when _ends[p.skillId] != null) (key, _ends[p.skillId]!),
    ];
    final theme = Theme.of(context).textTheme;
    return Stack(
      key: _stack,
      children: [
        if (_frames case final frames? when links.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _LinkPainter(widget.sky, frames, links, fromBelow: phone),
              ),
            ),
          ),
        // Her line at the bottom left; the legend's button is right of it.
        Positioned(
          left: AppSpacing.lg,
          bottom: phone ? AppSpacing.xl + AppSpacing.md : AppSpacing.lg,
          child: SpeechBubble(
            key: const Key('greeting-bubble'),
            tail: BubbleTail.none,
            maxWidth: HomeSky.lineWidth(phone: phone),
            child: Text(
              keepAll(widget.greeting),
              key: const Key('greeting'),
              style: phone ? theme.bodyMedium : AppTheme.serif(theme.titleLarge)?.copyWith(height: 1.3),
            ),
          ),
        ),
        if (picks.isNotEmpty)
          if (phone)
            Positioned(
              left: AppSpacing.md,
              right: AppSpacing.md,
              top: 56,
              child: SingleChildScrollView(
                key: const Key('orb-picks'),
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < picks.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: SizedBox(
                          width: 168,
                          child: _PickRow(key: _rows[i], index: i, pick: picks[i]),
                        ),
                      ),
                  ],
                ),
              ),
            )
          else
            Positioned(
              right: AppSpacing.xl,
              top: 0,
              bottom: 0,
              width: HomeSky.listWidth,
              child: Center(
                child: Column(
                  key: const Key('orb-picks'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < picks.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.sm),
                      _PickRow(key: _rows[i], index: i, pick: picks[i]),
                    ],
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({super.key, required this.index, required this.pick});

  final int index;
  final OrbPick pick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final shape = RoundedRectangleBorder(
      borderRadius: AppRadius.chipBorder,
      side: const BorderSide(color: AppColors.outline),
    );
    return Material(
      key: Key('orb-pick-${pick.skillId}'),
      color: AppColors.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(AppRoutes.skill(pick.skillId)),
        hoverColor: AppColors.surfaceHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${index + 1}',
                  style: theme.labelLarge?.copyWith(color: AppColors.ember),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pick.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodyMedium,
                    ),
                    Text(
                      pick.meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin curves from each pick to where its node was drawn this frame.
class _LinkPainter extends CustomPainter {
  _LinkPainter(this.sky, Listenable frames, this.links, {required this.fromBelow})
    : super(repaint: frames);

  final GlobalKey<LifeConstellationState> sky;

  /// (node key, where the line leaves the pick).
  final List<(String, Offset)> links;

  /// The picks are above (a phone's row): the lines leave their bottoms.
  final bool fromBelow;

  @override
  void paint(Canvas canvas, Size size) {
    final state = sky.currentState;
    if (state == null) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..color = AppColors.ember.withValues(alpha: 0.55);
    final dot = Paint()..color = AppColors.ember.withValues(alpha: 0.8);
    for (final (key, start) in links) {
      final node = state.positionOf(key);
      if (node == null) continue;
      final path = Path()..moveTo(start.dx, start.dy);
      if (fromBelow) {
        final mid = (start.dy + node.dy) / 2;
        path.cubicTo(start.dx, mid, node.dx, mid, node.dx, node.dy);
      } else {
        final mid = (start.dx + node.dx) / 2;
        path.cubicTo(mid, start.dy, mid, node.dy, node.dx, node.dy);
      }
      canvas
        ..drawPath(path, paint)
        ..drawCircle(start, 2.5, dot)
        ..drawCircle(
          node,
          3,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = AppColors.ember,
        );
    }
  }

  @override
  bool shouldRepaint(_LinkPainter old) => true;
}
