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
import '../../widgets/widgets.dart';
import '../stage/stage_scaffold.dart';
import 'exercise_library.dart';
import 'exercise_motion.dart';
import 'workout_charts.dart';
import 'workout_log.dart';

String bodyLabel(AppLocalizations l, BodyPart b) => switch (b) {
  BodyPart.chest => l.bodyChest,
  BodyPart.back => l.bodyBack,
  BodyPart.shoulders => l.bodyShoulders,
  BodyPart.arms => l.bodyArms,
  BodyPart.legs => l.bodyLegs,
  BodyPart.core => l.bodyCore,
  BodyPart.cardio => l.bodyCardio,
  BodyPart.stretch => l.bodyStretch,
};

String equipmentLabel(AppLocalizations l, Equipment e) => switch (e) {
  Equipment.body => l.equipBody,
  Equipment.dumbbell => l.equipDumbbell,
  Equipment.barbell => l.equipBarbell,
  Equipment.machine => l.equipMachine,
  Equipment.cable => l.equipCable,
  Equipment.kettlebell => l.equipKettlebell,
  Equipment.band => l.equipBand,
  Equipment.other => l.equipOther,
};

/// The workout page (route `/life/workout`, opened from the Life page): the
/// log, the exercise library by body part, and progress per exercise.
class WorkoutScene extends StatefulWidget {
  const WorkoutScene({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<WorkoutScene> createState() => _WorkoutSceneState();
}

class _WorkoutSceneState extends State<WorkoutScene> {
  late final SelfInfinityApi _api = context.read<SelfInfinityApi>();
  final GlobalKey<WorkoutLogState> _log = GlobalKey();
  late int _tab = widget.initialTab;
  ExerciseLibrary? _library;
  WorkoutCatalog? _catalog;

  /// Bumped when a workout changes, so the progress tab reads again.
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadChoices());
  }

  Future<void> _loadChoices() async {
    final library = await ExerciseLibrary.load();
    WorkoutCatalog? catalog;
    try {
      catalog = await _api.getWorkoutCatalog();
    } on Object {
      // The library alone still lets the user log.
    }
    if (!mounted) return;
    setState(() {
      _library = library;
      _catalog = catalog;
    });
  }

  ExerciseChoices get _choices =>
      ExerciseChoices(_catalog, _library, Localizations.localeOf(context).languageCode);

  void _changed() {
    setState(() => _revision++);
    context.read<AppState>().markDataChanged();
  }

  Future<void> _logExercise(LibraryExercise e) async {
    final language = Localizations.localeOf(context).languageCode;
    final saved = await showWorkoutDialog(
      context,
      api: _api,
      choices: _choices,
      date: formatKstDate(DateTime.now()),
      prefill: ExerciseOption(
        name: e.name(language),
        category: e.category,
        unit: e.unit,
        key: e.catalog,
        library: e,
      ),
    );
    if (!saved || !mounted) return;
    _changed();
    await _log.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final library = _library;
    return StageScaffold(
      title: l.workoutTitle,
      topLeading: IconButton(
        key: const Key('workout-back'),
        tooltip: l.back,
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => context.go(AppRoutes.life),
      ),
      stage: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: SegmentedButton<int>(
              key: const Key('workout-tabs'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: 0,
                  label: Text(l.workoutTabLog, key: const Key('workout-tab-log')),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text(l.workoutTabLibrary, key: const Key('workout-tab-library')),
                ),
                ButtonSegment(
                  value: 2,
                  label: Text(l.workoutTabStats, key: const Key('workout-tab-stats')),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _page(WorkoutLog(key: _log, onChanged: _changed)),
                library == null
                    ? const LoadingView()
                    : _LibraryView(
                        library: library,
                        api: _api,
                        revision: _revision,
                        onLog: _logExercise,
                      ),
                library == null
                    ? const LoadingView()
                    : _page(_ProgressView(key: ValueKey(_revision), api: _api, library: library)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _page(Widget child) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
    child: Center(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 880), child: child),
    ),
  );
}

// -- the library ---------------------------------------------------------------

class _LibraryView extends StatefulWidget {
  const _LibraryView({
    required this.library,
    required this.api,
    required this.revision,
    required this.onLog,
  });

  final ExerciseLibrary library;
  final SelfInfinityApi api;
  final int revision;
  final Future<void> Function(LibraryExercise e) onLog;

  @override
  State<_LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<_LibraryView> {
  BodyPart? _body;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    final language = Localizations.localeOf(context).languageCode;
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final e in widget.library.exercises)
        if ((_body == null || e.body == _body) &&
            (q.isEmpty || e.names.values.any((n) => n.toLowerCase().contains(q))))
          e,
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: CustomScrollView(
          key: const Key('library'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('library-search'),
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: l.libSearch,
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final b in [null, ...BodyPart.values])
                            Padding(
                              padding: const EdgeInsets.only(right: AppSpacing.xs),
                              child: ChoiceChip(
                                key: Key('body-${b?.name ?? 'all'}'),
                                label: Text(b == null ? l.bodyAll : bodyLabel(l, b)),
                                selected: _body == b,
                                showCheckmark: false,
                                onSelected: (_) => setState(() => _body = b),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            ),
            if (shown.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Text(
                    l.libNone,
                    textAlign: TextAlign.center,
                    style: theme.bodyMedium?.copyWith(color: AppColors.textTertiary),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                sliver: SliverLayoutBuilder(
                  builder: (context, box) {
                    // As tall as a card's content: the 4:3 picture, the name, the equipment.
                    final columns = (box.crossAxisExtent / 210).ceil().clamp(1, 6);
                    final width = (box.crossAxisExtent - AppSpacing.md * (columns - 1)) / columns;
                    final scale = MediaQuery.textScalerOf(context).scale(1);
                    final extent = (width - 2 * AppSpacing.sm) * 3 / 4 + 2 * AppSpacing.sm + 56 * scale;
                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: AppSpacing.md,
                        crossAxisSpacing: AppSpacing.md,
                        mainAxisExtent: extent,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _ExerciseCard(
                          exercise: shown[i],
                          language: language,
                          onTap: () => unawaited(_open(shown[i])),
                        ),
                        childCount: shown.length,
                      ),
                    );
                  },
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Text(
                  l.libSource,
                  textAlign: TextAlign.center,
                  style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(LibraryExercise e) async {
    final log = await showDialog<bool>(
      context: context,
      builder: (_) => _ExerciseDetail(exercise: e, api: widget.api),
    );
    if (log == true && mounted) await widget.onLog(e);
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.exercise, required this.language, required this.onTap});

  final LibraryExercise exercise;
  final String language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    return Material(
      key: Key('exercise-${exercise.id}'),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardBorder,
        side: const BorderSide(color: AppColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExerciseMotion(images: exercise.images),
              const SizedBox(height: AppSpacing.sm),
              Text(exercise.name(language), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.bodyMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                equipmentLabel(l, exercise.equipment),
                style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A movement: its frames, how it is done, and the user's own history of it.
class _ExerciseDetail extends StatefulWidget {
  const _ExerciseDetail({required this.exercise, required this.api});

  final LibraryExercise exercise;
  final SelfInfinityApi api;

  @override
  State<_ExerciseDetail> createState() => _ExerciseDetailState();
}

class _ExerciseDetailState extends State<_ExerciseDetail> {
  List<Workout>? _history;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final all = await widget.api.listWorkouts(from: '2000-01-01', to: '2999-12-31');
      final e = widget.exercise;
      final mine = [
        for (final w in all)
          if ((e.catalog != null && w.exerciseKey == e.catalog) || e.isCalled(w.exercise)) w,
      ];
      if (mounted) setState(() => _history = mine);
    } on Object {
      if (mounted) setState(() => _history = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    final language = Localizations.localeOf(context).languageCode;
    final e = widget.exercise;
    final history = _history;
    final best = history == null ? null : _bestOf(history);
    return Dialog(
      key: const Key('exercise-detail'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ExerciseMotion(images: e.images),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      e.name(language),
                      key: const Key('exercise-name'),
                      style: theme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      [bodyLabel(l, e.body), equipmentLabel(l, e.equipment)].join(' · '),
                      style: theme.labelMedium?.copyWith(color: AppColors.textTertiary),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      l.libSteps,
                      style: theme.labelLarge?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    for (final (i, step) in e.stepsIn(language).indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 22,
                              child: Text(
                                '${i + 1}',
                                style: theme.labelLarge?.copyWith(color: AppColors.ember),
                              ),
                            ),
                            Expanded(child: Text(step, style: theme.bodyMedium)),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l.libHistory,
                            style: theme.labelLarge?.copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                        if (best != null)
                          Text(
                            l.libBest(best),
                            key: const Key('exercise-best'),
                            style: theme.labelMedium?.copyWith(color: AppColors.xp),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    if (history == null)
                      const SizedBox(height: 48, child: LoadingView())
                    else if (history.isEmpty)
                      Text(
                        l.libNoHistory,
                        style: theme.bodyMedium?.copyWith(color: AppColors.textTertiary),
                      )
                    else
                      for (final w in history.take(8))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                          child: Row(
                            children: [
                              SizedBox(width: 96, child: Text(w.date, style: theme.labelMedium)),
                              Expanded(child: Text(w.amount.label, style: theme.bodyMedium)),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(l.close),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    key: const Key('exercise-log'),
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(l.libLog),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The best set: the heaviest weight, else the longest time or distance.
  static String? _bestOf(List<Workout> h) {
    double top(double? Function(WorkoutAmount a) f) =>
        h.fold(0, (m, w) => (f(w.amount) ?? 0) > m ? f(w.amount)! : m);
    String fmt(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
    final kg = top((a) => a.weightKg);
    if (kg > 0) return '${fmt(kg)}kg';
    final km = top((a) => a.distanceKm);
    if (km > 0) return '${fmt(km)}km';
    final min = top((a) => a.durationMin?.toDouble());
    if (min > 0) return '${fmt(min)}min';
    final reps = top((a) => a.reps?.toDouble());
    return reps > 0 ? '×${fmt(reps)}' : null;
  }
}

// -- progress ------------------------------------------------------------------

class _ProgressView extends StatefulWidget {
  const _ProgressView({super.key, required this.api, required this.library});

  final SelfInfinityApi api;
  final ExerciseLibrary library;

  @override
  State<_ProgressView> createState() => _ProgressViewState();
}

class _ProgressViewState extends State<_ProgressView> {
  List<Workout>? _all;
  String? _picked;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final all = await widget.api.listWorkouts(from: '2000-01-01', to: '2999-12-31');
      if (mounted) setState(() => _all = all);
    } on Object {
      if (mounted) setState(() => _all = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    final all = _all;
    if (all == null) return const SizedBox(height: 160, child: LoadingView());
    if (all.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          l.statsNone,
          key: const Key('stats-none'),
          textAlign: TextAlign.center,
          style: theme.bodyMedium?.copyWith(color: AppColors.textTertiary),
        ),
      );
    }
    // Exercises by how often they were logged.
    final counts = <String, int>{};
    for (final w in all) {
      counts[w.exercise] = (counts[w.exercise] ?? 0) + 1;
    }
    final days = <String, Set<String>>{};
    for (final w in all) {
      (days[w.exercise] ??= {}).add(w.date);
    }
    // The exercise logged on the most days first: it has the longest line.
    final names = counts.keys.toList()
      ..sort((a, b) {
        final byDays = days[b]!.length.compareTo(days[a]!.length);
        return byDays != 0 ? byDays : counts[b]!.compareTo(counts[a]!);
      });
    final picked = names.contains(_picked) ? _picked! : names.first;
    final mine = all.where((w) => w.exercise == picked).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final (label, points) = _series(l, mine);

    // The last 30 days by body part (the library's, else the category's).
    final since = formatKstDate(DateTime.now().subtract(const Duration(days: 29)));
    final byBody = <String, int>{};
    for (final w in all.where((w) => w.date.compareTo(since) >= 0)) {
      final lib = widget.library.of(w);
      final key = lib != null ? bodyLabel(l, lib.body) : categoryLabel(l, w.category);
      byBody[key] = (byBody[key] ?? 0) + 1;
    }
    final rows = byBody.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: const Key('stats-exercise'),
          initialValue: picked,
          decoration: InputDecoration(labelText: l.statsPick),
          items: [
            for (final n in names) DropdownMenuItem(value: n, child: Text('$n  (${counts[n]})')),
          ],
          onChanged: (v) => setState(() => _picked = v),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(label, style: theme.labelLarge?.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpacing.sm),
        if (points.length > 1)
          ProgressLine(points: points)
        else
          Text(
            _fmt(points.single.$2),
            key: const Key('stats-single'),
            style: theme.displaySmall,
          ),
        const SizedBox(height: AppSpacing.xl),
        Text(l.statsByBody, style: theme.labelLarge?.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpacing.sm),
        CountBars(key: const Key('stats-by-body'), rows: [for (final e in rows) (e.key, e.value)]),
      ],
    );
  }

  static String _fmt(double v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

  /// What to chart for the exercise: the top weight per day when it has
  /// weights, else kg × reps volume, else minutes (or km).
  static (String, List<(String, double)>) _series(AppLocalizations l, List<Workout> mine) {
    List<(String, double)> perDay(double Function(WorkoutAmount a) f, {bool sum = false}) {
      final days = <String, double>{};
      for (final w in mine) {
        final v = f(w.amount);
        days[w.date] = sum
            ? (days[w.date] ?? 0) + v
            : ((days[w.date] ?? 0) > v ? days[w.date]! : v);
      }
      return [for (final e in days.entries) (e.key, e.value)]..sort((a, b) => a.$1.compareTo(b.$1));
    }

    if (mine.any((w) => (w.amount.weightKg ?? 0) > 0)) {
      return (l.statsWeight, perDay((a) => a.weightKg ?? 0));
    }
    if (mine.any((w) => w.amount.reps != null)) {
      return (l.statsVolume, perDay((a) => ((a.sets ?? 1) * (a.reps ?? 0)).toDouble(), sum: true));
    }
    return (l.statsMinutes, perDay((a) => (a.durationMin ?? 0).toDouble(), sum: true));
  }
}
