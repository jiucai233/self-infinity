import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';

/// The dialogs behind the `⋯` menu of a node page: editing the course by
/// hand (contract #41–#45). Each only asks; the page calls the API.

/// A node's name and what it covers, as the player typed them.
typedef NodeText = ({String title, String description});

/// Asks for a node's name and what it covers: [initial] to edit one, none to
/// name a new part. Null when cancelled.
Future<NodeText?> askNodeText(
  BuildContext context, {
  required String dialogTitle,
  NodeText? initial,
}) => showDialog<NodeText>(
  context: context,
  builder: (_) => _NodeTextDialog(dialogTitle: dialogTitle, initial: initial),
);

class _NodeTextDialog extends StatefulWidget {
  const _NodeTextDialog({required this.dialogTitle, this.initial});

  final String dialogTitle;
  final NodeText? initial;

  @override
  State<_NodeTextDialog> createState() => _NodeTextDialogState();
}

class _NodeTextDialogState extends State<_NodeTextDialog> {
  late final TextEditingController _title = TextEditingController(text: widget.initial?.title ?? '');
  late final TextEditingController _description = TextEditingController(
    text: widget.initial?.description ?? '',
  );

  /// The server's limits (`SkillEditIn`).
  static const int titleMax = 48;
  static const int descriptionMax = 400;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop((title: title, description: _description.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      key: const Key('node-text-dialog'),
      title: Text(widget.dialogTitle),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('node-title'),
              controller: _title,
              autofocus: true,
              maxLength: titleMax,
              decoration: InputDecoration(labelText: l.nodeTitleLabel),
              onSubmitted: (_) => _save(),
            ),
            TextField(
              key: const Key('node-description'),
              controller: _description,
              maxLength: descriptionMax,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: l.nodeDescriptionLabel),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancel)),
        TextButton(key: const Key('node-text-save'), onPressed: _save, child: Text(l.nodeSave)),
      ],
    );
  }
}

/// What a node is linked to: a course, or nothing (a plain node).
sealed class LinkChoice {
  const LinkChoice();
}

class LinkToCourse extends LinkChoice {
  const LinkToCourse(this.courseId);

  final int courseId;
}

class Unlink extends LinkChoice {
  const Unlink();
}

/// Asks which of the player's other [courses] (with their names) the node
/// [title] is. Null when cancelled.
Future<LinkChoice?> askLinkedCourse(
  BuildContext context, {
  required String title,
  required List<({int id, String name})> courses,
  int? current,
}) {
  final l = context.l10n;
  return showDialog<LinkChoice>(
    context: context,
    builder: (dialog) => AlertDialog(
      key: const Key('node-link-dialog'),
      title: Text(l.nodeLinkTitle(title)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.nodeLinkBody, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            if (courses.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text(l.nodeLinkNoCourses),
              ),
            for (final c in courses)
              ListTile(
                key: Key('node-link-course-${c.id}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  c.id == current ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  size: 20,
                ),
                title: Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.of(dialog).pop(LinkToCourse(c.id)),
              ),
            if (current != null)
              ListTile(
                key: const Key('node-link-none'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link_off_rounded, size: 20),
                title: Text(l.nodeLinkNone),
                onTap: () => Navigator.of(dialog).pop(const Unlink()),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(dialog).pop(), child: Text(l.cancel))],
    ),
  );
}

/// Where a syllabus comes from.
enum SyllabusSource { search, upload }

/// Asks how to update [course] from a syllabus. Null when cancelled.
Future<SyllabusSource?> askSyllabusSource(BuildContext context, {required String course}) {
  final l = context.l10n;
  return showDialog<SyllabusSource>(
    context: context,
    builder: (dialog) => AlertDialog(
      key: const Key('node-syllabus-dialog'),
      title: Text(l.nodeApplySyllabusTitle(course)),
      content: SizedBox(width: 380, child: Text(l.nodeApplySyllabusBody)),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialog).pop(), child: Text(l.cancel)),
        TextButton(
          key: const Key('node-syllabus-search'),
          onPressed: () => Navigator.of(dialog).pop(SyllabusSource.search),
          child: Text(l.nodeSyllabusSearch),
        ),
        FilledButton(
          key: const Key('node-syllabus-upload'),
          onPressed: () => Navigator.of(dialog).pop(SyllabusSource.upload),
          child: Text(l.nodeSyllabusUpload),
        ),
      ],
    ),
  );
}

/// Asks before deleting the node [title] and what is only under it.
Future<bool> confirmDeleteNode(BuildContext context, {required String title}) async {
  final l = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      key: const Key('node-delete-dialog'),
      title: Text(l.nodeDeleteTitle(title)),
      content: SizedBox(width: 380, child: Text(l.nodeDeleteBody)),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: Text(l.cancel)),
        TextButton(
          key: const Key('node-delete-confirm'),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          onPressed: () => Navigator.of(dialog).pop(true),
          child: Text(l.delete),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// The node's parts in [map] (contains children).
bool hasParts(SkillNode node, CourseMap map) =>
    map.edges.any((e) => e.kind == SkillEdgeKind.contains && e.fromId == node.id);

/// Whether [node] is the root of [map].
bool isRootOf(SkillNode node, CourseMap map) =>
    !map.edges.any((e) => e.kind == SkillEdgeKind.contains && e.toId == node.id);
