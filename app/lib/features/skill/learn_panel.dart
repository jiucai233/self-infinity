import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api.dart';
import '../../api/api_exception.dart';
import '../../api/models.dart';
import '../../app/app_state.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../widgets/widgets.dart';

/// “Learn first”: what there is to study before taking the node on, and the
/// player's own notes. No tutoring, no new LLM call unless `Find material` is
/// tapped (then the Material Finder, on what was missed).
///
/// In order, each part only when it has something: what the node covers, its
/// knowledge points (what held, what was missed and why), the lesson cards
/// its failed audits made, the materials (one row per link, paged with `>`,
/// then the course source; `Find material` when something was missed), and
/// last the notes ([NodeNotes]).
///
/// On a wide screen it is the card under the node card; on a phone it is what
/// the `Learn first` row opens, in a sheet ([framed] false).
class LearnPanel extends StatefulWidget {
  const LearnPanel({
    super.key,
    required this.overview,
    this.points = const [],
    this.lessons = const [],
    this.framed = true,
  });

  final SkillOverview overview;

  /// The node's knowledge points, when it is a leaf that has them.
  final List<SkillPoint> points;

  /// The lesson cards made from this node's audits.
  final List<Principle> lessons;

  /// False in the phone's sheet: the same contents without the card.
  final bool framed;

  @override
  State<LearnPanel> createState() => _LearnPanelState();
}

class _LearnPanelState extends State<LearnPanel> {
  static const int pageSize = 4;
  int _page = 0;

  /// What `Find material` brought back, shown first (the overview catches up
  /// on its next load).
  List<SearchItem> _found = const [];
  bool _searching = false;
  bool _searchFailed = false;
  bool _foundNothing = false;

  List<SearchItem> get _links {
    final seen = <String>{};
    return [
      for (final item in _found)
        if (seen.add(item.url)) item,
      for (final plan in widget.overview.materials)
        for (final item in plan.items)
          if (seen.add(item.url)) item,
    ];
  }

  /// What to search for: the points missed (with what was wrong), else the
  /// newest lesson card's misconception; null when nothing was missed (the
  /// search is a remedy for a gap, not a general one).
  ({String? gap, int? misconceptionId})? get _target {
    final missed = [
      for (final p in widget.points)
        if (p.ok == false)
          (p.note?.trim().isNotEmpty ?? false) ? '${p.title}: ${p.note!.trim()}' : p.title,
    ];
    if (missed.isNotEmpty) return (gap: missed.join('; '), misconceptionId: null);
    final lesson = widget.lessons.where((p) => p.hasMisconception).firstOrNull;
    if (lesson != null) return (gap: null, misconceptionId: lesson.id);
    return null;
  }

  Future<void> _find(({String? gap, int? misconceptionId}) target) async {
    if (_searching) return;
    final api = context.read<SelfInfinityApi>();
    final app = context.read<AppState>();
    setState(() {
      _searching = true;
      _searchFailed = false;
      _foundNothing = false;
    });
    try {
      final plan = await api.createSearchPlan(
        widget.overview.skill.id,
        gap: target.gap,
        misconceptionId: target.misconceptionId,
      );
      if (!mounted) return;
      setState(() {
        _found = plan.items;
        _foundNothing = plan.items.isEmpty;
        _searching = false;
        _page = 0;
      });
      app.markDataChanged();
    } on Object {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final l = context.l10n;
    final node = widget.overview.skill;
    final course = widget.overview.course;
    final links = _links;
    final pages = (links.length / pageSize).ceil();
    final page = _page.clamp(0, pages == 0 ? 0 : pages - 1);
    final shown = links.skip(page * pageSize).take(pageSize).toList();
    final target = _target;
    final label = theme.labelMedium;
    final muted = theme.bodySmall?.copyWith(color: AppColors.textTertiary);
    List<Widget> section(String title, {String? hint}) => [
      const SizedBox(height: AppSpacing.lg),
      const Divider(),
      const SizedBox(height: AppSpacing.md),
      Text(title, style: label),
      if (hint != null) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(keepAll(hint), style: muted),
      ],
      const SizedBox(height: AppSpacing.sm),
    ];
    return DecoratedBox(
      key: const Key('skill-contents'),
      decoration: !widget.framed
          ? const BoxDecoration()
          : BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.cardBorder,
              border: Border.all(color: AppColors.outline),
            ),
      child: Padding(
        padding: EdgeInsets.all(widget.framed ? AppSpacing.xl : 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.learnFirst,
              key: const Key('skill-learn-title'),
              style: widget.framed ? theme.titleMedium : theme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              node.description.isEmpty ? l.noDescriptionYet : node.description,
              key: const Key('skill-description'),
              style: theme.bodyLarge,
            ),
            if (widget.points.isNotEmpty) ...[
              ...section(l.knowledgePoints, hint: l.knowledgePointsHint),
              for (final (i, point) in widget.points.indexed)
                PointRow(key: Key('skill-point-$i'), point: point),
            ],
            if (widget.lessons.isNotEmpty) ...[
              ...section(l.lessonCards),
              for (final p in widget.lessons)
                _LessonRow(key: Key('skill-lesson-${p.id}'), lesson: p),
            ],
            if (shown.isNotEmpty || course.hasSource || target != null) ...section(l.resources),
            for (final item in shown)
              _MaterialRow(
                key: ValueKey('link-${item.url}'),
                title: item.title.isEmpty ? displayDomain(item.url) : item.title,
                subtitle: displayDomain(item.url),
                onTap: () => openExternalUrl(context, item.url),
              ),
            if (course.hasSource)
              _MaterialRow(
                key: const Key('course-source'),
                title: l.sourceLabel(course.sourceCourse!),
                subtitle: course.hasSourceLink
                    ? displayDomain(course.sourceUrl!)
                    : l.uploadedCourseMaterial,
                icon: Icons.menu_book_outlined,
                onTap: course.hasSourceLink
                    ? () => openExternalUrl(context, course.sourceUrl!)
                    : null,
              ),
            if (pages > 1)
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (page > 0)
                      IconButton(
                        key: const Key('links-prev'),
                        tooltip: l.previous,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chevron_left_rounded),
                        onPressed: () => setState(() => _page = page - 1),
                      ),
                    Text('${page + 1}/$pages', style: theme.bodySmall),
                    if (page < pages - 1)
                      IconButton(
                        key: const Key('links-next'),
                        tooltip: l.next,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chevron_right_rounded),
                        onPressed: () => setState(() => _page = page + 1),
                      ),
                  ],
                ),
              ),
            if (target != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('learn-find-materials'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                  icon: _searching
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search_rounded, size: 18),
                  label: Text(l.findMaterials),
                  onPressed: _searching ? null : () => unawaited(_find(target)),
                ),
              ),
              if (_searchFailed || _foundNothing)
                Text(
                  _searchFailed ? l.materialsFailed : l.materialsNone,
                  key: const Key('learn-materials-note'),
                  style: muted,
                ),
            ],
            ...section(l.myNotes, hint: l.notesPrivate),
            NodeNotes(key: ValueKey('notes-${node.id}'), skillId: node.id),
          ],
        ),
      ),
    );
  }
}

/// The player's own notes on one node, newest first: a field to write one
/// (`Save note` shows once there is text), then the notes. Tapping a note
/// edits it in place; the bin deletes it after asking. Plain text.
class NodeNotes extends StatefulWidget {
  const NodeNotes({super.key, required this.skillId});

  final int skillId;

  @override
  State<NodeNotes> createState() => _NodeNotesState();
}

class _NodeNotesState extends State<NodeNotes> {
  late final SelfInfinityApi _api = context.read<SelfInfinityApi>();
  final TextEditingController _input = TextEditingController();
  final TextEditingController _edit = TextEditingController();

  List<NodeNote>? _notes;
  bool _loadFailed = false;
  bool _saving = false;
  String? _problem;

  /// The note being edited in place.
  int? _editing;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _input.dispose();
    _edit.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final notes = await _api.listNodeNotes(widget.skillId);
      if (mounted) setState(() => _notes = notes);
    } on Object {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  String _failure(Object e) => e is ApiException && e.statusCode == 400
      ? (e.serverMessage ?? context.l10n.noteSaveFailed)
      : context.l10n.noteSaveFailed;

  Future<void> _add() async {
    final text = _input.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      final note = await _api.createNodeNote(widget.skillId, text);
      if (!mounted) return;
      _input.clear();
      setState(() {
        _notes = [note, ...?_notes];
        _saving = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _problem = _failure(e);
      });
    }
  }

  void _startEdit(NodeNote note) {
    if (_saving) return;
    _edit.text = note.content;
    setState(() {
      _editing = note.id;
      _problem = null;
    });
  }

  Future<void> _saveEdit(NodeNote note) async {
    final text = _edit.text.trim();
    if (text.isEmpty || _saving) return;
    if (text == note.content) {
      setState(() => _editing = null);
      return;
    }
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      final saved = await _api.updateNodeNote(note.id, text);
      if (!mounted) return;
      setState(() {
        _notes = [
          for (final n in _notes ?? const <NodeNote>[]) n.id == saved.id ? saved : n,
        ];
        _editing = null;
        _saving = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _problem = _failure(e);
      });
    }
  }

  Future<void> _delete(NodeNote note) async {
    final l = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        key: const Key('note-delete-dialog'),
        title: Text(l.noteDeleteTitle),
        content: SizedBox(
          width: 380,
          child: Text(note.content, maxLines: 4, overflow: TextOverflow.ellipsis),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: Text(l.cancel)),
          TextButton(
            key: const Key('note-delete-confirm'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _api.deleteNodeNote(note.id);
      if (!mounted) return;
      setState(() {
        _notes = [
          for (final n in _notes ?? const <NodeNote>[])
            if (n.id != note.id) n,
        ];
        if (_editing == note.id) _editing = null;
      });
    } on Object catch (e) {
      if (mounted) showToast(context, ErrorView.messageFor(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context).textTheme;
    final notes = _notes;
    return Column(
      key: const Key('node-notes'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A plain field, not the Composer: the page's input bar already has
        // the one voice key.
        TextField(
          key: const Key('note-input'),
          controller: _input,
          minLines: 2,
          maxLines: 8,
          maxLength: NodeNote.maxLength,
          buildCounter: _noCounter,
          keyboardType: TextInputType.multiline,
          style: theme.bodyMedium,
          decoration: InputDecoration(hintText: l.noteHint, isDense: true),
        ),
        // Follows the field: nothing to save while it is empty.
        ListenableBuilder(
          listenable: _input,
          builder: (context, _) => _input.text.trim().isEmpty
              ? const SizedBox.shrink()
              : Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: OutlinedButton(
                      key: const Key('note-add'),
                      onPressed: _saving ? null : () => unawaited(_add()),
                      child: Text(l.noteAdd),
                    ),
                  ),
                ),
        ),
        if (_problem case final problem?) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            problem,
            key: const Key('note-problem'),
            style: theme.bodySmall?.copyWith(color: AppColors.danger),
          ),
        ],
        if (_loadFailed)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text(
              l.notesLoadFailed,
              key: const Key('notes-load-failed'),
              style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
        if (notes != null && notes.isNotEmpty) const SizedBox(height: AppSpacing.md),
        for (final note in notes ?? const <NodeNote>[])
          note.id == _editing
              ? _editor(note)
              : _NoteRow(
                  key: Key('note-${note.id}'),
                  note: note,
                  onTap: () => _startEdit(note),
                  onDelete: () => unawaited(_delete(note)),
                ),
      ],
    );
  }

  /// A note being edited: the text in a field, `Cancel` and `Save` under it.
  Widget _editor(NodeNote note) {
    final l = context.l10n;
    return Padding(
      key: Key('note-editor-${note.id}'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('note-edit-field'),
            controller: _edit,
            autofocus: true,
            minLines: 2,
            maxLines: 12,
            maxLength: NodeNote.maxLength,
            buildCounter: _noCounter,
            keyboardType: TextInputType.multiline,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: const InputDecoration(isDense: true),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: const Key('note-edit-cancel'),
                onPressed: _saving ? null : () => setState(() => _editing = null),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                child: Text(l.cancel),
              ),
              const SizedBox(width: AppSpacing.xs),
              ListenableBuilder(
                listenable: _edit,
                builder: (context, _) => OutlinedButton(
                  key: const Key('note-edit-save'),
                  onPressed: _saving || _edit.text.trim().isEmpty
                      ? null
                      : () => unawaited(_saveEdit(note)),
                  child: Text(l.noteSave),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Widget? _noCounter(
  BuildContext _, {
  required int currentLength,
  required bool isFocused,
  int? maxLength,
}) => null;

/// One note: its text, the day under it (`· edited` once rewritten), a quiet
/// bin on the right. The text opens it for editing.
class _NoteRow extends StatelessWidget {
  const _NoteRow({super.key, required this.note, required this.onTap, required this.onDelete});

  final NodeNote note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final l = context.l10n;
    final edited = note.updatedAt.isAfter(note.createdAt);
    final day = formatLocal(note.createdAt, style: DateStyle.monthDay);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: InkWell(
            key: Key('note-open-${note.id}'),
            onTap: onTap,
            borderRadius: AppRadius.chipBorder,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.sm,
                horizontal: AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note.content, key: const Key('note-text'), style: theme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    edited ? '$day · ${l.noteEdited}' : day,
                    style: theme.bodySmall?.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          key: Key('note-delete-${note.id}'),
          tooltip: l.delete,
          visualDensity: VisualDensity.compact,
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

/// A lesson card made from one of the node's failed audits: its title, and
/// the misconception it named.
class _LessonRow extends StatelessWidget {
  const _LessonRow({super.key, required this.lesson});

  final Principle lesson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lesson.title, style: theme.labelLarge),
          if (lesson.misconception case final m? when m.isNotEmpty)
            Text(m, style: theme.bodySmall?.copyWith(color: AppColors.danger)),
        ],
      ),
    );
  }
}

/// The first letter or digit of [title] in capitals (`“Functions” …` -> `F`); the
/// favicon placeholder of a material row.
String firstLetterOf(String title) {
  final match = RegExp(r'[\p{L}\p{N}]', unicode: true).firstMatch(title);
  return match == null ? '·' : match.group(0)!.toUpperCase();
}

/// One material: a round badge with the first letter of the title (the place
/// of the site's favicon), the title and the site; the whole row opens the
/// link. Without [onTap] (a course made from an uploaded file) it is plain.
class _MaterialRow extends StatelessWidget {
  const _MaterialRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
    this.onTap,
  });

  final String title;
  final String subtitle;

  /// Shown in the badge instead of the first letter.
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final letter = firstLetterOf(title);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
      child: Row(
        children: [
          DecoratedBox(
            key: const Key('material-badge'),
            decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
            child: SizedBox.square(
              dimension: 32,
              child: Center(
                child: icon != null
                    ? Icon(icon, size: 18, color: AppColors.primary)
                    : Text(letter, style: theme.labelLarge?.copyWith(color: AppColors.primary)),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  key: const Key('material-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  subtitle,
                  key: const Key('material-domain'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodySmall,
                ),
              ],
            ),
          ),
          if (onTap != null)
            const Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.textTertiary),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, borderRadius: AppRadius.chipBorder, child: row);
  }
}

/// Opens [LearnPanel] in a sheet over a phone's node page: most of the
/// height, dragged down to close, the keyboard pushing the notes up.
Future<void> showLearnSheet(
  BuildContext context, {
  required SkillOverview overview,
  required List<SkillPoint> points,
  required List<Principle> lessons,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // Over the tab bar too, so the notes field is never under it.
  useRootNavigator: true,
  showDragHandle: true,
  backgroundColor: AppColors.surface,
  builder: (sheet) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
    child: DraggableScrollableSheet(
      key: const Key('learn-sheet'),
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.4,
      maxChildSize: 1,
      builder: (context, controller) => SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
        child: LearnPanel(overview: overview, points: points, lessons: lessons, framed: false),
      ),
    ),
  ),
);
