import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/api_exception.dart';
import '../../api/models.dart';
import '../../app/app_state.dart';
import '../../app/router.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';
import '../stage/stage_scaffold.dart';
import 'life_chart.dart';

/// The player's own record (contract #39): how they live next to how they
/// learn. The window's numbers and chart, their own patterns, the Life
/// Coach's advice, and every day, which they can fix or fill in.
///
/// Route `/life`. Reading never calls the LLM; only `Get advice` does.
class LifeScene extends StatefulWidget {
  const LifeScene({super.key});

  @override
  State<LifeScene> createState() => _LifeSceneState();
}

class _LifeSceneState extends State<LifeScene> {
  late final SelfInfinityApi _api = context.read<SelfInfinityApi>();

  static const List<int> windows = [7, 30, 90];

  int _window = 30;
  Life? _life;
  Object? _error;
  bool _advising = false;
  bool _adviceFailed = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final token = ++_token;
    setState(() => _error = null);
    try {
      final life = await _api.getLife(days: _window);
      if (!mounted || token != _token) return;
      setState(() => _life = life);
    } on Object catch (e) {
      if (!mounted || token != _token) return;
      setState(() => _error = e);
    }
  }

  Future<void> _advise() async {
    setState(() {
      _advising = true;
      _adviceFailed = false;
    });
    try {
      await _api.requestLifeAdvice();
      if (!mounted) return;
      await _load();
    } on Object {
      if (!mounted) return;
      setState(() => _adviceFailed = true);
    } finally {
      if (mounted) setState(() => _advising = false);
    }
  }

  Future<void> _edit(String date, LifeDay? day) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditDayDialog(api: _api, date: date, day: day),
    );
    if (saved != true || !mounted) return;
    context.read<AppState>().markDataChanged(); // today's card in the panel
    await _load();
  }

  Future<void> _fillIn() async {
    final today = DateTime.parse(formatKstDate(DateTime.now()));
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    final date = DateFormat('yyyy-MM-dd').format(picked);
    await _edit(date, _life?.days.where((d) => d.date == date).firstOrNull);
  }

  @override
  Widget build(BuildContext context) {
    final life = _life;
    return StageScaffold(
      title: context.l10n.lifeTitle,
      topLeading: IconButton(
        key: const Key('back-home'),
        tooltip: context.l10n.back,
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => context.go(AppRoutes.home),
      ),
      stage: life == null
          ? (_error == null ? const LoadingView() : ErrorView(error: _error!, onRetry: _load))
          : LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                key: const Key('life-scroll'),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.sm,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _windowToggle(context),
                        const SizedBox(height: AppSpacing.lg),
                        _Summary(summary: life.summary, compact: box.maxWidth < 600),
                        const SizedBox(height: AppSpacing.lg),
                        _Card(
                          key: const Key('life-chart-card'),
                          title: context.l10n.lifeChartTitle(life.summary.days),
                          child: life.summary.daysLogged == 0 && life.summary.audits == 0
                              ? _muted(context, context.l10n.lifeNoData)
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    LifeChart(key: const Key('life-chart'), days: life.days),
                                    const SizedBox(height: AppSpacing.md),
                                    const _ChartLegend(),
                                  ],
                                ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _Patterns(life: life),
                        const SizedBox(height: AppSpacing.lg),
                        _Advice(
                          advice: life.advice,
                          busy: _advising,
                          failed: _adviceFailed,
                          onAsk: () => unawaited(_advise()),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _Days(
                          days: life.days,
                          onEdit: (d) => unawaited(_edit(d.date, d)),
                          onFillIn: () => unawaited(_fillIn()),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          context.l10n.lifePrivacy,
                          key: const Key('life-privacy'),
                          textAlign: TextAlign.center,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _windowToggle(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: SegmentedButton<int>(
      key: const Key('life-window'),
      showSelectedIcon: false,
      segments: [
        for (final w in windows)
          ButtonSegment(
            value: w,
            label: Text(context.l10n.lifeDays(w), key: Key('life-window-$w')),
          ),
      ],
      selected: {_window},
      onSelectionChanged: (s) {
        setState(() => _window = s.first);
        unawaited(_load());
      },
    ),
  );
}

Widget _muted(BuildContext context, String text) => Text(
  text,
  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textTertiary),
);

String _num(double? v) => v == null ? '—' : formatNumber(v, maxFractionDigits: 1);

/// A white card with a hairline and a small title.
class _Card extends StatelessWidget {
  const _Card({super.key, required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(color: AppColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.labelLarge?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

/// The window in big numbers: sleep, focus, stress, exercise days, weight.
class _Summary extends StatelessWidget {
  const _Summary({required this.summary, required this.compact});

  final LifeSummary summary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = summary;
    final change = s.weightFirst != null && s.weightLast != null
        ? s.weightLast! - s.weightFirst!
        : null;
    return Wrap(
      key: const Key('life-summary'),
      spacing: compact ? AppSpacing.xl : AppSpacing.xxl,
      runSpacing: AppSpacing.md,
      children: [
        _Number(
          key: const Key('life-sleep'),
          label: l.lifeSleep,
          value: _num(s.avgSleepHours),
          suffix: ' h',
        ),
        _Number(
          key: const Key('life-focus'),
          label: l.lifeFocus,
          value: _num(s.avgFocus),
          suffix: l.lifeOutOf5,
        ),
        _Number(
          key: const Key('life-stress'),
          label: l.lifeStress,
          value: _num(s.avgStress),
          suffix: l.lifeOutOf5,
        ),
        _Number(
          key: const Key('life-exercise'),
          label: l.lifeExercise,
          value: '${s.exerciseDays}',
          suffix: l.lifeDaysSuffix,
        ),
        if (s.weightLast != null)
          _Number(
            key: const Key('life-weight'),
            label: l.lifeWeight,
            value: _num(s.weightLast),
            suffix: change == null || change == 0
                ? ' kg'
                : ' kg (${change > 0 ? '+' : '−'}${_num(change.abs())})',
          ),
        _Number(
          key: const Key('life-audits'),
          label: l.lifeAudits,
          value: '${s.passed}',
          suffix: ' / ${s.audits}',
        ),
      ],
    );
  }
}

class _Number extends StatelessWidget {
  const _Number({super.key, required this.label, required this.value, this.suffix});

  final String label;
  final String value;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.labelSmall?.copyWith(color: AppColors.textTertiary)),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            text: value,
            style: theme.headlineLarge,
            children: [
              if (suffix != null)
                TextSpan(
                  text: suffix,
                  style: theme.titleMedium?.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final style = Theme.of(context).textTheme.bodySmall;
    Widget item(Color color, String label, {bool bar = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: bar ? 8 : 10,
          height: bar ? 12 : 3,
          decoration: BoxDecoration(color: color, borderRadius: AppRadius.chipBorder),
        ),
        const SizedBox(width: 6),
        Text(label, style: style),
      ],
    );
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.xs,
      children: [
        item(LifeChart.sleepColor, l.lifeSleep, bar: true),
        item(LifeChart.focusColor, l.lifeFocus),
        item(LifeChart.stressColor, l.lifeStress),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(l.lifeAudits, style: style),
          ],
        ),
      ],
    );
  }
}

/// The player's own days in two groups, or how many days it takes.
class _Patterns extends StatelessWidget {
  const _Patterns({required this.life});

  final Life life;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    String label(LifePatternKind kind, bool better) => switch ((kind, better)) {
      (LifePatternKind.sleep, true) => l.lifeSleepBetter,
      (LifePatternKind.sleep, false) => l.lifeSleepWorse,
      (LifePatternKind.exercise, true) => l.lifeExerciseBetter,
      (LifePatternKind.exercise, false) => l.lifeExerciseWorse,
      (LifePatternKind.stress, true) => l.lifeStressBetter,
      (LifePatternKind.stress, false) => l.lifeStressWorse,
    };
    String group(LifeGroup g) => [
      l.lifeGroupDays(g.days),
      g.passRate == null
          ? l.lifeGroupNoAudits
          : l.lifeGroupPassed((g.passRate! * 100).round(), g.audits),
      if (g.avgFocus != null) l.lifeGroupFocus(_num(g.avgFocus)),
    ].join(' · ');

    return _Card(
      key: const Key('life-patterns'),
      title: l.lifePatterns,
      child: life.patterns.isEmpty
          ? _muted(context, l.lifePatternsEmpty(life.patternMinDays))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final p in life.patterns)
                  Padding(
                    key: Key('life-pattern-${p.kind.name}'),
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final better in [true, false])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 120,
                                  child: Text(label(p.kind, better), style: theme.bodyMedium),
                                ),
                                Expanded(
                                  child: Text(
                                    group(better ? p.better : p.worse),
                                    style: theme.bodyMedium?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                Text(
                  l.lifePatternNote,
                  style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
    );
  }
}

/// The Life Coach: three pieces, each with the fact it rests on.
class _Advice extends StatelessWidget {
  const _Advice({
    required this.advice,
    required this.busy,
    required this.failed,
    required this.onAsk,
  });

  final LifeAdvice? advice;
  final bool busy;
  final bool failed;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    final a = advice;
    return _Card(
      key: const Key('life-advice'),
      title: l.lifeAdvice,
      trailing: busy
          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : TextButton(
              key: const Key('life-advice-get'),
              onPressed: onAsk,
              child: Text(a == null ? l.lifeAdviceGet : l.lifeAdviceAgain),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (failed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                l.lifeAdviceFailed,
                key: const Key('life-advice-failed'),
                style: theme.bodyMedium?.copyWith(color: AppColors.danger),
              ),
            ),
          if (a == null)
            _muted(context, l.lifeAdviceEmpty)
          else ...[
            for (final item in a.items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Column(
                  key: const Key('life-advice-item'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: theme.titleSmall),
                    const SizedBox(height: 2),
                    Text(item.body, style: theme.bodyMedium),
                    if (item.basedOn.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        l.lifeAdviceBasedOn(item.basedOn),
                        style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
            Text(
              formatLocal(a.generatedAt, style: DateStyle.dateTime),
              style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Every day with something in it, newest first, and today; tap to edit.
class _Days extends StatelessWidget {
  const _Days({required this.days, required this.onEdit, required this.onFillIn});

  final List<LifeDay> days;
  final ValueChanged<LifeDay> onEdit;
  final VoidCallback onFillIn;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    final shown = [
      for (final (i, d) in days.indexed.toList().reversed)
        if (d.checkedIn || d.audits > 0 || i == days.length - 1) d,
    ];
    String values(LifeDay d) => [
      if (d.sleepHours != null) l.hoursShort(formatNumber(d.sleepHours!)),
      if (d.sleepQuality != null) '${l.lifeSleepQuality} ${d.sleepQuality}',
      if (d.exerciseMinutes != null && d.exerciseMinutes! > 0)
        l.lifeMinutes(d.exerciseMinutes!)
      else if (d.exercised == true)
        l.lifeExercise,
      if (d.focus != null) '${l.lifeFocus} ${d.focus}',
      if (d.stress != null) '${l.lifeStress} ${d.stress}',
      if (d.weightKg != null) l.lifeKg(formatNumber(d.weightKg!, maxFractionDigits: 1)),
      if (d.audits > 0) l.lifeAuditsDone(d.passed, d.audits),
    ].join(' · ');

    return _Card(
      key: const Key('life-days'),
      title: l.lifeLog,
      trailing: TextButton(
        key: const Key('life-fill-in'),
        onPressed: onFillIn,
        child: Text(l.lifeFillIn),
      ),
      child: Column(
        children: [
          for (final d in shown)
            InkWell(
              key: Key('life-day-${d.date}'),
              borderRadius: AppRadius.chipBorder,
              onTap: () => onEdit(d),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        DateFormat.MMMEd().format(DateTime.parse(d.date)),
                        style: theme.bodyMedium,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        values(d).isEmpty ? '—' : values(d),
                        style: theme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                    const Icon(Icons.edit_outlined, size: 16, color: AppColors.textTertiary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One day's fields; saving sends them all (an empty one clears it).
class _EditDayDialog extends StatefulWidget {
  const _EditDayDialog({required this.api, required this.date, required this.day});

  final SelfInfinityApi api;
  final String date;
  final LifeDay? day;

  @override
  State<_EditDayDialog> createState() => _EditDayDialogState();
}

class _EditDayDialogState extends State<_EditDayDialog> {
  late final TextEditingController _sleep = TextEditingController(
    text: widget.day?.sleepHours == null ? '' : formatNumber(widget.day!.sleepHours!),
  );
  late final TextEditingController _minutes = TextEditingController(
    text: widget.day?.exerciseMinutes?.toString() ?? '',
  );
  late final TextEditingController _weight = TextEditingController(
    text: widget.day?.weightKg == null
        ? ''
        : formatNumber(widget.day!.weightKg!, maxFractionDigits: 1),
  );
  late final TextEditingController _meals = TextEditingController(text: widget.day?.dietNote ?? '');
  late int? _quality = widget.day?.sleepQuality;
  late int? _focus = widget.day?.focus;
  late int? _stress = widget.day?.stress;
  bool _saving = false;
  Object? _error;

  @override
  void dispose() {
    _sleep.dispose();
    _minutes.dispose();
    _weight.dispose();
    _meals.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    num? number(TextEditingController c) => num.tryParse(c.text.trim());
    final minutes = number(_minutes)?.round();
    try {
      await widget.api.editCheckIn(widget.date, {
        'sleep_hours': number(_sleep)?.round(),
        'sleep_quality': _quality,
        'exercise_minutes': minutes,
        if (minutes != null) 'exercised': minutes > 0,
        'weight_kg': number(_weight)?.toDouble(),
        'diet_note': _meals.text.trim().isEmpty ? null : _meals.text.trim(),
        'focus': _focus,
        'stress': _stress,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Widget field(Key key, TextEditingController c, String label, {bool decimal = false}) =>
        TextField(
          key: key,
          controller: c,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          decoration: InputDecoration(labelText: label),
        );
    Widget scale(Key key, String label, int? value, ValueChanged<int?> onChanged) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Wrap(
          key: key,
          spacing: 6,
          children: [
            for (var i = 1; i <= 5; i++)
              ChoiceChip(
                label: Text('$i'),
                selected: value == i,
                showCheckmark: false,
                onSelected: (on) => onChanged(on ? i : null),
              ),
          ],
        ),
      ],
    );
    return AlertDialog(
      key: const Key('life-edit-dialog'),
      title: Text(l.lifeEdit(DateFormat.yMMMEd().format(DateTime.parse(widget.date)))),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field(const Key('edit-sleep'), _sleep, l.lifeSleepHours),
              const SizedBox(height: AppSpacing.md),
              scale(
                const Key('edit-quality'),
                l.lifeSleepQuality,
                _quality,
                (v) => setState(() => _quality = v),
              ),
              const SizedBox(height: AppSpacing.md),
              field(const Key('edit-minutes'), _minutes, l.lifeExerciseMinutes),
              field(const Key('edit-weight'), _weight, l.lifeWeightKg, decimal: true),
              TextField(
                key: const Key('edit-meals'),
                controller: _meals,
                decoration: InputDecoration(labelText: l.meals),
              ),
              const SizedBox(height: AppSpacing.md),
              scale(
                const Key('edit-focus'),
                l.lifeFocus,
                _focus,
                (v) => setState(() => _focus = v),
              ),
              const SizedBox(height: AppSpacing.md),
              scale(
                const Key('edit-stress'),
                l.lifeStress,
                _stress,
                (v) => setState(() => _stress = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  (_error is ApiException ? (_error as ApiException).serverMessage : null) ??
                      '$_error',
                  style: const TextStyle(color: AppColors.danger),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
        FilledButton(
          key: const Key('edit-save'),
          onPressed: _saving ? null : () => unawaited(_save()),
          child: Text(l.lifeSave),
        ),
      ],
    );
  }
}
