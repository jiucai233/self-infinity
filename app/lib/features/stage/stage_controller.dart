import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api/api.dart';
import '../../api/life_tree.dart';
import '../../api/models.dart';
import '../../app/app_state.dart';

/// What the left panel, the entering scene and the map share across scenes:
/// the character stats (briefing facts), today's check-in, the newest course,
/// the life tree (every course under its main quest), the main quests and the
/// daily quests (the current study plan, with which of its nodes are done).
///
/// It reloads whenever [AppState.markDataChanged] is called.
class StageController extends ChangeNotifier {
  StageController({required this.api, required this.appState, DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc()) {
    _revision = appState.dataRevision;
    appState.addListener(_onAppState);
    unawaited(refresh());
  }

  final SelfInfinityApi api;
  final AppState appState;
  final DateTime Function() _clock;

  late int _revision;
  int _token = 0;
  bool _disposed = false;

  ProfileFacts? _facts;
  DailyCheckIn? _today;
  CourseMap? _courseMap;
  StudyPlan? _plan;
  List<Goal> _goals = const [];
  List<CourseMap> _maps = const [];
  List<AuditSummary> _audits = const [];
  List<Principle> _lessons = const [];
  LifeTree _tree = LifeTree.build();
  Set<int> _doneToday = const {};
  bool _loaded = false;

  /// The briefing facts (null until loaded or when the call failed).
  ProfileFacts? get facts => _facts;

  /// Today's (KST) check-in, or null.
  DailyCheckIn? get todayCheckIn => _today;

  /// The map of the newest course, or null when there is no course.
  CourseMap? get courseMap => _courseMap;

  /// Every course, under its main quest (the `You` label is set by the
  /// widgets from the profile). Empty (only you) until loaded.
  LifeTree get lifeTree => _tree;

  /// The main quests, oldest first.
  List<Goal> get goals => _goals;

  /// Every course map, newest course first.
  List<CourseMap> get courseMaps => _maps;

  /// The latest 100 audits of all courses, newest first.
  List<AuditSummary> get audits => _audits;

  /// Every lesson card, newest first.
  List<Principle> get lessons => _lessons;

  /// The current study plan (GET /plan/current), or null.
  StudyPlan? get plan => _plan;

  /// Whether the daily quest [step] is done: its node is mastered or was
  /// audited (finished) today, KST.
  bool isQuestDone(PlanStep step) => _doneToday.contains(step.skillId);

  /// Whether the first load finished.
  bool get loaded => _loaded;

  void _onAppState() {
    if (appState.dataRevision == _revision) return;
    _revision = appState.dataRevision;
    unawaited(refresh());
  }

  /// Reloads facts, today's check-in and the newest course. A failing call
  /// only leaves its part empty.
  Future<void> refresh() async {
    final token = ++_token;
    final results = await Future.wait<Object?>([
      _safe<Briefing>(api.getBriefing()),
      _safe<DailyCheckIn?>(api.getTodayCheckIn()),
      _safe<List<CourseMap>>(_loadCourseMaps()),
      _safe<StudyPlan?>(api.getCurrentPlan()),
      _safe<List<AuditSummary>>(api.listAudits(limit: 100)),
      _safe<List<SkillNode>>(api.listSkills()),
      _safe<List<Goal>>(api.listGoals()),
      _safe<List<Principle>>(api.listPrinciples()),
    ]);
    if (_disposed || token != _token) return;
    _facts = (results[0] as Briefing?)?.facts ?? _facts;
    _today = results[1] as DailyCheckIn?;
    _maps = (results[2] as List<CourseMap>?) ?? _maps;
    _courseMap = _maps.firstOrNull;
    _plan = results[3] as StudyPlan?;
    _audits = (results[4] as List<AuditSummary>?) ?? const [];
    _goals = (results[6] as List<Goal>?) ?? _goals;
    _lessons = (results[7] as List<Principle>?) ?? _lessons;
    _tree = LifeTree.build(goals: _goals, maps: _maps, audits: _audits, lessons: _lessons.length);
    _doneToday = _questsDone(
      _plan,
      _audits,
      (results[5] as List<SkillNode>?) ?? const [],
    );
    _loaded = true;
    notifyListeners();
  }

  Set<int> _questsDone(StudyPlan? plan, List<AuditSummary> audits, List<SkillNode> skills) {
    if (plan == null) return const {};
    final today = formatKstDate(_clock());
    final mastered = {
      for (final n in skills)
        if (n.isMastered) n.id,
    };
    final audited = {
      for (final a in audits)
        if (a.status != AuditStatus.active && formatKstDate(a.createdAt) == today) a.skillId,
    };
    return {
      for (final step in plan.steps)
        if (mastered.contains(step.skillId) || audited.contains(step.skillId)) step.skillId,
    };
  }

  /// Newest course first.
  Future<List<CourseMap>> _loadCourseMaps() async {
    final courses = await api.listCourses();
    return Future.wait([for (final c in courses) api.getCourseMap(c.id)]);
  }

  static Future<T?> _safe<T>(Future<T> future) async {
    try {
      return await future;
    } on Object {
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    appState.removeListener(_onAppState);
    super.dispose();
  }
}
