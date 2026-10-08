import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/api_exception.dart';
import '../../api/models.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../widgets/status_chip.dart';

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
/// what live voice costs, next to what GPT-Live would (contract #37).
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
  bool _voiceTab = false;
  DevVoice? _voice;
  Object? _voiceError;

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

  void _showVoice(bool on) {
    setState(() => _voiceTab = on);
    if (on && _voice == null) unawaited(_loadVoice());
  }

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
                SegmentedButton<bool>(
                  key: const Key('dev-tabs'),
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(l.devTabAudits, key: const Key('dev-tab-audits')),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(l.devTabVoice, key: const Key('dev-tab-voice')),
                    ),
                  ],
                  selected: {_voiceTab},
                  onSelectionChanged: (s) => _showVoice(s.first),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  key: const Key('dev-refresh'),
                  tooltip: l.devRefresh,
                  onPressed: () => unawaited(_voiceTab ? _loadVoice() : _load()),
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
          Expanded(
            child: _voiceTab
                ? _VoiceCosts(voice: _voice, error: _voiceError)
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

String _pct(double? v) => v == null ? '—' : '${(v * 100).round()}%';
String _usd(double? v) =>
    v == null ? '—' : '\$${v < 1 ? v.toStringAsFixed(3) : v.toStringAsFixed(2)}';
String _num(double? v, [int digits = 1]) => v == null ? '—' : v.toStringAsFixed(digits);

/// A titled row of number tiles, keyed `dev-metric-<key>`.
Widget _tiles(BuildContext context, String title, List<(String, String, String)> tiles) {
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
                  Text(value, key: Key('dev-metric-$key'), style: theme.headlineMedium),
                ],
              ),
            ),
        ],
      ),
    ],
  );
}

/// What live voice costs: the realtime Guide next to GPT-Live, the audits'
/// transcription, and every session.
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
          ('guide-live', l.devVoiceLive, _usd(v.guideLiveEquivalent)),
          ('guide-per-minute', l.devVoicePerMinute, _usd(v.guideCostPerMinute)),
          ('guide-cached', l.devVoiceCached, _pct(v.guideCachedShare)),
        ]),
        const SizedBox(height: AppSpacing.lg),
        _tiles(context, l.devVoiceAudits, [
          ('audit-sessions', l.devVoiceSessions, '${v.auditSessions}'),
          ('audit-minutes', l.devVoiceMinutes, _num(v.auditMinutes)),
          ('audit-cost', l.devVoiceCost, _usd(v.auditCost)),
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
                children: [
                  Expanded(
                    child: Text(
                      '${s.kind == 'guide' ? l.devVoiceGuide : l.devVoiceAudits} · '
                      '${MaterialLocalizations.of(context).formatShortDate(s.startedAt.toLocal())} '
                      '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(s.startedAt.toLocal()))}',
                      style: theme.bodyMedium,
                    ),
                  ),
                  Text(
                    '${_num(s.minutes)} ${l.devVoiceMinutes} · ${s.turns} ${l.devVoiceTurns} · ${_usd(s.cost)}'
                    '${s.liveEquivalent == null ? '' : ' · ${l.devVoiceLive} ${_usd(s.liveEquivalent)}'}',
                    style: theme.bodySmall?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
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
