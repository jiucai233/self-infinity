import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/api_exception.dart';
import '../../api/models.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/status_chip.dart';
import 'learner_chart.dart';

/// Opens the developer panel (contract #34) over the current scene.
Future<void> showDevPanel(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const Dialog(
    insetPadding: EdgeInsets.all(AppSpacing.xl),
    backgroundColor: AppColors.background,
    child: DevPanel(),
  ),
);

/// The developer panel: how well the Auditor judges, from the developers'
/// reviews of its verdicts, and how audits go overall; below, every finished
/// audit with its transcript and the buttons to review it. A second tab shows
/// what live voice costs (contract #37), a third what the text agents' calls
/// cost on each model, a fourth the learner model: the user's ability audit
/// by audit, the Auditor's error rates and the nodes open to study.
class DevPanel extends StatefulWidget {
  const DevPanel({super.key});

  @override
  State<DevPanel> createState() => _DevPanelState();
}

class _DevPanelState extends State<DevPanel> {
  late final SelfInfinityApi _api = context.read<SelfInfinityApi>();
  DevAudits? _data;
  Object? _error;
  final Set<int> _open = {};
  _Tab _tab = _Tab.audits;
  DevVoice? _voice;
  Object? _voiceError;
  DevLlm? _llm;
  Object? _llmError;
  LearnerModel? _learner;
  Object? _learnerError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final data = await _api.getDevAudits(limit: 100);
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadVoice() async {
    try {
      final voice = await _api.getDevVoice(limit: 100);
      if (mounted) {
        setState(() {
          _voice = voice;
          _voiceError = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _voiceError = e);
    }
  }

  Future<void> _loadLlm() async {
    try {
      final llm = await _api.getDevLlm();
      if (mounted) {
        setState(() {
          _llm = llm;
          _llmError = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _llmError = e);
    }
  }

  Future<void> _loadLearner() async {
    try {
      final learner = await _api.getLearner();
      if (mounted) {
        setState(() {
          _learner = learner;
          _learnerError = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _learnerError = e);
    }
  }

  void _show(_Tab tab) {
    setState(() => _tab = tab);
    if (tab == _Tab.voice && _voice == null) unawaited(_loadVoice());
    if (tab == _Tab.llm && _llm == null) unawaited(_loadLlm());
    if (tab == _Tab.learner && _learner == null) unawaited(_loadLearner());
  }

  Future<void> _refresh() => switch (_tab) {
    _Tab.audits => _load(),
    _Tab.voice => _loadVoice(),
    _Tab.llm => _loadLlm(),
    _Tab.learner => _loadLearner(),
  };

  Future<void> _review(DevAudit audit, AuditReview? review, bool leaked) async {
    try {
      await _api.reviewAudit(audit.id, review, leaked: leaked);
      await _load(); // the metrics move with every review
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(e.userMessage)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    final data = _data;
    final tabs = SegmentedButton<_Tab>(
      key: const Key('dev-tabs'),
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: _Tab.audits,
          label: Text(l.devTabAudits, key: const Key('dev-tab-audits')),
        ),
        ButtonSegment(
          value: _Tab.voice,
          label: Text(l.devTabVoice, key: const Key('dev-tab-voice')),
        ),
        ButtonSegment(
          value: _Tab.llm,
          label: Text(l.devTabLlm, key: const Key('dev-tab-llm')),
        ),
        ButtonSegment(
          value: _Tab.learner,
          label: Text(l.devTabLearner, key: const Key('dev-tab-learner')),
        ),
      ],
      selected: {_tab},
      onSelectionChanged: (s) => _show(s.first),
    );
    // On a phone the four tabs do not fit beside the title: they get a line of their own.
    final narrow = MediaQuery.sizeOf(context).width < AppLayout.wideBreakpoint;
    return ConstrainedBox(
      key: const Key('dev-panel'),
      constraints: const BoxConstraints(maxWidth: 960),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.sm, 0),
            child: Row(
              children: [
                Expanded(child: Text(l.devTitle, style: theme.titleLarge)),
                if (!narrow) tabs,
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  key: const Key('dev-refresh'),
                  tooltip: l.devRefresh,
                  onPressed: () => unawaited(_refresh()),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: l.close,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          if (narrow)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.sm,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: tabs,
            ),
          Expanded(
            child: _tab == _Tab.voice
                ? _VoiceCosts(voice: _voice, error: _voiceError)
                : _tab == _Tab.llm
                ? _LlmCosts(llm: _llm, error: _llmError)
                : _tab == _Tab.learner
                ? _Learner(learner: _learner, error: _learnerError)
                : data == null
                ? Center(
                    child: _error == null
                        ? const CircularProgressIndicator()
                        : Text(
                            _error is ApiException
                                ? (_error! as ApiException).userMessage
                                : '$_error',
                          ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.sm,
                      AppSpacing.xl,
                      AppSpacing.xl,
                    ),
                    children: [
                      Text(
                        l.devHint,
                        style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _Metrics(metrics: data.metrics),
                      const SizedBox(height: AppSpacing.xl),
                      if (data.audits.isEmpty)
                        Text(l.devNoAudits, style: theme.bodyMedium)
                      else
                        for (final a in data.audits)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.md),
                            child: _AuditCard(
                              audit: a,
                              open: _open.contains(a.id),
                              onToggle: () => setState(
                                () => _open.contains(a.id) ? _open.remove(a.id) : _open.add(a.id),
                              ),
                              onReview: (review, leaked) => unawaited(_review(a, review, leaked)),
                            ),
                          ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

enum _Tab { audits, voice, llm, learner }

/// Dollars for what costs fractions of a cent (one model call): two
/// significant digits below a cent.
String _usdFine(double? v) => v == null
    ? '—'
    : v == 0
    ? '\$0'
    : v < 0.01
    ? '\$${v.toStringAsPrecision(2)}'
    : _usd(v);

String _pct(double? v) => v == null ? '—' : '${(v * 100).round()}%';
String _usd(double? v) =>
    v == null ? '—' : '\$${v < 1 ? v.toStringAsFixed(3) : v.toStringAsFixed(2)}';
String _num(double? v, [int digits = 1]) => v == null ? '—' : v.toStringAsFixed(digits);

/// An ability to two decimals with its sign (`+0.20`, `-0.10`, `0.00`).
String _signed(double v) {
  final digits = v.abs().toStringAsFixed(2);
  return digits == '0.00' ? digits : '${v > 0 ? '+' : '-'}$digits';
}

/// A titled row of number tiles, keyed `dev-metric-<key>` (or [prefix]`<key>`).
Widget _tiles(
  BuildContext context,
  String title,
  List<(String, String, String)> tiles, {
  String prefix = 'dev-metric-',
}) {
  final theme = Theme.of(context).textTheme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: theme.labelLarge),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.md,
        children: [
          for (final (key, label, value) in tiles)
            SizedBox(
              width: 112,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.labelSmall?.copyWith(color: AppColors.textTertiary)),
                  // A long figure ($0.00046) shrinks to its tile instead of wrapping.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, key: Key('$prefix$key'), style: theme.headlineMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    ],
  );
}

/// What live voice costs: the Guide and the audits on each of their voices,
/// a GPT-Live session's two parts (the voice, its other call), and every
/// session.
class _VoiceCosts extends StatelessWidget {
  const _VoiceCosts({required this.voice, required this.error});

  final DevVoice? voice;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    final v = voice;
    if (v == null) {
      final e = error;
      return Center(
        child: e == null
            ? const CircularProgressIndicator()
            : Text(e is ApiException ? e.userMessage : '$e'),
      );
    }
    return ListView(
      key: const Key('dev-voice'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      children: [
        Text(l.devVoiceHint, style: theme.bodySmall?.copyWith(color: AppColors.textTertiary)),
        const SizedBox(height: AppSpacing.lg),
        _tiles(context, l.devVoiceGuide, [
          ('guide-sessions', l.devVoiceSessions, '${v.guideSessions}'),
          ('guide-minutes', l.devVoiceMinutes, _num(v.guideMinutes)),
          ('guide-cost', l.devVoiceCost, _usd(v.guideCost)),
          ('guide-per-minute', l.devVoicePerMinute, _usd(v.guideCostPerMinute)),
          ('guide-per-session', l.devVoicePerSession, _usd(v.guideCostPerSession)),
          ('guide-all-live', l.devVoiceAllLive, _usd(v.guideAllLive)),
          ('guide-all-realtime', l.devVoiceAllRealtime, _usd(v.guideAllRealtime)),
          (
            'realtime-rate',
            v.realtimeRateMeasured ? l.devVoiceRealtimeRate : l.devVoiceRealtimeRateDefault,
            _usd(v.realtimePerMinute),
          ),
          ('guide-cached', l.devVoiceCached, _pct(v.guideCachedShare)),
        ]),
        const SizedBox(height: AppSpacing.lg),
        _tiles(context, l.devVoiceAudits, [
          ('audit-sessions', l.devVoiceSessions, '${v.auditSessions}'),
          ('audit-minutes', l.devVoiceMinutes, _num(v.auditMinutes)),
          ('audit-cost', l.devVoiceCost, _usd(v.auditCost)),
          ('audit-live-per-session', l.devVoicePerSessionLive, _usd(v.auditLiveCostPerSession)),
          ('audit-turns-per-session', l.devVoicePerSessionTurns, _usd(v.auditTurnsCostPerSession)),
          ('audit-all-live', l.devVoiceAllLive, _usd(v.auditAllLive)),
          ('audit-all-turns', l.devVoiceAllTurns, _usd(v.auditAllTurns)),
          (
            'turns-rate',
            v.turnsRateMeasured ? l.devVoiceTurnsRate : l.devVoiceTurnsRateDefault,
            _usd(v.turnsPerMinute),
          ),
        ]),
        const SizedBox(height: AppSpacing.lg),
        _tiles(context, l.devVoiceLiveParts, [
          ('guide-live-voice', l.devVoiceGuideVoice, _usd(v.guideLiveVoiceCost)),
          ('guide-live-backend', l.devVoiceGuideBackend, _usdFine(v.guideLiveBackendCost)),
          ('audit-live-voice', l.devVoiceAuditVoice, _usd(v.auditLiveVoiceCost)),
          ('audit-live-backend', l.devVoiceAuditBackend, _usdFine(v.auditLiveBackendCost)),
        ]),
        const SizedBox(height: AppSpacing.xl),
        if (v.sessions.isEmpty)
          Text(l.devNoVoice, style: theme.bodyMedium)
        else
          for (final s in v.sessions)
            Padding(
              key: Key('dev-voice-${s.id}'),
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      '${switch (s.kind) {
                        'guide' => s.isLive ? l.devVoiceGuideLive : l.devVoiceGuideRealtime,
                        'audit' => l.devVoiceAuditLive,
                        _ => l.devVoiceAuditTurns,
                      }} · '
                      '${MaterialLocalizations.of(context).formatShortDate(s.startedAt.toLocal())} '
                      '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(s.startedAt.toLocal()))}',
                      style: theme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Flexible(
                    flex: 2,
                    child: Text(
                      textAlign: TextAlign.end,
                      '${_num(s.minutes)} ${l.devVoiceMinutes} · ${s.turns} ${l.devVoiceTurns} · ${_usd(s.cost)}'
                      '${s.backendCost == null ? '' : ' (${l.devVoiceOtherCall} ${_usdFine(s.backendCost)})'}'
                      '${s.otherCost == null ? '' : ' · ${switch (s.kind) {
                              'guide' => s.isLive ? l.devVoiceOnRealtime : l.devVoiceLive,
                              'audit' => l.devVoiceOnTurns,
                              _ => l.devVoiceLive,
                            }} ${_usd(s.otherCost)}'}',
                      style: theme.bodySmall?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// What the text agents' calls cost: all of them, per audit on each model,
/// by model and by agent.
class _LlmCosts extends StatelessWidget {
  const _LlmCosts({required this.llm, required this.error});

  final DevLlm? llm;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    final d = llm;
    if (d == null) {
      final e = error;
      return Center(
        child: e == null
            ? const CircularProgressIndicator()
            : Text(e is ApiException ? e.userMessage : '$e'),
      );
    }
    String name(DevLlmRow r) => '${r.provider} · ${r.model}';
    String tokens(DevLlmRow r) =>
        '${_num(r.avgInputTokens, 0)} → ${_num(r.avgOutputTokens, 0)} tok · ${_num(r.avgMs == null ? null : r.avgMs! / 1000)} s';
    return ListView(
      key: const Key('dev-llm'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      children: [
        Text(l.devLlmHint, style: theme.bodySmall?.copyWith(color: AppColors.textTertiary)),
        const SizedBox(height: AppSpacing.lg),
        _tiles(context, l.devLlmAll, [
          ('llm-calls', l.devLlmCalls, '${d.calls}'),
          ('llm-failed', l.devLlmFailed, '${d.failed}'),
          ('llm-cost', l.devVoiceCost, _usd(d.cost)),
          ('llm-per-call', l.devLlmPerCall, _usdFine(d.avgCost)),
          if (d.unpricedCalls > 0) ('llm-unpriced', l.devLlmUnpriced, '${d.unpricedCalls}'),
        ]),
        const SizedBox(height: AppSpacing.xl),
        if (d.calls == 0)
          Text(l.devNoLlm, style: theme.bodyMedium)
        else ...[
          _rows(context, l.devLlmPerAudit, 'audit', [
            for (final r in d.audits)
              (
                name(r),
                '${r.audits} ${l.devAudits} · ${_num(r.avgCalls)} ${l.devLlmCalls} · ${_usdFine(r.avgCost)}',
              ),
          ]),
          _rows(context, l.devLlmByModel, 'model', [
            for (final r in d.providers)
              (
                name(r),
                '${r.calls} ${l.devLlmCalls}${r.failed == 0 ? '' : ' (${r.failed} ${l.devLlmFailed})'} · '
                    '${tokens(r)} · ${_usd(r.cost)} · ${l.devLlmPerCall} ${_usdFine(r.avgCost)}',
              ),
          ]),
          _rows(context, l.devLlmByAgent, 'agent', [
            for (final r in d.agents)
              (
                '${r.agent} · ${r.model}',
                '${r.calls} ${l.devLlmCalls} · ${tokens(r)} · ${l.devLlmPerCall} ${_usdFine(r.avgCost)}',
              ),
          ]),
          _rows(context, l.devLlmAllOn, 'all', [for (final r in d.allOn) (name(r), _usd(r.cost))]),
        ],
      ],
    );
  }

  /// A titled list of `name … figures` lines, keyed `dev-llm-<key>-<index>`.
  Widget _rows(BuildContext context, String title, String key, List<(String, String)> rows) {
    final theme = Theme.of(context).textTheme;
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          for (final (i, (name, figures)) in rows.indexed)
            Padding(
              key: Key('dev-llm-$key-$i'),
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(name, style: theme.bodyMedium)),
                  const SizedBox(width: AppSpacing.md),
                  Flexible(
                    flex: 2,
                    child: Text(
                      figures,
                      textAlign: TextAlign.end,
                      style: theme.bodySmall?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The learner model: the ability after each audit as a line, the newest
/// audits with what each moved, the Auditor's two error rates, and the nodes
/// open to study with the chance of passing each.
class _Learner extends StatelessWidget {
  const _Learner({required this.learner, required this.error});

  final LearnerModel? learner;
  final Object? error;

  static const int recent = 10;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    final m = learner;
    if (m == null) {
      final e = error;
      return Center(
        child: e == null
            ? const CircularProgressIndicator()
            : Text(e is ApiException ? e.userMessage : '$e'),
      );
    }
    final steps = m.history.reversed.take(recent).toList(); // newest first
    return ListView(
      key: const Key('dev-learner'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      children: [
        Text(l.devLearnerOverTime, style: theme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        if (m.history.isEmpty)
          EmptyView(message: l.devNoAudits)
        else ...[
          LearnerChart(key: const Key('learner-chart'), history: m.history),
          const SizedBox(height: AppSpacing.md),
          Text.rich(
            key: const Key('learner-ability'),
            TextSpan(
              children: [
                TextSpan(text: '${l.devLearnerAbilityNow} '),
                TextSpan(
                  text: _signed(m.ability),
                  style: theme.titleSmall?.copyWith(color: AppColors.textPrimary),
                ),
                TextSpan(text: ' · ${m.history.length} ${l.devAudits}'),
              ],
            ),
            style: theme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(l.devLearnerRecent, style: theme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          for (final (i, s) in steps.indexed)
            Padding(
              key: Key('learner-step-$i'),
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(s.skillTitle, style: theme.bodyMedium)),
                      const SizedBox(width: AppSpacing.md),
                      if (s.passed)
                        StatusChip.success(l.auditPassed)
                      else
                        StatusChip.danger(l.auditFailed),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${formatLocal(s.createdAt, style: DateStyle.dateTime)} · '
                    '${l.devLearnerAbility} ${_signed(s.ability)} · '
                    '${l.devLearnerProgress} ${_pct(s.progress)}'
                    '${switch (s.agreement) {
                      final a? when a < 1 => ' · ${l.devLearnerAgreed(_pct(a))}',
                      _ => '',
                    }}',
                    style: theme.bodySmall?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.lg),
        KeyedSubtree(
          key: const Key('learner-judge'),
          child: _tiles(context, l.devLearnerJudge, prefix: 'learner-judge-', [
            ('false-fail', l.devLearnerFalseFail, _pct(m.judgeFalseFail)),
            ('false-pass', l.devLearnerFalsePass, _pct(m.judgeFalsePass)),
          ]),
        ),
        if (m.nodes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          Text(l.devLearnerNodes(_pct(m.targetChance)), style: theme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          for (final (i, n) in m.nodes.indexed)
            Padding(
              key: Key('learner-node-$i'),
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(child: Text(n.title, style: theme.bodyMedium)),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    _pct(n.chance),
                    style: theme.bodySmall?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.metrics});

  final DevMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final m = metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row(context, l.devJudging, [
          ('agreement', l.devAgreement, _pct(m.agreement)),
          ('kappa', l.devKappa, _num(m.kappa, 2)),
          ('too-strict', l.devTooStrict, '${m.tooStrict}'),
          ('too-lenient', l.devTooLenient, '${m.tooLenient}'),
          ('leaked', l.devLeaked, '${m.leaked}'),
          ('reviewed', l.devReviewed, '${m.reviewed}'),
        ]),
        const SizedBox(height: AppSpacing.lg),
        _row(context, l.devOverall, [
          ('finished', l.devAudits, '${m.finished}'),
          ('pass-rate', l.devPassRate, _pct(m.passRate)),
          ('avg-score', l.devAvgScore, _num(m.avgScore, 0)),
          ('gaps', l.devGapsPerFail, _num(m.avgGapsWhenFailed)),
          ('answers', l.devAnswers, _num(m.avgAnswers)),
          ('challenged', l.devChallenged, _pct(m.challengedRate)),
        ]),
      ],
    );
  }

  Widget _row(BuildContext context, String title, List<(String, String, String)> tiles) =>
      _tiles(context, title, tiles);
}

class _AuditCard extends StatelessWidget {
  const _AuditCard({
    required this.audit,
    required this.open,
    required this.onToggle,
    required this.onReview,
  });

  final DevAudit audit;
  final bool open;
  final VoidCallback onToggle;
  final void Function(AuditReview? review, bool leaked) onReview;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    final a = audit;
    // The one way this verdict can be wrong.
    final wrong = a.passed ? AuditReview.tooLenient : AuditReview.tooStrict;
    return DecoratedBox(
      key: Key('dev-audit-${a.id}'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(a.skillTitle, style: theme.titleSmall)),
                if (a.passed)
                  StatusChip.success(l.auditPassed)
                else
                  StatusChip.danger(l.auditFailed),
                const SizedBox(width: AppSpacing.sm),
                Text('${a.score ?? '—'} ${l.pointsUnit}', style: theme.labelMedium),
              ],
            ),
            if (a.comment case final comment? when comment.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(comment, style: theme.bodyMedium),
              ),
            if (a.gaps.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                l.whatWasMissing,
                style: theme.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
              for (final g in a.gaps) Text('· $g', style: theme.bodySmall),
            ],
            if (open) ...[
              const SizedBox(height: AppSpacing.md),
              for (final t in a.turns)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: t.isUser ? '› ' : '« ',
                          style: const TextStyle(color: AppColors.textTertiary),
                        ),
                        TextSpan(text: t.content),
                      ],
                    ),
                    style: theme.bodySmall?.copyWith(
                      color: t.isUser ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  key: Key('dev-review-right-${a.id}'),
                  label: Text(l.devRight),
                  selected: a.review == AuditReview.right,
                  onSelected: (on) => onReview(on ? AuditReview.right : null, a.leaked),
                ),
                ChoiceChip(
                  key: Key('dev-review-wrong-${a.id}'),
                  label: Text(a.passed ? l.devTooLenient : l.devTooStrict),
                  selected: a.review == wrong,
                  onSelected: (on) => onReview(on ? wrong : null, a.leaked),
                ),
                FilterChip(
                  key: Key('dev-leak-${a.id}'),
                  label: Text(l.devGaveAnswer),
                  selected: a.leaked,
                  // A leak is part of a review: pick right or wrong first.
                  onSelected: a.review == null ? null : (on) => onReview(a.review, on),
                ),
                TextButton(
                  key: Key('dev-transcript-${a.id}'),
                  onPressed: onToggle,
                  child: Text(l.devTranscript),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
