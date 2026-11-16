import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/models.dart';
import '../../app/app_state.dart';
import '../../app/router.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import 'workout_log.dart';

/// The workouts on the Life page: the streak, workout XP and the last seven
/// days; a tap opens the workout page.
class WorkoutCard extends StatefulWidget {
  const WorkoutCard({super.key});

  @override
  State<WorkoutCard> createState() => _WorkoutCardState();
}

class _WorkoutCardState extends State<WorkoutCard> {
  WorkoutSummary? _summary;
  int? _revision;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = context.watch<AppState>().dataRevision;
    if (_revision != revision) {
      _revision = revision;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    try {
      final summary = await context.read<SelfInfinityApi>().getWorkoutSummary();
      if (mounted) setState(() => _summary = summary);
    } on Object {
      // The card stays a way into the page.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    final summary = _summary;
    return Material(
      key: const Key('workout-section'),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardBorder,
        side: const BorderSide(color: AppColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('workout-open'),
        onTap: () => context.go(AppRoutes.workout),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(l.workoutTitle, style: theme.labelLarge?.copyWith(color: AppColors.textSecondary)),
                  ),
                  if (summary != null && summary.streak > 0) ...[
                    const Icon(Icons.local_fire_department_rounded, size: 16, color: AppColors.ember),
                    const SizedBox(width: AppSpacing.xs),
                    Text(l.workoutStreak(summary.streak), style: theme.labelMedium),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  if (summary != null)
                    Text('${summary.xp} XP', style: theme.labelMedium?.copyWith(color: AppColors.xp)),
                  const SizedBox(width: AppSpacing.sm),
                  const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textTertiary),
                ],
              ),
              if (summary != null) ...[
                const SizedBox(height: AppSpacing.md),
                WorkoutWeek(days: summary.byDay, selected: formatKstDate(DateTime.now())),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
