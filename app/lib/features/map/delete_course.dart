import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/api_exception.dart';
import '../../app/app_state.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';

/// Asks before deleting a course, with the choice to delete its [nodeCount]
/// nodes and their attempts and lesson cards too (unchecked, they are kept
/// with the course out of sight), then deletes it. True when it was deleted.
/// Used by the course card on the life tree and the `⋯` menu of a node page.
Future<bool> confirmDeleteCourse(
  BuildContext context, {
  required int courseId,
  required String courseName,
  required int nodeCount,
}) async {
  final api = context.read<SelfInfinityApi>();
  final appState = context.read<AppState>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l = context.l10n;
  var deleteNodes = false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setDialog) => AlertDialog(
        key: const Key('course-delete-dialog'),
        title: Text(l.deleteCourseTitle(courseName)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.deleteCourseBody),
            const SizedBox(height: AppSpacing.md),
            CheckboxListTile(
              key: const Key('course-delete-nodes'),
              value: deleteNodes,
              onChanged: (v) => setDialog(() => deleteNodes = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l.deleteCourseNodes(nodeCount)),
              subtitle: Text(l.deleteCourseKeep),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: Text(l.cancel)),
          TextButton(
            key: const Key('course-delete-confirm'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(l.delete),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true) return false;
  try {
    await api.deleteCourse(courseId, deleteNodes: deleteNodes);
    appState.markDataChanged();
    return true;
  } on ApiException catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.userMessage)));
    return false;
  }
}
