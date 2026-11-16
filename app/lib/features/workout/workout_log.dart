import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/api_exception.dart';
import '../../api/models.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../upload/file_picker_service.dart';
import '../../upload/file_saver.dart';
import '../../widgets/widgets.dart';
import 'exercise_library.dart';
import 'exercise_motion.dart';
import 'workout_charts.dart';

/// The log of the workout page (contract #54): say a line and it is split
/// into workouts; the last 90 days as a heatmap (a tap picks the day); that
/// day's routines to check off and its workouts to fix or delete; the streak
/// and workout XP on top; routines, export and import behind ⋯.
class WorkoutLog extends StatefulWidget {
  const WorkoutLog({super.key, this.onChanged});

  /// A workout was added, changed or removed.
  final VoidCallback? onChanged;

  @override
  State<WorkoutLog> createState() => WorkoutLogState();
}

/// One exercise the add dialog offers: from the bundled library (with its
/// frames) or the server's quick-log catalog.
@immutable
class ExerciseOption {
  const ExerciseOption({required this.name, required this.category, required this.unit, this.key, this.library});

  final String name;
  final WorkoutCategory category;
  final WorkoutUnit unit;

  /// The server's catalog key, when the movement has one.
  final String? key;
  final LibraryExercise? library;
}

/// What can be picked when logging: the library first, then the catalog
/// movements the library does not have.
class ExerciseChoices {
  ExerciseChoices(WorkoutCatalog? catalog, ExerciseLibrary? library, this.language)
    : _library = library,
      options = [
        for (final e in library?.exercises ?? const <LibraryExercise>[])
          ExerciseOption(name: e.name(language), category: e.category, unit: e.unit, key: e.catalog, library: e),
        for (final c in catalog?.exercises ?? const <CatalogExercise>[])
          if (!(library?.exercises.any((e) => e.catalog == c.key) ?? false))
            ExerciseOption(name: c.name, category: c.category, unit: c.unit, key: c.key),
      ];

  final String language;
  final ExerciseLibrary? _library;
  final List<ExerciseOption> options;

  /// The option [name] means (its name in any language), if any.
  ExerciseOption? match(String name) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return null;
    return options.where((o) => o.name.toLowerCase() == n || (o.library?.isCalled(n) ?? false)).firstOrNull;
  }

  LibraryExercise? libraryOf(Workout w) => _library?.of(w);
}

/// Add a workout ([prefill] picks the exercise); true when one was saved.
Future<bool> showWorkoutDialog(
  BuildContext context, {
  required SelfInfinityApi api,
  required ExerciseChoices choices,
  required String date,
  ExerciseOption? prefill,
  Workout? workout,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _WorkoutDialog(api: api, choices: choices, date: date, workout: workout, prefill: prefill),
    ) ??
    false;

String _today() => formatKstDate(DateTime.now());

String _shift(String date, int days) =>
    DateFormat('yyyy-MM-dd').format(DateTime.parse(date).add(Duration(days: days, hours: 12)));

String categoryLabel(AppLocalizations l, WorkoutCategory c) => switch (c) {
  WorkoutCategory.strength => l.workoutCatStrength,
  WorkoutCategory.cardio => l.workoutCatCardio,
  WorkoutCategory.flexibility => l.workoutCatFlexibility,
  WorkoutCategory.sports => l.workoutCatSports,
  WorkoutCategory.other => l.workoutCatOther,
};

class WorkoutLogState extends State<WorkoutLog> {
  late final SelfInfinityApi _api = context.read<SelfInfinityApi>();
  final TextEditingController _say = TextEditingController();

  String _date = _today();
  WorkoutCatalog? _catalog;
  ExerciseLibrary? _library;
  WorkoutSummary? _summary;
  WorkoutSummary? _quarter;
  List<Workout> _workouts = const [];
  List<RoutineDay> _routines = const [];
  Object? _error;
  bool _saying = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _say.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_token;
    try {
      final results = await Future.wait([
        if (_catalog == null) _api.getWorkoutCatalog() else Future.value(_catalog),
        _api.getWorkoutSummary(),
        _api.getWorkoutSummary(days: 90),
        _api.listWorkouts(from: _date, to: _date),
        _api.getRoutineDay(date: _date),
        if (_library == null) ExerciseLibrary.load() else Future.value(_library),
      ]);
      if (!mounted || token != _token) return;
      setState(() {
        _catalog = results[0] as WorkoutCatalog?;
        _summary = results[1] as WorkoutSummary?;
        _quarter = results[2] as WorkoutSummary?;
        _workouts = results[3] as List<Workout>;
        _routines = results[4] as List<RoutineDay>;
        _library = results[5] as ExerciseLibrary?;
        _error = null;
      });
    } on Object catch (e) {
      if (!mounted || token != _token) return;
      setState(() => _error = e);
    }
  }

  ExerciseChoices get choices =>
      ExerciseChoices(_catalog, _library, Localizations.localeOf(context).languageCode);

  /// Reloads (a workout was logged elsewhere on the page).
  Future<void> reload() => _load();

  Future<void> _changed() async {
    widget.onChanged?.call();
    await _load();
  }

  void _pick(String date) {
    if (date == _date) return;
    setState(() => _date = date);
    unawaited(_load());
  }

  Future<void> _sendSaid() async {
    final text = _say.text.trim();
    if (text.isEmpty || _saying) return;
    final l = context.l10n;
    setState(() => _saying = true);
    try {
      final said = await _api.sayWorkout(text, date: _date);
      if (!mounted) return;
      if (said.workouts.isEmpty) {
        showToast(context, l.workoutSaidNothing);
      } else {
        _say.clear();
        showToast(
          context,
          said.unread.isEmpty
              ? l.workoutSaved(said.workouts.length)
              : '${l.workoutSaved(said.workouts.length)} ${l.workoutUnread(said.unread.join(', '))}',
        );
        await _changed();
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _saying = false);
    }
  }

  Future<void> _edit([Workout? workout]) async {
    if (_catalog == null) return;
    final saved = await showWorkoutDialog(context, api: _api, choices: choices, date: _date, workout: workout);
    if (saved && mounted) await _changed();
  }

  Future<void> _delete(Workout w) async {
    try {
      await _api.deleteWorkout(w.id);
      if (mounted) await _changed();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage);
    }
  }

  Future<void> _toggle(RoutineDay day, RoutineDayItem item) async {
    try {
      if (item.checked) {
        await _api.uncheckRoutineItem(day.routine.id, item.index, date: _date);
      } else {
        await _api.checkRoutineItem(day.routine.id, item.index, date: _date);
      }
      if (mounted) await _changed();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage);
    }
  }

  Future<void> _menu(String action) async {
    final l = context.l10n;
    switch (action) {
      case 'routines':
        if (_catalog == null) return;
        final choices = this.choices;
        await showDialog<void>(
          context: context,
          builder: (_) => _RoutinesDialog(api: _api, choices: choices),
        );
        if (mounted) await _load();
      case 'csv' || 'xlsx':
        try {
          final bytes = await _api.exportWorkouts(action);
          final stamp = DateFormat('yyyyMMdd').format(DateTime.now());
          final ok = await saveFile(
            bytes,
            filename: 'workouts-$stamp.$action',
            mimeType: action == 'csv'
                ? 'text/csv'
                : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          );
          if (!ok && mounted) showToast(context, l.workoutExportUnavailable);
        } on ApiException catch (e) {
          if (mounted) showToast(context, e.userMessage);
        }
      case 'import':
        final file = await context.read<FilePickerService>().pick(extensions: const ['csv', 'xlsx']);
        if (file == null || !mounted) return;
        try {
          final result = await _api.importWorkouts(filename: file.name, bytes: file.bytes);
          if (!mounted) return;
          final errors = result.errors.map((e) => '#${e.row} ${e.reason}').join(' · ');
          showToast(
            context,
            [l.workoutImported(result.imported, result.skipped), if (errors.isNotEmpty) errors].join(' '),
          );
          await _changed();
        } on ApiException catch (e) {
          if (mounted) showToast(context, e.userMessage);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    final summary = _summary;
    // A Material, not a DecoratedBox: the rows' ink and checkboxes paint on it.
    return Material(
      key: const Key('workout-log'),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardBorder,
        side: const BorderSide(color: AppColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Spacer(),
                if (summary != null) ...[
                  if (summary.streak > 0) ...[
                    const Icon(Icons.local_fire_department_rounded, size: 16, color: AppColors.ember),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      l.workoutStreak(summary.streak),
                      key: const Key('workout-streak'),
                      style: theme.labelMedium,
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Text(
                    '${summary.xp} XP',
                    key: const Key('workout-xp'),
                    style: theme.labelMedium?.copyWith(color: AppColors.xp),
                  ),
                ],
                PopupMenuButton<String>(
                  key: const Key('workout-menu'),
                  tooltip: l.more,
                  icon: const Icon(Icons.more_horiz_rounded, size: 20, color: AppColors.textSecondary),
                  onSelected: (a) => unawaited(_menu(a)),
                  itemBuilder: (_) => [
                    PopupMenuItem(key: const Key('workout-export-csv'), value: 'csv', child: Text(l.workoutExportCsv)),
                    PopupMenuItem(
                      key: const Key('workout-export-xlsx'),
                      value: 'xlsx',
                      child: Text(l.workoutExportXlsx),
                    ),
                    PopupMenuItem(key: const Key('workout-import'), value: 'import', child: Text(l.workoutImport)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Composer(
              controller: _say,
              fieldKey: const Key('workout-say'),
              hint: l.workoutSayHint,
              onSend: () => unawaited(_sendSaid()),
              enabled: !_saying,
              busy: _saying,
              maxLength: 300,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_error != null && summary == null)
              ErrorView(error: _error!, onRetry: _load)
            else if (summary == null)
              const SizedBox(height: 120, child: LoadingView())
            else ...[
              WorkoutHeatmap(days: (_quarter ?? summary).byDay, selected: _date, onPick: _pick),
              const SizedBox(height: AppSpacing.lg),
              _DayHeader(
                date: _date,
                onPrev: () => _pick(_shift(_date, -1)),
                onNext: _date.compareTo(_today()) >= 0 ? null : () => _pick(_shift(_date, 1)),
                onAdd: () => unawaited(_edit()),
                onRoutines: () => unawaited(_menu('routines')),
              ),
              for (final day in _routines) _RoutineChecklist(day: day, onToggle: (i) => unawaited(_toggle(day, i))),
              if (_workouts.isEmpty && _routines.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    l.workoutNone,
                    key: const Key('workout-none'),
                    style: theme.bodyMedium?.copyWith(color: AppColors.textTertiary),
                  ),
                ),
              for (final w in _workouts.where((w) => w.source != WorkoutSource.routine))
                _WorkoutRow(
                  workout: w,
                  library: _library?.of(w),
                  onEdit: () => unawaited(_edit(w)),
                  onDelete: () => unawaited(_delete(w)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The last days as bars of how much was done; the picked day is dark.
class WorkoutWeek extends StatelessWidget {
  const WorkoutWeek({super.key, required this.days, required this.selected, this.onPick});

  final List<WorkoutDay> days;
  final String selected;
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final top = days.fold<int>(1, (m, d) => d.workouts > m ? d.workouts : m);
    final weekday = DateFormat.E(Localizations.localeOf(context).toLanguageTag());
    return SizedBox(
      height: 100,
      child: Row(
        key: const Key('workout-week'),
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in days)
            Expanded(
              child: InkWell(
                key: Key('workout-day-${d.date}'),
                borderRadius: AppRadius.chipBorder,
                onTap: onPick == null ? null : () => onPick!(d.date),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (d.workouts > 0)
                      Text('${d.workouts}', style: theme.labelSmall?.copyWith(color: AppColors.textTertiary)),
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      width: 18,
                      height: d.workouts == 0 ? 3 : 8 + 36 * d.workouts / top,
                      decoration: BoxDecoration(
                        color: d.date == selected
                            ? AppColors.textPrimary
                            : d.workouts == 0
                            ? AppColors.outline
                            : AppColors.ember,
                        borderRadius: AppRadius.chipBorder,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      weekday.format(DateTime.parse(d.date)),
                      style: theme.labelSmall?.copyWith(
                        color: d.date == selected ? AppColors.textPrimary : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// `‹ Mon, Nov 16 ›` and Add.
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.date,
    required this.onPrev,
    required this.onNext,
    required this.onAdd,
    required this.onRoutines,
  });

  final String date;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  final VoidCallback onAdd;
  final VoidCallback onRoutines;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    final label = DateFormat.MMMEd(Localizations.localeOf(context).toLanguageTag()).format(DateTime.parse(date));
    return Row(
      children: [
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const Key('workout-prev'),
                tooltip: l.workoutPrevDay,
                visualDensity: VisualDensity.compact,
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
              ),
              Flexible(
                child: Text(
                  label,
                  key: const Key('workout-date'),
                  style: theme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                key: const Key('workout-next'),
                tooltip: l.workoutNextDay,
                visualDensity: VisualDensity.compact,
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
              ),
            ],
          ),
        ),
        // A phone keeps the icons; the words come back where there is room.
        if (MediaQuery.sizeOf(context).width < AppLayout.wideBreakpoint) ...[
          IconButton.outlined(
            key: const Key('workout-routines'),
            tooltip: l.routinesTitle,
            onPressed: onRoutines,
            icon: const Icon(Icons.event_repeat_rounded, size: 18),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton.filled(
            key: const Key('workout-add'),
            tooltip: l.workoutNew,
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ] else ...[
          OutlinedButton.icon(
            key: const Key('workout-routines'),
            onPressed: onRoutines,
            icon: const Icon(Icons.event_repeat_rounded, size: 18),
            label: Text(l.routinesTitle),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.icon(
            key: const Key('workout-add'),
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(l.workoutAdd),
          ),
        ],
      ],
    );
  }
}

/// A routine of the day: its name and its exercises to check off.
class _RoutineChecklist extends StatelessWidget {
  const _RoutineChecklist({required this.day, required this.onToggle});

  final RoutineDay day;
  final ValueChanged<RoutineDayItem> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      key: Key('routine-day-${day.routine.id}'),
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.xs),
            child: Row(
              children: [
                Expanded(child: Text(day.routine.name, style: theme.labelLarge)),
                if (day.done) const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
              ],
            ),
          ),
          for (final item in day.items)
            CheckboxListTile(
              key: Key('routine-item-${day.routine.id}-${item.index}'),
              value: item.checked,
              onChanged: (_) => onToggle(item),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              title: Text(
                item.item.exercise,
                style: theme.bodyMedium?.copyWith(
                  decoration: item.checked ? TextDecoration.lineThrough : null,
                  color: item.checked ? AppColors.textTertiary : AppColors.textPrimary,
                ),
              ),
              secondary: Text(
                item.item.amount.label,
                style: theme.labelMedium?.copyWith(color: AppColors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}

/// One workout: name, numbers, category; tap to fix, × to delete.
class _WorkoutRow extends StatelessWidget {
  const _WorkoutRow({required this.workout, required this.onEdit, required this.onDelete, this.library});

  final Workout workout;

  /// The movement in the library, for its picture.
  final LibraryExercise? library;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    return InkWell(
      key: Key('workout-${workout.id}'),
      borderRadius: AppRadius.chipBorder,
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, 0, AppSpacing.xs),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: ExerciseMotion(images: library?.images.take(1).toList() ?? const []),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(workout.exercise, style: theme.bodyMedium),
                  Text(
                    [categoryLabel(l, workout.category), workout.amount.label].join(' · '),
                    style: theme.labelMedium?.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            IconButton(
              key: Key('workout-delete-${workout.id}'),
              tooltip: l.delete,
              onPressed: onDelete,
              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

/// The numbers of a workout or a routine item, as typed: the fields an
/// exercise is counted in (sets × reps and a weight; minutes; km and minutes).
class _AmountFields extends StatelessWidget {
  const _AmountFields({required this.unit, required this.controllers});

  final WorkoutUnit unit;
  final Map<String, TextEditingController> controllers;

  static const Map<WorkoutUnit, List<String>> fields = {
    WorkoutUnit.reps: ['sets', 'reps', 'weight'],
    WorkoutUnit.time: ['minutes'],
    WorkoutUnit.distance: ['distance', 'minutes'],
  };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    String label(String f) => switch (f) {
      'sets' => l.workoutSets,
      'reps' => l.workoutReps,
      'weight' => l.workoutWeight,
      'minutes' => l.workoutMinutes,
      _ => l.workoutDistance,
    };
    final decimal = {'weight', 'distance'};
    return Row(
      children: [
        for (final (i, f) in fields[unit]!.indexed) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              key: Key('amount-$f'),
              controller: controllers[f],
              keyboardType: TextInputType.numberWithOptions(decimal: decimal.contains(f)),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(decimal.contains(f) ? r'[0-9.]' : r'[0-9]')),
              ],
              decoration: InputDecoration(labelText: label(f)),
            ),
          ),
        ],
      ],
    );
  }
}

/// The exercise, its category and its numbers; shared by a workout and a
/// routine item.
class _ExerciseForm extends StatefulWidget {
  const _ExerciseForm({
    super.key,
    required this.choices,
    this.exercise = '',
    this.category,
    this.amount = const WorkoutAmount(),
  });

  final ExerciseChoices choices;
  final String exercise;
  final WorkoutCategory? category;
  final WorkoutAmount amount;

  @override
  State<_ExerciseForm> createState() => _ExerciseFormState();
}

class _ExerciseFormState extends State<_ExerciseForm> {
  late final TextEditingController _name = TextEditingController(text: widget.exercise);
  late WorkoutCategory _category = widget.category ?? WorkoutCategory.strength;
  late final Map<String, TextEditingController> _fields = {
    'sets': TextEditingController(text: _text(widget.amount.sets)),
    'reps': TextEditingController(text: _text(widget.amount.reps)),
    'weight': TextEditingController(text: _text(widget.amount.weightKg)),
    'minutes': TextEditingController(text: _text(widget.amount.durationMin)),
    'distance': TextEditingController(text: _text(widget.amount.distanceKm)),
  };

  static String _text(num? v) =>
      v == null ? '' : (v is double && v == v.roundToDouble() ? '${v.toInt()}' : '$v');

  ExerciseOption? get match => widget.choices.match(_name.text);

  WorkoutUnit get _unit =>
      match?.unit ??
      switch (_category) {
        WorkoutCategory.strength => WorkoutUnit.reps,
        WorkoutCategory.cardio => WorkoutUnit.distance,
        _ => WorkoutUnit.time,
      };

  String get exercise => _name.text.trim();
  WorkoutCategory get category => match?.category ?? _category;

  /// What is typed in the fields this exercise shows.
  WorkoutAmount get amount {
    final shown = _AmountFields.fields[_unit]!.toSet();
    int? i(String f) => shown.contains(f) ? int.tryParse(_fields[f]!.text) : null;
    double? d(String f) => shown.contains(f) ? double.tryParse(_fields[f]!.text) : null;
    return WorkoutAmount(
      sets: i('sets'),
      reps: i('reps'),
      weightKg: d('weight'),
      durationMin: i('minutes'),
      distanceKm: d('distance'),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final known = match;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Autocomplete<ExerciseOption>(
          initialValue: TextEditingValue(text: widget.exercise),
          displayStringForOption: (e) => e.name,
          optionsBuilder: (v) {
            final q = v.text.trim().toLowerCase();
            if (q.isEmpty) return widget.choices.options;
            return widget.choices.options.where((e) => e.name.toLowerCase().contains(q));
          },
          onSelected: (e) => setState(() {
            _name.text = e.name;
            _category = e.category;
          }),
          fieldViewBuilder: (context, controller, focus, submit) {
            // The field's own controller mirrors ours.
            if (controller.text != _name.text && controller.text.isEmpty) controller.text = _name.text;
            controller.addListener(() {
              if (_name.text != controller.text) setState(() => _name.text = controller.text);
            });
            return TextField(
              key: const Key('workout-exercise'),
              controller: controller,
              focusNode: focus,
              maxLength: 40,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              decoration: InputDecoration(labelText: l.workoutExercise),
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        if (known == null) ...[
          DropdownButtonFormField<WorkoutCategory>(
            key: const Key('workout-category'),
            initialValue: _category,
            decoration: InputDecoration(labelText: l.workoutCategory),
            items: [
              for (final c in WorkoutCategory.values)
                DropdownMenuItem(value: c, child: Text(categoryLabel(l, c))),
            ],
            onChanged: (c) => setState(() => _category = c ?? _category),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        _AmountFields(unit: _unit, controllers: _fields),
      ],
    );
  }
}

/// Add or fix one workout.
class _WorkoutDialog extends StatefulWidget {
  const _WorkoutDialog({required this.api, required this.choices, required this.date, this.workout, this.prefill});

  final SelfInfinityApi api;
  final ExerciseChoices choices;
  final String date;
  final Workout? workout;

  /// The exercise to log, picked before (the library's Log it).
  final ExerciseOption? prefill;

  @override
  State<_WorkoutDialog> createState() => _WorkoutDialogState();
}

class _WorkoutDialogState extends State<_WorkoutDialog> {
  final GlobalKey<_ExerciseFormState> _form = GlobalKey();
  late final TextEditingController _note = TextEditingController(text: widget.workout?.note ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final form = _form.currentState!;
    final l = context.l10n;
    if (form.exercise.isEmpty) return;
    if (form.amount.isEmpty) {
      setState(() => _error = l.workoutNeedAmount);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final draft = WorkoutDraft(
      date: widget.workout?.date ?? widget.date,
      exercise: form.exercise,
      exerciseKey: form.match?.key,
      category: form.category,
      amount: form.amount,
      note: _note.text,
    );
    try {
      final w = widget.workout;
      if (w == null) {
        await widget.api.createWorkout(draft);
      } else {
        await widget.api.updateWorkout(w.id, draft);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.userMessage;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final w = widget.workout;
    return AlertDialog(
      key: const Key('workout-dialog'),
      title: Text(w == null ? l.workoutNew : l.workoutEdit),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ExerciseForm(
                key: _form,
                choices: widget.choices,
                exercise: w?.exercise ?? widget.prefill?.name ?? '',
                category: w?.category ?? widget.prefill?.category,
                amount: w?.amount ?? const WorkoutAmount(),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('workout-note'),
                controller: _note,
                maxLength: 200,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                decoration: InputDecoration(labelText: l.workoutNote),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  key: const Key('workout-error'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.danger),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: Text(l.cancel)),
        FilledButton(
          key: const Key('workout-save'),
          onPressed: _busy ? null : () => unawaited(_save()),
          child: Text(l.workoutSave),
        ),
      ],
    );
  }
}

/// The routines: each with its days and exercises; tap to change, × to delete.
class _RoutinesDialog extends StatefulWidget {
  const _RoutinesDialog({required this.api, required this.choices});

  final SelfInfinityApi api;
  final ExerciseChoices choices;

  @override
  State<_RoutinesDialog> createState() => _RoutinesDialogState();
}

class _RoutinesDialogState extends State<_RoutinesDialog> {
  List<Routine>? _routines;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final routines = await widget.api.listRoutines();
      if (mounted) setState(() => _routines = routines);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage);
    }
  }

  Future<void> _edit([Routine? routine]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RoutineEditor(api: widget.api, choices: widget.choices, routine: routine),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete(Routine r) async {
    try {
      await widget.api.deleteRoutine(r.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.userMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    final routines = _routines;
    return AlertDialog(
      key: const Key('routines-dialog'),
      title: Text(l.routinesTitle),
      content: SizedBox(
        width: 400,
        child: routines == null
            ? const SizedBox(height: 120, child: LoadingView())
            : routines.isEmpty
            ? Text(l.routineNone, style: theme.bodyMedium?.copyWith(color: AppColors.textTertiary))
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final r in routines)
                    ListTile(
                      key: Key('routine-${r.id}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(r.name),
                      subtitle: Text(
                        '${weekdaysLabel(context, r.weekdays)} · ${r.items.map((i) => i.exercise).join(', ')}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => unawaited(_edit(r)),
                      trailing: IconButton(
                        key: Key('routine-delete-${r.id}'),
                        tooltip: l.delete,
                        onPressed: () => unawaited(_delete(r)),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.close)),
        FilledButton.icon(
          key: const Key('routine-new'),
          onPressed: () => unawaited(_edit()),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(l.routineNew),
        ),
      ],
    );
  }
}

/// The weekday's short name, Monday first (0 = Monday).
String weekdayName(BuildContext context, int day) =>
    DateFormat.E(Localizations.localeOf(context).toLanguageTag()).format(DateTime(2024, 1, 1 + day));

String weekdaysLabel(BuildContext context, List<int> days) =>
    [for (final d in [...days]..sort()) weekdayName(context, d)].join(' ');

/// Make or change a routine: its name, its days, its exercises.
class _RoutineEditor extends StatefulWidget {
  const _RoutineEditor({required this.api, required this.choices, this.routine});

  final SelfInfinityApi api;
  final ExerciseChoices choices;
  final Routine? routine;

  @override
  State<_RoutineEditor> createState() => _RoutineEditorState();
}

class _RoutineEditorState extends State<_RoutineEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.routine?.name ?? '');
  late final Set<int> _days = {...?widget.routine?.weekdays};
  late final List<RoutineItem> _items = [...?widget.routine?.items];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addItem() async {
    final item = await showDialog<RoutineItem>(
      context: context,
      builder: (_) => _ItemDialog(choices: widget.choices),
    );
    if (item != null) setState(() => _items.add(item));
  }

  Future<void> _save() async {
    final l = context.l10n;
    final problem = _name.text.trim().isEmpty
        ? l.routineName
        : _days.isEmpty
        ? l.routineNeedDay
        : _items.isEmpty
        ? l.routineNeedItem
        : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final draft = RoutineDraft(name: _name.text, weekdays: _days.toList(), items: _items);
    try {
      final r = widget.routine;
      if (r == null) {
        await widget.api.createRoutine(draft);
      } else {
        await widget.api.updateRoutine(r.id, draft);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.userMessage;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    return AlertDialog(
      key: const Key('routine-editor'),
      title: Text(widget.routine == null ? l.routineNew : l.routineEdit),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('routine-name'),
                controller: _name,
                maxLength: Routine.maxName,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                decoration: InputDecoration(labelText: l.routineName),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (var d = 0; d < 7; d++)
                    FilterChip(
                      key: Key('routine-day-$d'),
                      label: Text(weekdayName(context, d)),
                      selected: _days.contains(d),
                      showCheckmark: false,
                      onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d)),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              for (final (i, item) in _items.indexed)
                ListTile(
                  key: Key('routine-item-row-$i'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.exercise, style: theme.bodyMedium),
                  subtitle: Text(item.amount.label),
                  trailing: IconButton(
                    tooltip: l.delete,
                    onPressed: () => setState(() => _items.removeAt(i)),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ),
              if (_items.length < Routine.maxItems)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('routine-add-item'),
                    onPressed: () => unawaited(_addItem()),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(l.routineAddItem),
                  ),
                ),
              if (_error != null)
                Text(
                  _error!,
                  key: const Key('routine-error'),
                  style: theme.bodySmall?.copyWith(color: AppColors.danger),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: Text(l.cancel)),
        FilledButton(
          key: const Key('routine-save'),
          onPressed: _busy ? null : () => unawaited(_save()),
          child: Text(l.workoutSave),
        ),
      ],
    );
  }
}

/// One exercise of a routine.
class _ItemDialog extends StatefulWidget {
  const _ItemDialog({required this.choices});

  final ExerciseChoices choices;

  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  final GlobalKey<_ExerciseFormState> _form = GlobalKey();
  String? _error;

  void _done() {
    final form = _form.currentState!;
    if (form.exercise.isEmpty) return;
    if (form.amount.isEmpty) {
      setState(() => _error = context.l10n.workoutNeedAmount);
      return;
    }
    Navigator.of(context).pop(
      RoutineItem(
        exercise: form.exercise,
        exerciseKey: form.match?.key,
        category: form.category,
        amount: form.amount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      key: const Key('routine-item-dialog'),
      title: Text(l.routineAddItem),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ExerciseForm(key: _form, choices: widget.choices),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancel)),
        FilledButton(key: const Key('routine-item-done'), onPressed: _done, child: Text(l.workoutAdd)),
      ],
    );
  }
}
