import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/api_exception.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';

/// How long an audit is (contract #53): short, standard or thorough, saved for
/// the account. Opens from the ◎ menu.
Future<void> showAuditLengthDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _AuditLengthDialog(),
);

class _AuditLengthDialog extends StatefulWidget {
  const _AuditLengthDialog();

  @override
  State<_AuditLengthDialog> createState() => _AuditLengthDialogState();
}

class _AuditLengthDialogState extends State<_AuditLengthDialog> {
  late final SelfInfinityApi _api = context.read<SelfInfinityApi>();
  String? _current;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final length = await _api.getAuditLength();
      if (mounted) setState(() => _current = length);
    } on Object {
      // nothing selected: a choice still saves
    }
  }

  Future<void> _choose(String length) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final saved = await _api.setAuditLength(length);
      if (!mounted) return;
      setState(() => _current = saved);
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showToast(context, e.userMessage);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    final choices = [
      ('short', l.auditLengthShort, l.auditLengthShortHint),
      ('standard', l.auditLengthStandard, l.auditLengthStandardHint),
      ('thorough', l.auditLengthThorough, l.auditLengthThoroughHint),
    ];
    return SimpleDialog(
      key: const Key('audit-length-dialog'),
      title: Text(l.auditLengthTitle),
      children: [
        for (final (id, name, hint) in choices)
          SimpleDialogOption(
            key: Key('audit-length-$id'),
            onPressed: () => unawaited(_choose(id)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: theme.titleSmall),
                      Text(hint, style: theme.bodySmall?.copyWith(color: AppColors.textTertiary)),
                    ],
                  ),
                ),
                if (_current == id)
                  const Icon(
                    Icons.check_rounded,
                    key: Key('audit-length-selected'),
                    size: 18,
                    color: AppColors.textPrimary,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
