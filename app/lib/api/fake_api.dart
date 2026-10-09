/// An in-memory [SelfInfinityApi] that needs no backend.
///
/// It follows the offline demo script of `docs/api-contract.md` Section 4 and
/// the state rules of the real backend, so the UI behaves the same with or
/// without a server. Select it at run time with `--dart-define=USE_FAKE_API=true`.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../voice/live_link.dart';
import 'api.dart';
import 'api_exception.dart';
import 'graph_utils.dart';
import 'models.dart';
import 'reflection_prompts.dart';

/// Deterministic in-memory backend.
///
/// ```dart
/// final api = FakeApiClient(latency: Duration.zero); // tests
/// final demo = FakeApiClient();                       // 300 ms per call
/// ```
///
/// ### Behaviour (contract Section 4 and the state rules)
/// * **Courses**: a topic containing `math` (case-insensitive; Korean `수학` is
///   still accepted as a fallback) yields the 12-node math course (any
///   settings); with `searchSyllabus` it is based on
///   `High School Mathematics Curriculum (Ministry of Education)`. A topic with
///   `vision` yields a course in layers: `Image Features` broken down,
///   `Geometric Vision` and `Visual Recognition` left `unexpanded`
///   ([expandSkill] gives each three parts, `{title} 1`–`3`). Any other topic
///   yields a generic 10-node course. Settings are validated like the server
///   does (422).
/// * **Unlocking** (`learningOrder`: parts before what contains them, the root
///   last): the root's children are chapters, each with one `available` node,
///   its first one not mastered; the root opens when every chapter is done.
///   Passing a node opens the next of its chapter.
/// * **Challenges** (`testOut`): on a branch, root or unexpanded node, locked
///   or not; scripted like an audit; a pass masters every node under it
///   (`testedOut`).
/// * **Audits**: the first answer gets a probe (it names the most recent
///   lesson from the Memory Retriever if there is one); later answers get a
///   verdict. Pass needs ≥ 80 characters in total and no `don't know` / `not sure`
///   (or Korean `모르`) in the latest answer. The Challenger overturns a pass with a total below 160
///   characters, at most once per session. Turn limit: concept 8, task 4,
///   doubled at night; a probe at the limit becomes a failing verdict with
///   score 0.
/// * **Memory Retriever**: up to 3 lessons, most recent first, taken from the
///   audited node itself, its direct contains/requires neighbours, or
///   principles linked (by the Linker) to those.
/// * **Reflection**: only for a failed session, only once. The Recorder and
///   Linker follow Section 4.4. Extra for demos: a reflection containing `contradict`
///   (or Korean `모순`)
///   also gets a `contradicts` link to the previous lesson, so that all five
///   graph edge kinds can be seen.
/// * **Check-ins**: only through the chat. Transcripts are parsed per Section
///   4.5; a second check-in on the same KST day replaces the first.
///   [checkInVoice], [narrate] and [generatePlan] are the pipelines behind the
///   chat; they are not part of the client API any more.
/// * **Briefing / search**: Section 4.6, computed from the state.
/// * **Stage UI** (contract Section 5): `sendChat` runs the Mock front desk
///   (keyword rules, first match wins; `teach me` also counts as a learn request) and the same pipelines as the other
///   calls; a failing pipeline is explained in a message, a failing front
///   desk throws (the user message stays in the history). With `uploadIds`
///   a `generate_course` / `none` intent builds the course from the files
///   (`source_course` = the file names, no URL). There are at most two
///   suggestions (how was today / continue learning). `uploadFile` accepts
///   `.pdf` / `.txt` / `.md` up to 4 MB. `ProfileFacts.xp` sums the rewards and
///   levels up every 5 cleared nodes (starts at level 1).
/// * **Life as a game** (contract Section 6): the profile (limits are 422s),
///   the journal, and the reflection suggestion — once checked in today, the
///   first suggestion is the reflection prompt of the current KST time window
///   (by the injected clock) until a journal entry with that prompt exists
///   today. `sendChat(reflectionPrompt: …)` runs no front desk: it saves the
///   prompt, the answer, a journal entry and `Noted. It's in your journal.`
///
/// ### Failure injection
/// [failNext] makes upcoming calls throw an [ApiException] **before** any
/// state changes (a failed call has no effect).
///
/// ### Test hooks
/// [debugMaxTurns], [debugSetMaxTurns] and [debugSetNodeType] expose or tweak
/// details the API hides.
class FakeApiClient implements SelfInfinityApi {
  /// Creates the fake.
  ///
  /// [latency] is awaited at the start of every call so that loading states
  /// are visible (default 300 ms). With `Duration.zero` no timer is used at
  /// all, which is what widget tests want. [clock] provides "now" (UTC);
  /// the default is the system clock.
  ///
  /// [onboarded] is the profile's tutorial flag at the start: `true` (the
  /// default, what most tests want) skips the first-run tutorial.
  FakeApiClient({
    this.latency = const Duration(milliseconds: 300),
    DateTime Function()? clock,
    bool onboarded = true,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()),
       _profile = Profile(onboarded: onboarded);

  /// Delay before every call.
  final Duration latency;

  final DateTime Function() _clock;

  /// The method names accepted by [failNext]'s `method` argument.
  static const Set<String> methodNames = {
    'generateCourse',
    'scoutCourse',
    'listCourses',
    'getCourseMap',
    'listSkills',
    'expandSkill',
    'editSkill',
    'deleteSkill',
    'addSkillPart',
    'linkSkill',
    'applySyllabus',
    'startAudit',
    'submitTurn',
    'submitReflection',
    'checkInVoice',
    'getBriefing',
    'narrate',
    'generatePlan',
    'createSearchPlan',
    'sendChat',
    'getChatHistory',
    'getChatSuggestions',
    'getTodayCheckIn',
    'getLife',
    'requestLifeAdvice',
    'editCheckIn',
    'addLifeFact',
    'editLifeFact',
    'deleteLifeFact',
    'getSkillOverview',
    'listAudits',
    'uploadFile',
    'getCurrentPlan',
    'getProfile',
    'updateProfile',
    'listJournal',
    'listPrinciples',
    'listGoals',
    'createGoal',
    'updateGoal',
    'deleteGoal',
    'deleteCourse',
    'getMe',
    'getDevAudits',
    'reviewAudit',
    'voiceAvailable',
    'guideVoice',
    'transcribe',
    'speech',
    'chatAct',
    'chatLog',
    'reportVoiceUsage',
    'getDevVoice',
  };

  // -- state ------------------------------------------------------------------

  final List<Course> _courses = [];
  final Map<int, SkillNode> _nodes = {}; // insertion order == id order
  final List<SkillEdge> _edges = []; // per course: contains edges, then requires
  final Map<int, _FakeAudit> _audits = {};
  final List<Principle> _principles = []; // creation order
  final List<_Link> _links = [];
  final Map<String, DailyCheckIn> _checkIns = {}; // by KST date
  final List<StudyPlan> _plans = [];
  final List<SearchPlan> _searchPlans = []; // creation order
  final List<ChatMessage> _chat = []; // creation order
  final Map<int, _FakeUpload> _uploads = {};
  Profile _profile;
  final List<JournalEntry> _journal = []; // creation order
  final List<Goal> _goals = []; // creation order
  String? _narrative;
  DateTime? _narrativeAt;

  int _nextCourseId = 1;
  int _nextNodeId = 1;
  int _nextAuditId = 1;
  int _nextPrincipleId = 1;
  int _nextPlanId = 1;
  int _nextSearchPlanId = 1;
  int _nextChatId = 1;
  int _nextUploadId = 1;
  int _nextJournalId = 1;
  int _nextGoalId = 1;

  // -- failure injection ------------------------------------------------------

  final List<_InjectedFailure> _failures = [];

  /// Makes the next [times] call(s) fail with an [ApiException].
  ///
  /// * [statusCode] defaults to 502; `null` simulates "no response"
  ///   (a network failure).
  /// * [message] is the server `detail`; it defaults to the contract message
  ///   of the endpoint. Pass e.g. `'skill is locked'` with `statusCode: 400`
  ///   to exercise the Korean translations.
  /// * [method] restricts the failure to one API method (see [methodNames]),
  ///   e.g. `failNext(method: 'submitTurn')`; `null` hits whatever is called
  ///   next. Calls to other methods pass through and leave the failure queued.
  ///
  /// The latency is still awaited before the failure is thrown.
  void failNext({int? statusCode = 502, String? message, String? method, int times = 1}) {
    assert(method == null || methodNames.contains(method), 'Unknown method "$method"');
    assert(times > 0);
    for (var i = 0; i < times; i++) {
      _failures.add(_InjectedFailure(method, statusCode, message));
    }
  }

  /// Removes every queued failure.
  void clearFailures() => _failures.clear();

  // -- test hooks -------------------------------------------------------------

  /// The turn limit stored for an audit session (concept 8, task 4, doubled
  /// for `night`). The API never exposes it.
  int debugMaxTurns(int sessionId) =>
      (_audits[sessionId] ?? (throw StateError('No audit session $sessionId'))).maxTurns;

  /// Overrides the turn limit of an audit session, so that the forced failing
  /// verdict at the limit (`passed: false`, `score: 0`) can be reached: with
  /// a limit of 2, a Challenger probe on the second answer becomes that
  /// verdict. The scripted Auditor never probes more than once on its own.
  void debugSetMaxTurns(int sessionId, int maxTurns) {
    final audit = _audits[sessionId] ?? (throw StateError('No audit session $sessionId'));
    audit.maxTurns = maxTurns;
  }

  /// Turns a node into a `task` (or back into a `concept`) so that task
  /// audits can be tested; the generated courses contain concept nodes only.
  void debugSetNodeType(int skillId, NodeType type) {
    final node = _nodes[skillId] ?? (throw StateError('No skill node $skillId'));
    _nodes[skillId] = node.copyWith(nodeType: type);
  }

  /// Sets a node's status directly, e.g. to open a node further along the
  /// learning order than the one the course has open.
  void debugSetStatus(int skillId, SkillStatus status) {
    final node = _nodes[skillId] ?? (throw StateError('No skill node $skillId'));
    _nodes[skillId] = node.copyWith(status: status);
  }

  // ===========================================================================
  // course creation (only the chat uses it; tests seed with it)
  // ===========================================================================

  @override
  Future<CourseMap> generateCourse(GenerateRequest request) =>
      _generateCourse(request, sourceFiles: const []);

  /// [sourceFiles]: names of uploaded files the outline is taken from (a
  /// course from files has no URL; several names are joined with `, `).
  Future<CourseMap> _generateCourse(
    GenerateRequest request, {
    required List<String> sourceFiles,
  }) async {
    await _begin('generateCourse');
    _require(request.topic.trim().isNotEmpty, 'topic must not be blank');

    // `수학` is a Korean fallback; the English demo uses `math`.
    final isMath = request.topic.toLowerCase().contains('math') || request.topic.contains('수학');
    final List<_NodeSpec> specs;
    final List<_RequiresSpec> requires;
    if (isMath) {
      specs = _mathNodes;
      requires = _mathRequires;
    } else if (request.topic.toLowerCase().contains('vision')) {
      specs = _visionNodes;
      requires = const [];
    } else {
      final firstLine = request.topic.split('\n').first.trim();
      final rootTitle = firstLine.isEmpty ? 'New Topic' : _shortTitle(firstLine);
      specs = _genericNodes(rootTitle);
      requires = _genericRequires;
    }

    final foundSyllabus = sourceFiles.isEmpty && isMath && request.searchSyllabus;
    final course = Course(
      id: _nextCourseId++,
      topic: request.topic,
      sourceCourse: sourceFiles.isNotEmpty
          ? sourceFiles.join(', ')
          : foundSyllabus
          ? 'High School Mathematics Curriculum (Ministry of Education)'
          : null,
      sourceUrl: foundSyllabus ? _mockSearch('High School Mathematics Curriculum').first.url : null,
      createdAt: _clock(),
    );
    _courses.add(course);

    final firstId = _nextNodeId;
    _nextNodeId += specs.length;
    final ids = [for (var i = 0; i < specs.length; i++) firstId + i];

    final nodes = <SkillNode>[
      for (var i = 0; i < specs.length; i++)
        SkillNode(
          id: ids[i],
          courseId: course.id,
          slug: specs[i].slug,
          title: specs[i].title,
          description: specs[i].description,
          status: SkillStatus.locked,
          nodeType: NodeType.concept,
          unexpanded: specs[i].expand,
        ),
    ];
    final edges = <SkillEdge>[
      for (var i = 0; i < specs.length; i++)
        for (var p = 0; p < specs[i].parents.length; p++)
          SkillEdge(
            fromId: ids[specs[i].parents[p] - 1],
            toId: ids[i],
            kind: SkillEdgeKind.contains,
            isPrimary: p == 0,
          ),
      for (final r in requires)
        SkillEdge(
          fromId: ids[r.from - 1],
          toId: ids[r.to - 1],
          kind: SkillEdgeKind.requires,
          reason: r.reason,
        ),
    ];

    for (final n in nodes) {
      _nodes[n.id] = n;
    }
    _edges.addAll(edges);
    _openNext(course.id);
    return CourseMap(
      course: course,
      nodes: [for (final n in nodes) _nodes[n.id]!],
      edges: edges,
    );
  }

  // ===========================================================================
  // 3–6: courses and skills
  // ===========================================================================

  @override
  Future<CourseMap> expandSkill(int skillId) async {
    await _begin('expandSkill');
    final node = _nodes[skillId];
    if (node == null) throw const ApiException(404, 'skill not found');
    if (node.isLinked) {
      throw const ApiException(400, 'This node is another course, or is being broken down already.');
    }
    final hasParts = _edges.any((e) => e.kind == SkillEdgeKind.contains && e.fromId == skillId);
    _nodes[skillId] = node.copyWith(unexpanded: false);
    // A node with parts is filled in: one part it was missing.
    final titles = hasParts ? ['More ${node.title}'] : [for (var i = 1; i <= 3; i++) '${node.title} $i'];
    for (final (i, title) in titles.indexed) {
      _addPart(
        node,
        slug: hasParts ? '${node.slug}-more' : '${node.slug}-part-${i + 1}',
        title: _shortTitle(title),
        description: hasParts
            ? 'What ${node.title} still lacked.'
            : 'Explain how part ${i + 1} of ${node.title} works and why it holds.',
      );
    }
    _openNext(node.courseId);
    return _mapOf(_courseOf(node));
  }

  SkillNode _addPart(SkillNode parent, {required String slug, required String title, String description = ''}) {
    final id = _nextNodeId++;
    final taken = {
      for (final n in _nodes.values)
        if (n.courseId == parent.courseId) n.slug,
    };
    var free = slug;
    for (var i = 2; taken.contains(free); i++) {
      free = '$slug-$i';
    }
    final part = SkillNode(
      id: id,
      courseId: parent.courseId,
      slug: free,
      title: title,
      description: description,
      status: SkillStatus.locked,
      nodeType: NodeType.concept,
    );
    _nodes[id] = part;
    _edges.add(SkillEdge(fromId: parent.id, toId: id, kind: SkillEdgeKind.contains, isPrimary: true));
    return part;
  }

  Course _courseOf(SkillNode node) => _courses.firstWhere((c) => c.id == node.courseId);

  SkillNode _editable(int skillId) {
    final node = _nodes[skillId];
    if (node == null) throw const ApiException(404, 'skill not found');
    return node;
  }

  /// The course's node with no contains parent.
  SkillNode? _rootOf(int courseId) => _nodes.values
      .where((n) => n.courseId == courseId)
      .where((n) => !_edges.any((e) => e.kind == SkillEdgeKind.contains && e.toId == n.id))
      .firstOrNull;

  @override
  Future<CourseMap> editSkill(int skillId, {String? title, String? description}) async {
    await _begin('editSkill');
    final node = _editable(skillId);
    _nodes[skillId] = node.copyWith(title: title?.trim(), description: description?.trim());
    return _mapOf(_courseOf(node));
  }

  @override
  Future<CourseMap> deleteSkill(int skillId) async {
    await _begin('deleteSkill');
    final node = _editable(skillId);
    if (_rootOf(node.courseId)?.id == skillId) {
      throw const ApiException(400, 'This is the course itself: delete the course instead.');
    }
    final contains = _edges.where((e) => e.kind == SkillEdgeKind.contains).toList();
    final gone = {skillId};
    final pending = [skillId];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      for (final e in contains.where((e) => e.fromId == current)) {
        final parents = contains.where((p) => p.toId == e.toId).map((p) => p.fromId);
        if (!gone.contains(e.toId) && parents.every(gone.contains)) {
          gone.add(e.toId);
          pending.add(e.toId);
        }
      }
    }
    // A part that stays keeps its other parent, as its main one if need be.
    final staying = {
      for (final e in contains)
        if (gone.contains(e.fromId) && !gone.contains(e.toId)) e.toId,
    };
    _edges.removeWhere((e) => gone.contains(e.fromId) || gone.contains(e.toId));
    for (final id in staying) {
      final edges = [
        for (final e in _edges)
          if (e.kind == SkillEdgeKind.contains && e.toId == id) e,
      ];
      if (edges.isNotEmpty && !edges.any((e) => e.isPrimary == true)) {
        final first = edges.first;
        _edges[_edges.indexOf(first)] = SkillEdge(
          fromId: first.fromId,
          toId: first.toId,
          kind: first.kind,
          isPrimary: true,
        );
      }
    }
    gone.forEach(_nodes.remove);
    final audits = {
      for (final a in _audits.values)
        if (gone.contains(a.skillId)) a.id,
    };
    _audits.removeWhere((id, _) => audits.contains(id));
    _principles.removeWhere((p) => audits.contains(p.sourceSessionId));
    _openNext(node.courseId);
    return _mapOf(_courseOf(node));
  }

  @override
  Future<CourseMap> addSkillPart(int skillId, {required String title, String? description}) async {
    await _begin('addSkillPart');
    final node = _editable(skillId);
    if (node.isLinked) throw const ApiException(400, 'This node is another course: add parts in that course.');
    final slug = title.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    _addPart(node, slug: slug.isEmpty ? 'node' : slug, title: title.trim(), description: description?.trim() ?? '');
    _openNext(node.courseId);
    return _mapOf(_courseOf(node));
  }

  @override
  Future<CourseMap> linkSkill(int skillId, int? courseId) async {
    await _begin('linkSkill');
    final node = _editable(skillId);
    if (courseId != null) {
      if (!_courses.any((c) => c.id == courseId)) throw const ApiException(400, 'No such course.');
      if (courseId == node.courseId) throw const ApiException(400, 'A course cannot be inside itself.');
      if (_rootOf(node.courseId)?.id == skillId) {
        throw const ApiException(400, "This is a course's root: link one of its parts.");
      }
      if (_edges.any((e) => e.kind == SkillEdgeKind.contains && e.fromId == skillId)) {
        throw const ApiException(
          400,
          'This node has parts of its own: delete them first, or link a node without parts.',
        );
      }
      if (_coursesInside(courseId).contains(node.courseId)) {
        throw const ApiException(400, 'That course already holds this one: the two would contain each other.');
      }
    }
    _nodes[skillId] = node.copyWith(unexpanded: courseId == null ? null : false, linkedCourseId: () => courseId);
    _syncLinks();
    return _mapOf(_courseOf(node));
  }

  /// Every course reachable from [courseId] through its nodes' links.
  Set<int> _coursesInside(int courseId) {
    final seen = <int>{};
    final pending = [courseId];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      for (final n in _nodes.values) {
        final linked = n.linkedCourseId;
        if (n.courseId == current && linked != null && seen.add(linked)) pending.add(linked);
      }
    }
    return seen;
  }

  /// A linked node and its course are mastered together (contract #44).
  void _syncLinks() {
    var changed = true;
    while (changed) {
      changed = false;
      for (final node in _nodes.values.toList()) {
        final linked = node.linkedCourseId;
        final root = linked == null ? null : _rootOf(linked);
        if (root == null) continue;
        if (root.isMastered && !node.isMastered) {
          _nodes[node.id] = node.copyWith(status: SkillStatus.mastered, masteryScore: root.masteryScore);
          _openNext(node.courseId);
          changed = true;
        } else if (node.isMastered && !root.isMastered) {
          for (final id in [root.id, ...descendantsOf(root.id, _edges)]) {
            final n = _nodes[id];
            if (n != null && !n.isMastered) {
              _nodes[id] = n.copyWith(status: SkillStatus.mastered, testedOut: true);
            }
          }
          _openNext(root.courseId);
          changed = true;
        }
      }
    }
  }

  @override
  Future<CourseMap> applySyllabus(int courseId, {List<int> uploadIds = const []}) async {
    await _begin('applySyllabus');
    final course = _courses.where((c) => c.id == courseId).firstOrNull;
    final root = _rootOf(courseId);
    if (course == null || root == null) throw const ApiException(404, 'course not found');
    final uploads = [for (final id in uploadIds) _uploads[id] ?? (throw const ApiException(404, 'upload not found'))];
    // The fake reads no syllabus: each file adds one part named after it, a search adds one.
    final titles = uploads.isEmpty ? ['${root.title} in Practice'] : [for (final u in uploads) _stem(u.filename)];
    final have = {
      for (final n in _nodes.values)
        if (n.courseId == courseId) n.title.toLowerCase(),
    };
    for (final title in titles) {
      if (have.add(title.toLowerCase())) {
        _addPart(root, slug: title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'), title: _shortTitle(title));
      }
    }
    _openNext(courseId);
    return _mapOf(course);
  }

  @override
  Future<List<Course>> listCourses() async {
    await _begin('listCourses');
    return _courses.reversed.toList();
  }

  @override
  Future<CourseMap> getCourseMap(int courseId) async {
    await _begin('getCourseMap');
    final course = _courses.where((c) => c.id == courseId).firstOrNull;
    if (course == null) throw const ApiException(404, 'course not found');
    return _mapOf(course);
  }

  CourseMap _mapOf(Course course) {
    final nodes = _nodes.values.where((n) => n.courseId == course.id).toList();
    final ids = {for (final n in nodes) n.id};
    final edges = _edges.where((e) => ids.contains(e.fromId)).toList();
    return CourseMap(course: course, nodes: nodes, edges: edges);
  }

  @override
  Future<List<SkillNode>> listSkills({int? courseId}) async {
    await _begin('listSkills');
    return [
      for (final n in _nodes.values)
        if (courseId == null || n.courseId == courseId) n,
    ];
  }

  // ===========================================================================
  // 7–9: audits
  // ===========================================================================

  @override
  Future<AuditStart> startAudit(int skillId, {String mode = 'day', bool testOut = false}) async {
    await _begin('startAudit');
    _require(mode == 'day' || mode == 'night', 'mode must be "day" or "night"');
    final node = _nodes[skillId];
    if (node == null) throw const ApiException(404, 'skill not found');
    final position = positionOf(skillId, _edges, unexpanded: node.unexpanded);
    if (testOut) {
      if (node.isMastered) throw const ApiException(400, 'skill is already mastered');
      if (position == NodePosition.leaf) {
        throw const ApiException(400, 'Only a branch or a whole course can be challenged.');
      }
    } else {
      if (node.isLocked) throw const ApiException(400, 'skill is locked');
      if (node.unexpanded) {
        throw const ApiException(400, 'Break this node down first, or challenge it as a whole.');
      }
    }

    final opening = testOut ? _testOutQuestion(node) : _openingQuestion(node, position);
    final base = testOut || node.nodeType == NodeType.concept ? 8 : 4;
    final audit = _FakeAudit(
      id: _nextAuditId++,
      skillId: skillId,
      position: position,
      maxTurns: mode == 'night' ? base * 2 : base,
      createdAt: _clock(),
      testOut: testOut,
    )..turns.add(AuditTurn(role: AuditRole.auditor, content: opening));
    _audits[audit.id] = audit;
    return AuditStart(session: audit.toModel(), openingQuestion: opening);
  }

  @override
  Future<TurnResult> submitTurn(int sessionId, String content) async {
    await _begin('submitTurn');
    _require(content.trim().isNotEmpty, 'content must not be blank');
    final audit = _audits[sessionId];
    if (audit == null) throw const ApiException(404, 'audit session not found');
    if (audit.status != AuditStatus.active) {
      throw const ApiException(400, 'audit session is already closed');
    }

    audit.turns.add(AuditTurn(role: AuditRole.user, content: content));
    final userTurns = audit.turns.where((t) => t.isUser).map((t) => t.content).toList();

    // First answer: always a probe.
    if (userTurns.length == 1) {
      final lessons = _retrieveLessons(audit.skillId);
      final withMisconception = lessons.where((p) => p.hasMisconception);
      final question = withMisconception.isEmpty
          ? _genericProbe
          : 'You once thought “${withMisconception.first.misconception}”. '
                'How is this explanation different?';
      return _probeOrForcedFail(audit, question, userTurns.length);
    }

    // Later answers: verdict.
    final n = userTurns.join(' ').runes.length;
    final latest = userTurns.last.toLowerCase().replaceAll('\u2019', "'");
    // `모르` is a Korean fallback for "don't know".
    final passed =
        n >= 80 &&
        !latest.contains("don't know") &&
        !latest.contains('not sure') &&
        !latest.contains('모르');
    if (!passed) {
      return _finishFail(
        audit,
        score: 45,
        gaps: const [
          'You stated the definition but not why it works.',
          "You didn't cover the exceptions.",
        ],
        comment: 'The answer stops at the conclusion and lacks reasons.',
      );
    }
    if (!audit.challenged && n < 160) {
      audit.challenged = true;
      return _probeOrForcedFail(audit, _challengerQuestion, userTurns.length);
    }
    return _finishPass(audit, n);
  }

  @override
  Future<Principle> submitReflection(int sessionId, String reflection) async {
    await _begin('submitReflection');
    _require(reflection.trim().isNotEmpty, 'reflection must not be blank');
    final audit = _audits[sessionId];
    if (audit == null) throw const ApiException(404, 'audit session not found');
    if (audit.status != AuditStatus.failed) {
      throw const ApiException(400, 'reflection is only accepted for a failed audit');
    }
    if (audit.principleId != null) {
      throw const ApiException(400, 'reflection already submitted for this audit');
    }

    // Recorder (Section 4.4).
    final skill = _nodes[audit.skillId]!;
    final principle = Principle(
      id: _nextPrincipleId++,
      title: _cut('Revisit “${skill.title}”', 40),
      body: _cut('When I explain “${skill.title}”, I give the reason before the conclusion.', 120),
      misconception: _cut(reflection.trim(), 60),
      sourceSessionId: audit.id,
      skillId: skill.id,
      skillTitle: skill.title,
      createdAt: _clock(),
    );
    audit.principleId = principle.id;

    // Linker: one `related` link to the most recent other principle.
    if (_principles.isNotEmpty) {
      final previous = _principles.last;
      _links.add(
        _Link(
          principle.id,
          previous.id,
          GraphEdgeKind.related,
          'Same concept, similar misconception',
        ),
      );
      if (reflection.toLowerCase().contains('contradict') || reflection.contains('모순')) {
        _links.add(
          _Link(
            principle.id,
            previous.id,
            GraphEdgeKind.contradicts,
            'Conflicts with the earlier lesson',
          ),
        );
      }
    }
    _principles.add(principle);
    return principle;
  }

  // ===========================================================================
  // 12: check-in
  // ===========================================================================

  /// The Check-in Converter behind the chat (no longer part of the client API).
  Future<CheckInResult> checkInVoice(String transcript) async {
    await _begin('checkInVoice');
    _require(transcript.trim().isNotEmpty, 'transcript must not be blank');
    return _saveCheckIn(_fillIn(transcript));
  }

  /// A said check-in fills in the day: what it found overwrites, the rest
  /// stays (the server's `_fill_in`).
  DailyCheckIn _fillIn(String transcript) {
    final date = formatKstDate(_clock());
    final old = _checkIns[date];
    final parsed = _parseTranscript(transcript);
    final minutes = _parseExerciseMinutes(transcript);
    final earlier = old?.transcript;
    return DailyCheckIn(
      date: date,
      sleepHours: parsed.sleepHours ?? old?.sleepHours,
      exercised: parsed.exercised ?? ((minutes ?? 0) > 0 ? true : null) ?? old?.exercised,
      dietNote: parsed.dietNote ?? old?.dietNote,
      focus: parsed.focus ?? old?.focus,
      stress: parsed.stress ?? old?.stress,
      transcript: earlier == null || transcript.startsWith(earlier)
          ? transcript
          : '$earlier\n$transcript',
      source: CheckInSource.voice,
      sleepQuality: _parseSleepQuality(transcript) ?? old?.sleepQuality,
      exerciseMinutes: minutes ?? old?.exerciseMinutes,
      weightKg: _parseWeight(transcript) ?? old?.weightKg,
    );
  }

  /// The server's voice-log backstop: a check-in only when something was found.
  void _logSaid(String said) {
    final p = _parseTranscript(said);
    final found = [
      p.sleepHours, p.exercised, p.dietNote, p.focus, p.stress,
      _parseSleepQuality(said), _parseExerciseMinutes(said), _parseWeight(said),
    ].any((v) => v != null);
    if (found) _saveCheckIn(_fillIn(said));
  }

  CheckInResult _saveCheckIn(DailyCheckIn checkIn) {
    _checkIns[checkIn.date] = checkIn; // same KST day replaces the record
    return CheckInResult(
      checkin: checkIn,
      missingFields: [
        if (checkIn.sleepHours == null) CheckInField.sleepHours,
        if (checkIn.exercised == null) CheckInField.exercised,
        if (checkIn.dietNote == null) CheckInField.dietNote,
        if (checkIn.focus == null) CheckInField.focus,
        if (checkIn.stress == null) CheckInField.stress,
      ],
    );
  }

  // ===========================================================================
  // 13–16: briefing and plan
  // ===========================================================================

  @override
  Future<Briefing> getBriefing() async {
    await _begin('getBriefing');
    return _briefing();
  }

  /// The Narrator behind the chat (no longer part of the client API).
  Future<Briefing> narrate() async {
    await _begin('narrate');
    final facts = _facts();
    final sentences = <String>[
      "You've cleared ${facts.nodes.mastered} of ${facts.nodes.total} nodes.",
      for (final c in facts.misconceptionClusters)
        'The misconception “${c.label}” showed up ${c.occurrences} ${c.occurrences == 1 ? 'time' : 'times'} in ${c.skills.join(', ')}.',
      if (facts.condition.avgSleepHours != null)
        'Average sleep over the last ${facts.condition.days == 1 ? 'day' : '${facts.condition.days} days'}: ${_num(facts.condition.avgSleepHours!)} h.',
    ];
    _narrative = _cut(sentences.join(' '), 400);
    _narrativeAt = _clock();
    return _briefing();
  }

  /// The Planner behind the chat (no longer part of the client API).
  Future<StudyPlan> generatePlan() async {
    await _begin('generatePlan');
    final available = _nodes.values.where((n) => n.isAvailable).toList();
    if (available.isEmpty) {
      throw const ApiException(
        400,
        'No node is available yet. Generate a course or pass an existing node first.',
      );
    }
    final condition = _conditionFacts();
    final low = condition.flag == ConditionFlag.low;
    // Leaves first when the condition is low (a short, easy session), else by id.
    final ordered = low
        ? [
            ...available.where((n) => positionOf(n.id, _edges) == NodePosition.leaf),
            ...available.where((n) => positionOf(n.id, _edges) != NodePosition.leaf),
          ]
        : available;
    final bucket = _contextBucket(condition);
    final plan = StudyPlan(
      id: _nextPlanId++,
      suggestedTier: _suggestedTier(bucket),
      contextBucket: bucket,
      createdAt: _clock(),
      steps: [
        for (final n in ordered.take(low ? 3 : 5))
          PlanStep(
            skillId: n.id,
            courseId: n.courseId,
            skillTitle: n.title,
            nodeType: n.nodeType,
            rationale: 'Prerequisites checked — you can take this on now.',
            focusHint: 'Explain the why before the definition.',
          ),
      ],
    );
    _plans.add(plan);
    return plan;
  }

  // ===========================================================================
  // 17: material search
  // ===========================================================================

  @override
  Future<SearchPlan> createSearchPlan(int skillId, {String? gap, int? misconceptionId}) async {
    await _begin('createSearchPlan');
    final trimmedGap = gap?.trim() ?? '';
    if (trimmedGap.isEmpty && misconceptionId == null) {
      throw const ApiException(
        400,
        'A gap or misconception id is required. Search targets a specific gap only.',
      );
    }
    final skill = _nodes[skillId];
    if (skill == null) throw const ApiException(404, 'skill not found');

    final String target;
    if (trimmedGap.isNotEmpty) {
      target = trimmedGap;
    } else {
      final principle = _principles.where((p) => p.id == misconceptionId).firstOrNull;
      if (principle == null || !principle.hasMisconception) {
        throw const ApiException(404, 'misconception not found');
      }
      target = principle.misconception!;
    }

    final queries = ['${skill.title} ${_cut(target, 30)}', '${skill.title} explained'];
    final plan = SearchPlan(
      id: _nextSearchPlanId++,
      skillId: skillId,
      gap: target,
      queries: queries,
      items: _mockSearch(queries.first, reason: 'Covers this gap directly.'),
      createdAt: _clock(),
    );
    _searchPlans.add(plan);
    return plan;
  }

  /// Like the backend's Mock script: an answer that names nothing ("idk", "a
  /// lot of things") gets the main quests and two starter courses to pick
  /// from; anything else passes through.
  @override
  Future<CourseScout> scoutCourse(String answer) async {
    await _begin('scoutCourse');
    final typed = answer.trim();
    _require(typed.isNotEmpty, 'answer must not be blank');
    _require(typed.length <= 120, 'answer must be at most 120 characters');
    if (typed.length > 2 && !_vague.hasMatch(typed)) {
      return CourseScout(isClear: true, topic: typed);
    }
    final options = [
      for (final goal in _goals.take(2))
        ScoutOption(
          topic: goal.title.replaceFirst(_questVerb, ''),
          why: 'It is what “${goal.title}” needs first.',
        ),
      for (final (topic, why) in _starterCourses) ScoutOption(topic: topic, why: why),
    ].take(3).toList();
    return CourseScout(
      isClear: false,
      question: 'Here are a few places to start. Pick one:',
      options: options,
    );
  }

  static final _vague = RegExp(
    r"\b(idk|i don'?t know|dont know|no idea|not sure|anything|everything|whatever|a lot|many things"
    r"|something|dunno)\b|不知道|随便|都行|什么都|모르|아무거나|다 좋",
    caseSensitive: false,
  );
  static final _questVerb = RegExp(
    r'^(complete|finish|pass|get|learn|build|do|make|start)\s+',
    caseSensitive: false,
  );
  static const _starterCourses = [
    ('Python programming basics', 'A tool almost every other course leans on.'),
    ('Linear algebra', 'The language of data, graphics and machine learning.'),
    ('Clear technical writing', 'Explaining things well is how you prove them here.'),
  ];

  // ===========================================================================
  // 18–23: stage UI (contract Section 5)
  // ===========================================================================

  /// Unlike the other calls, a failing front desk still keeps the user's
  /// message in the history (contract endpoint 18). An unknown upload id is a
  /// 404 and nothing is saved.
  @override
  Future<List<ChatMessage>> sendChat(
    String message, {
    List<int> uploadIds = const [],
    String? reflectionPrompt,
    String? courseTopic,
  }) async {
    _require(message.trim().isNotEmpty, 'message must not be blank');
    _require(
      courseTopic == null || courseTopic.trim().isNotEmpty || uploadIds.isNotEmpty,
      'course_topic must not be blank without upload_ids',
    );
    if (reflectionPrompt != null) return _answerReflection(message, reflectionPrompt);
    final files = <_FakeUpload>[];
    for (final id in uploadIds) {
      final upload = _uploads[id];
      if (upload == null) throw const ApiException(404, 'upload not found');
      files.add(upload);
    }
    final user = ChatMessage(
      id: _nextChatId++,
      role: ChatRole.user,
      content: message,
      createdAt: _clock(),
    );
    _chat.add(user);
    await _begin('sendChat');

    // A course topic skips the front desk (the tutorial).
    var intent = courseTopic != null && courseTopic.trim().isNotEmpty
        ? _GenerateCourse(courseTopic.trim())
        : courseTopic != null
        ? const _None('')
        : _frontDesk(message);
    // With files, `generate_course` and `none` both build a course from them.
    if (files.isNotEmpty && (intent is _GenerateCourse || intent is _None)) {
      // "I want to learn this" names no topic: the file does.
      final current = intent;
      final named = current is _GenerateCourse && !_demonstrative.hasMatch(current.topic);
      final topic = current is _GenerateCourse && named
          ? current.topic
          : _stem(files.first.filename);
      intent = _GenerateCourse(topic, files: [for (final f in files) f.filename]);
    }
    final out = <ChatMessage>[user];
    ChatMessage assistant(String agent, String content, [ChatAction? action]) => ChatMessage(
      id: _nextChatId++,
      role: ChatRole.assistant,
      content: content,
      agent: agent,
      action: action,
      createdAt: _clock(),
    );

    try {
      switch (intent) {
        case _None(:final reply):
          out.add(assistant('front_desk', reply));
        case _GenerateCourse(:final topic, :final files):
          out.add(assistant('front_desk', "I'll build a world for “$topic”."));
          final map = await _generateCourse(GenerateRequest(topic: topic), sourceFiles: files);
          final root = rootNodes(map.nodes, map.edges).first;
          out.add(
            assistant(
              'planner',
              'Your world “${root.title}” is ready — ${map.nodes.length} nodes.',
              CourseAction(course: map.course, nodeCount: map.nodes.length),
            ),
          );
        case _OpenSkill(:final skill):
          out.add(
            assistant(
              'front_desk',
              'Taking you to “${skill.title}”.',
              NavigateAction(scene: NavScene.skill, skillId: skill.id),
            ),
          );
        case _CheckIn():
          out.add(assistant('front_desk', 'Got it, logging that.'));
          final result = await checkInVoice(message);
          out.add(
            assistant('checkin_converter', _checkInSummary(result.checkin), CheckInAction(result)),
          );
        case _Plan():
          out.add(assistant('front_desk', "Let me pick today's quests."));
          final plan = await generatePlan();
          final titles = plan.steps.map((s) => '“${s.skillTitle}”').join(', ');
          out.add(assistant('recommender', "Today's quests: $titles.", PlanAction(plan)));
        case _Briefing():
          out.add(assistant('front_desk', 'Let me sum up where you are.'));
          final briefing = await narrate();
          out.add(assistant('narrator', briefing.narrative ?? '', BriefingAction(briefing)));
        case _OpenMap():
          out.add(
            assistant(
              'front_desk',
              'Opening your life tree.',
              const NavigateAction(scene: NavScene.map),
            ),
          );
      }
    } on ApiException catch (e) {
      out.add(assistant('front_desk', _pipelineFailure(intent, e)));
    }
    // A check-in or plain chat also goes to the Fact Keeper (#40).
    if (intent is _CheckIn || (intent is _None && files.isEmpty && courseTopic == null)) {
      _keepFacts(message);
    }
    _chat.addAll(out.skip(1));
    return out;
  }

  /// Chat with a `reflection_prompt`: no front desk, nothing generated.
  Future<List<ChatMessage>> _answerReflection(String message, String prompt) async {
    _require(reflectionPrompts.contains(prompt), 'unknown reflection prompt');
    await _begin('sendChat');
    ChatMessage line(ChatRole role, String content, {String? agent}) => ChatMessage(
      id: _nextChatId++,
      role: role,
      content: content,
      agent: agent,
      createdAt: _clock(),
    );
    final out = [
      line(ChatRole.assistant, prompt, agent: 'front_desk'),
      line(ChatRole.user, message),
      line(ChatRole.assistant, "Noted. It's in your journal.", agent: 'front_desk'),
    ];
    _journal.add(
      JournalEntry(
        id: _nextJournalId++,
        prompt: prompt,
        answer: message.trim(),
        createdAt: _clock(),
      ),
    );
    _chat.addAll(out);
    return out;
  }

  static final RegExp _demonstrative = RegExp(
    r'^(?:this|this file|these|these files)$',
    caseSensitive: false,
  );

  /// A file name without its extension.
  static String _stem(String filename) {
    final dot = filename.lastIndexOf('.');
    return dot > 0 ? filename.substring(0, dot) : filename;
  }

  @override
  Future<UploadedFile> uploadFile({required String filename, required List<int> bytes}) async {
    await _begin('uploadFile');
    final lower = filename.toLowerCase();
    final allowed = lower.endsWith('.pdf') || lower.endsWith('.txt') || lower.endsWith('.md');
    if (!allowed || bytes.length > 4 * 1024 * 1024) {
      throw const ApiException(400, 'Only PDF, TXT or MD files up to 4 MB.');
    }
    // PDFs are not parsed here: any non-empty PDF counts as readable text.
    final text = lower.endsWith('.pdf')
        ? String.fromCharCodes(bytes)
        : String.fromCharCodes(utf8.decode(bytes, allowMalformed: true).runes);
    if (text.trim().isEmpty) {
      throw const ApiException(400, 'No text could be read from this file.');
    }
    final upload = _FakeUpload(
      id: _nextUploadId++,
      filename: filename,
      chars: math.min(text.runes.length, 100000),
      createdAt: _clock(),
    );
    _uploads[upload.id] = upload;
    return UploadedFile(
      id: upload.id,
      filename: upload.filename,
      chars: upload.chars,
      createdAt: upload.createdAt,
    );
  }

  /// Pipeline failures are explained in a message, not thrown (endpoint 18).
  String _pipelineFailure(_Intent intent, ApiException e) {
    if (e.statusCode == 400 && intent is _Plan) {
      return 'No node is ready yet. Make a world first.';
    }
    return switch (intent) {
      _GenerateCourse() => "I couldn't build that world. Please try again in a moment.",
      _CheckIn() => "I couldn't log that. Please try again in a moment.",
      _Plan() => "I couldn't pick today's quests. Please try again.",
      _Briefing() => "I couldn't put your status together. Please try again.",
      _ => "I couldn't do that right now. Please try again in a moment.",
    };
  }

  String _checkInSummary(DailyCheckIn c) {
    final parts = <String>[
      if (c.sleepHours != null) 'sleep ${_num(c.sleepHours!)} h',
      if (c.exercised != null) 'exercise ${c.exercised! ? 'yes' : 'no'}',
      if (c.dietNote != null) 'meals ${c.dietNote}',
      if (c.focus != null) 'focus ${c.focus}/5',
      if (c.stress != null) 'stress ${c.stress}/5',
    ];
    return parts.isEmpty
        ? "I couldn't find anything to log. Tell me about sleep, exercise or meals."
        : 'Logged: ${parts.join(' · ')}';
  }

  static String _num(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  /// The Mock front desk (contract Section 5): keyword rules, first match wins; `teach me` also counts as a learn request.
  _Intent _frontDesk(String message) {
    final skill = _titleInMessage(message);
    if (skill != null &&
        RegExp('challenge|audit|try|open|continue|start', caseSensitive: false).hasMatch(message)) {
      return _OpenSkill(skill);
    }
    if (RegExp(
      r'\b(?:sleep|slept|tired|exercis|worked out|ate\b|had .* for (?:breakfast|lunch|dinner)|log my day|my day)',
      caseSensitive: false,
    ).hasMatch(message)) {
      return const _CheckIn();
    }
    if (RegExp(r'learn|study|build|make|create|teach me', caseSensitive: false).hasMatch(message)) {
      var topic = message.trim().replaceFirst(
        RegExp(
          r"^(?:i want to learn|i['\u2019]d like to learn|i want to study|teach me|"
          r'build me a world (?:for|about)|make a world (?:for|about))\s*',
          caseSensitive: false,
        ),
        '',
      );
      topic = topic.replaceFirst(RegExp(r'[\s.!?]+$'), '').trim();
      if (topic.isEmpty) return const _None('What topic should I build?');
      return _GenerateCourse(topic);
    }
    if (RegExp('quest|what should i|recommend', caseSensitive: false).hasMatch(message)) {
      return const _Plan();
    }
    if (RegExp('status|report|how am i doing', caseSensitive: false).hasMatch(message)) {
      return const _Briefing();
    }
    if (RegExp('map|world', caseSensitive: false).hasMatch(message)) return const _OpenMap();
    return const _None('Sure. What would you like to do today?');
  }

  /// The node whose title is contained in [message]: the longest title wins,
  /// a tie goes to the newest course.
  SkillNode? _titleInMessage(String message) {
    SkillNode? best;
    final lower = message.toLowerCase();
    for (final n in _nodes.values) {
      if (!lower.contains(n.title.toLowerCase())) continue;
      if (best == null ||
          n.title.length > best.title.length ||
          (n.title.length == best.title.length && n.courseId >= best.courseId)) {
        best = n;
      }
    }
    return best;
  }

  @override
  Future<List<ChatMessage>> getChatHistory({int limit = 50}) async {
    await _begin('getChatHistory');
    _require(limit >= 1 && limit <= 200, 'limit must be 1-200');
    return _chat.length <= limit ? List.of(_chat) : _chat.sublist(_chat.length - limit);
  }

  @override
  Future<List<ChatSuggestion>> getChatSuggestions() async {
    await _begin('getChatSuggestions');
    final out = <ChatSuggestion>[];
    // 1. no check-in today; once checked in, this window's reflection prompt
    // (unless it was answered today).
    final now = _clock();
    if (!_checkIns.containsKey(formatKstDate(now))) {
      out.add(const ChatSuggestion(label: 'How was your day?', message: 'Let me log my day'));
    } else {
      final kst = toKst(now);
      final prompt = reflectionPromptAt(kst.hour * 60 + kst.minute);
      final today = formatKstDate(now);
      final answered = _journal.any(
        (e) => e.prompt == prompt && formatKstDate(e.createdAt) == today,
      );
      if (!answered) {
        out.add(ChatSuggestion(label: prompt, message: '', reflection: true));
      }
    }
    // 2. continue learning.
    final last = _audits.values.isEmpty ? null : _audits.values.last; // newest, any status
    final lastNode = last == null ? null : _nodes[last.skillId];
    if (lastNode != null && !lastNode.isMastered) {
      out.add(
        ChatSuggestion(
          label: 'Continue “${lastNode.title}”',
          message: 'Continue “${lastNode.title}”',
          skillId: lastNode.id,
        ),
      );
    } else {
      final available = _courses.isEmpty
          ? null
          : _nodes.values.where((n) => n.courseId == _courses.last.id && n.isAvailable).firstOrNull;
      if (available != null) {
        out.add(
          ChatSuggestion(
            label: 'Start with “${available.title}”',
            message: 'Start with “${available.title}”',
            skillId: available.id,
          ),
        );
      } else {
        out.add(const ChatSuggestion(label: 'Tell me what you want to learn', message: ''));
      }
    }
    return out;
  }

  @override
  Future<DailyCheckIn?> getTodayCheckIn() async {
    await _begin('getTodayCheckIn');
    return _checkIns[formatKstDate(_clock())];
  }

  // -- 39: life ------------------------------------------------------------------

  LifeAdvice? _lifeAdvice;

  @override
  Future<Life> getLife({int days = 30}) async {
    await _begin('getLife');
    _require(days >= 7 && days <= 365, 'days must be 7-365');
    return _life(days);
  }

  @override
  Future<LifeAdvice> requestLifeAdvice() async {
    await _begin('requestLifeAdvice');
    final s = _life(14).summary;
    final items = [
      if (s.avgSleepHours != null)
        LifeAdviceItem(
          title: 'Protect your sleep',
          body: 'Pick a fixed time to stop screens this week and keep it five nights.',
          basedOn: 'slept ${s.avgSleepHours} h on average',
        ),
      if (s.avgFocus != null)
        LifeAdviceItem(
          title: 'Audit when you focus best',
          body: 'Put this week\'s audits in the part of the day you feel sharpest.',
          basedOn: 'focus ${s.avgFocus} of 5 on average',
        ),
      LifeAdviceItem(
        title: 'Log a few more days',
        body: 'Check in every day this week, even briefly, so your own patterns can show up.',
        basedOn: '${s.daysLogged} of 14 days logged',
      ),
    ].take(3).toList();
    return _lifeAdvice = LifeAdvice(items: items, generatedAt: _clock());
  }

  @override
  Future<DailyCheckIn> editCheckIn(String date, Map<String, Object?> fields) async {
    await _begin('editCheckIn');
    if (date.compareTo(formatKstDate(_clock())) > 0) {
      throw const ApiException(400, 'That day has not come yet.');
    }
    final old = _checkIns[date];
    T? pick<T>(String key, T? current) => fields.containsKey(key) ? fields[key] as T? : current;
    final minutes = pick<int>('exercise_minutes', old?.exerciseMinutes);
    final checkIn = DailyCheckIn(
      date: date,
      sleepHours: pick<num>('sleep_hours', old?.sleepHours)?.toDouble(),
      exercised: pick<bool>('exercised', old?.exercised) ?? ((minutes ?? 0) > 0 ? true : null),
      dietNote: pick<String>('diet_note', old?.dietNote),
      focus: pick<int>('focus', old?.focus),
      stress: pick<int>('stress', old?.stress),
      transcript: old?.transcript,
      source: old?.source ?? CheckInSource.manual,
      sleepQuality: pick<int>('sleep_quality', old?.sleepQuality),
      exerciseMinutes: minutes,
      weightKg: pick<num>('weight_kg', old?.weightKg)?.toDouble(),
    );
    _checkIns[date] = checkIn;
    return checkIn;
  }

  // -- 40: lasting facts ---------------------------------------------------------

  static const int maxFacts = 20;
  final List<LifeFact> _lifeFacts = []; // creation order
  int _nextFactId = 1;

  List<LifeFact> get _holding => [
    for (final f in _lifeFacts.reversed)
      if (f.endedAt == null) f,
  ];

  void _putFact(LifeFact fact) {
    final i = _lifeFacts.indexWhere((f) => f.id == fact.id);
    if (i < 0) {
      _lifeFacts.add(fact);
    } else {
      _lifeFacts[i] = fact;
    }
  }

  LifeFact _endFact(LifeFact f) => LifeFact(
    id: f.id,
    category: f.category,
    text: f.text,
    said: f.said,
    createdAt: f.createdAt,
    endedAt: _clock(),
    replacesId: f.replacesId,
  );

  /// The server Mock's Fact Keeper: injuries and healing, night shifts, a
  /// vegetarian or vegan diet and exam periods; nothing else.
  void _keepFacts(String said) {
    LifeFact? holds(String word) =>
        _holding.where((f) => f.text.toLowerCase().contains(word.toLowerCase())).firstOrNull;
    void add(FactCategory category, String text) {
      if (_holding.length >= maxFacts) return;
      if (_holding.any((f) => f.text.toLowerCase() == text.toLowerCase())) return;
      _lifeFacts.add(
        LifeFact(
          id: _nextFactId++,
          category: category,
          text: text,
          said: true,
          createdAt: _clock(),
        ),
      );
    }

    final healed = _healedPattern.firstMatch(said);
    final injured = _injuredPattern.firstMatch(said);
    if (healed != null) {
      final fact = holds(healed.group(1) ?? healed.group(2)!);
      if (fact != null) _putFact(_endFact(fact));
    } else if (injured != null) {
      final part = (injured.group(1) ?? injured.group(2)!).toLowerCase();
      if (holds(part) == null) {
        add(FactCategory.health, '${part[0].toUpperCase()}${part.substring(1)} injury');
      }
    }
    if (_nightShiftPattern.hasMatch(said)) add(FactCategory.schedule, 'Works night shifts');
    final diet = _dietPattern.firstMatch(said);
    if (diet != null) {
      final d = diet.group(1)!.toLowerCase();
      add(FactCategory.preference, '${d[0].toUpperCase()}${d.substring(1)}');
    }
    final exams = _examsPattern.firstMatch(said);
    if (exams != null) add(FactCategory.schedule, 'Exams until ${exams.group(1)!.trim()}');
  }

  static const String _factsFull = 'You can keep $maxFacts lasting facts. End or delete one first.';

  LifeFact _fact(int id) =>
      _lifeFacts.where((f) => f.id == id).firstOrNull ??
      (throw const ApiException(404, 'fact not found'));

  String _factText(String text) {
    final t = text.trim().split(RegExp(r'\s+')).join(' ');
    _require(t.isNotEmpty && t.length <= LifeFact.maxLength, 'text must be 1-120 characters');
    return t;
  }

  @override
  Future<LifeFact> addLifeFact(String text, {FactCategory category = FactCategory.other}) async {
    await _begin('addLifeFact');
    final clean = _factText(text);
    if (_holding.length >= maxFacts) throw const ApiException(409, _factsFull);
    final fact = LifeFact(
      id: _nextFactId++,
      category: category,
      text: clean,
      said: false,
      createdAt: _clock(),
    );
    _lifeFacts.add(fact);
    return fact;
  }

  @override
  Future<LifeFact> editLifeFact(
    int id, {
    String? text,
    FactCategory? category,
    bool? ended,
  }) async {
    await _begin('editLifeFact');
    final old = _fact(id);
    final clean = text == null ? null : _factText(text);
    var endedAt = old.endedAt;
    if (ended == true && endedAt == null) endedAt = _clock();
    if (ended == false && endedAt != null) {
      if (_holding.length >= maxFacts) throw const ApiException(409, _factsFull);
      endedAt = null;
    }
    final fact = LifeFact(
      id: old.id,
      category: category ?? old.category,
      text: clean ?? old.text,
      said: old.said,
      createdAt: old.createdAt,
      endedAt: endedAt,
      replacesId: old.replacesId,
    );
    _putFact(fact);
    return fact;
  }

  @override
  Future<void> deleteLifeFact(int id) async {
    await _begin('deleteLifeFact');
    _fact(id);
    _lifeFacts.removeWhere((f) => f.id == id);
    for (final f in [..._lifeFacts]) {
      if (f.replacesId == id) {
        _putFact(
          LifeFact(
            id: f.id,
            category: f.category,
            text: f.text,
            said: f.said,
            createdAt: f.createdAt,
            endedAt: f.endedAt,
          ),
        );
      }
    }
  }

  /// The server's `services/life.py`, over [window] days ending today (KST).
  Life _life(int window) {
    final kst = toKst(_clock());
    final today = DateTime.utc(kst.year, kst.month, kst.day);
    String ymd(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final audits = <String, (int, int)>{};
    for (final a in _audits.values) {
      if (a.status == AuditStatus.active) continue;
      final (n, p) = audits[formatKstDate(a.createdAt)] ?? (0, 0);
      audits[formatKstDate(a.createdAt)] = (n + 1, p + (a.status == AuditStatus.passed ? 1 : 0));
    }
    bool? exercised(DailyCheckIn c) => (c.exerciseMinutes ?? 0) > 0 ? true : c.exercised;
    final days = [
      for (var i = window - 1; i >= 0; i--)
        () {
          final date = ymd(today.subtract(Duration(days: i)));
          final c = _checkIns[date];
          final (n, p) = audits[date] ?? (0, 0);
          return LifeDay(
            date: date,
            checkedIn: c != null,
            sleepHours: c?.sleepHours,
            sleepQuality: c?.sleepQuality,
            exercised: c == null ? null : exercised(c),
            exerciseMinutes: c?.exerciseMinutes,
            weightKg: c?.weightKg,
            dietNote: c?.dietNote,
            focus: c?.focus,
            stress: c?.stress,
            audits: n,
            passed: p,
          );
        }(),
    ];
    double? mean(Iterable<num?> v) {
      final present = [for (final x in v) ?x];
      return present.isEmpty
          ? null
          : (present.reduce((a, b) => a + b) / present.length * 10).round() / 10;
    }

    final logged = [
      for (final d in days)
        if (d.checkedIn) _checkIns[d.date]!,
    ];
    final weights = [
      for (final c in logged)
        if (c.weightKg != null) c.weightKg!,
    ];
    LifeGroup group(List<DailyCheckIn> cs) {
      final n = cs.fold<int>(0, (t, c) => t + (audits[c.date]?.$1 ?? 0));
      final p = cs.fold<int>(0, (t, c) => t + (audits[c.date]?.$2 ?? 0));
      return LifeGroup(
        days: cs.length,
        audits: n,
        passRate: n == 0 ? null : (p / n * 100).round() / 100,
        avgFocus: mean(cs.map((c) => c.focus)),
      );
    }

    final all = _checkIns.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    final splits = <LifePatternKind, (bool Function(DailyCheckIn), bool Function(DailyCheckIn))>{
      LifePatternKind.sleep: (
        (c) => (c.sleepHours ?? -1) >= 7,
        (c) => c.sleepHours != null && c.sleepHours! < 6,
      ),
      LifePatternKind.exercise: ((c) => exercised(c) == true, (c) => exercised(c) == false),
      LifePatternKind.stress: (
        (c) => c.stress != null && c.stress! <= 2,
        (c) => (c.stress ?? 0) >= 4,
      ),
    };
    const minDays = 5;
    final patterns = <LifePattern>[
      for (final MapEntry(key: kind, value: (better, worse)) in splits.entries)
        if (all.where(better).length >= minDays && all.where(worse).length >= minDays)
          LifePattern(
            kind: kind,
            better: group(all.where(better).toList()),
            worse: group(all.where(worse).toList()),
          ),
    ];
    return Life(
      summary: LifeSummary(
        days: window,
        daysLogged: logged.length,
        avgSleepHours: mean(logged.map((c) => c.sleepHours)),
        avgSleepQuality: mean(logged.map((c) => c.sleepQuality)),
        exerciseDays: logged.where((c) => exercised(c) == true).length,
        avgExerciseMinutes: mean(
          logged.map((c) => (c.exerciseMinutes ?? 0) > 0 ? c.exerciseMinutes : null),
        ),
        avgFocus: mean(logged.map((c) => c.focus)),
        avgStress: mean(logged.map((c) => c.stress)),
        weightFirst: weights.firstOrNull,
        weightLast: weights.lastOrNull,
        audits: days.fold(0, (t, d) => t + d.audits),
        passed: days.fold(0, (t, d) => t + d.passed),
      ),
      days: days,
      patterns: patterns,
      patternMinDays: minDays,
      advice: _lifeAdvice,
      facts: _holding,
      pastFacts: [..._lifeFacts.where((f) => f.endedAt != null)]
        ..sort((a, b) => b.endedAt!.compareTo(a.endedAt!)),
      maxFacts: maxFacts,
    );
  }

  @override
  Future<SkillOverview> getSkillOverview(int skillId) async {
    await _begin('getSkillOverview');
    final skill = _nodes[skillId];
    if (skill == null) throw const ApiException(404, 'skill not found');
    final course = _courses.firstWhere((c) => c.id == skill.courseId);
    return SkillOverview(
      skill: skill,
      course: course,
      containsParents: [for (final id in containsParentsOf(skillId, _edges)) _nodes[id]!],
      requires: [
        for (final e in requiresIn(skillId, _edges))
          RequiredSkill(skill: _nodes[e.fromId]!, reason: e.reason),
      ],
      audits: [
        for (final a in _audits.values.toList().reversed)
          if (a.skillId == skillId) _summaryOf(a),
      ],
      materials: [
        for (final p in _searchPlans.reversed)
          if (p.skillId == skillId) p,
      ],
    );
  }

  @override
  Future<List<AuditSummary>> listAudits({int limit = 20}) async {
    await _begin('listAudits');
    _require(limit >= 1 && limit <= 100, 'limit must be 1-100');
    return [for (final a in _audits.values.toList().reversed.take(limit)) _summaryOf(a)];
  }

  AuditSummary _summaryOf(_FakeAudit a) => AuditSummary(
    id: a.id,
    skillId: a.skillId,
    skillTitle: (_nodes[a.skillId] ?? _hiddenNodes[a.skillId])!.title,
    status: a.status,
    score: a.score,
    createdAt: a.createdAt,
    testOut: a.testOut,
  );

  // ===========================================================================
  // 32, 34: who is signed in; the developer panel
  // ===========================================================================

  /// Local and offline: always a developer.
  @override
  Future<Me> getMe() async {
    await _begin('getMe');
    return const Me(id: 'dev', isDev: true);
  }

  @override
  Future<DevAudits> getDevAudits({int limit = 50}) async {
    await _begin('getDevAudits');
    _require(limit >= 1 && limit <= 200, 'limit must be 1-200');
    final finished = [
      for (final a in _audits.values.toList().reversed)
        if (a.status != AuditStatus.active) a,
    ];
    return DevAudits(
      metrics: _devMetrics(finished),
      audits: [for (final a in finished.take(limit)) _devAuditOf(a)],
    );
  }

  @override
  Future<DevAudit> reviewAudit(int auditId, AuditReview? review, {bool leaked = false}) async {
    await _begin('reviewAudit');
    final a = _audits[auditId] ?? (throw const ApiException(404, 'audit session not found'));
    if (a.status == AuditStatus.active) throw const ApiException(400, 'audit is not finished');
    if (review == AuditReview.tooStrict && a.status != AuditStatus.failed) {
      throw const ApiException(400, 'too_strict is for a failed audit');
    }
    if (review == AuditReview.tooLenient && a.status != AuditStatus.passed) {
      throw const ApiException(400, 'too_lenient is for a passed audit');
    }
    a
      ..review = review
      ..leaked = review != null && leaked;
    return _devAuditOf(a);
  }

  // ===========================================================================
  // 35: voice
  // ===========================================================================

  /// Offline there is no speech server: the app uses the device's own speech.
  @override
  Future<bool> voiceAvailable() async {
    await _begin('voiceAvailable');
    return false;
  }

  @override
  Future<String?> guideVoice() async {
    await _begin('guideVoice');
    return null;
  }

  @override
  Future<String> transcribe(Uint8List audio, {required String filename}) async {
    await _begin('transcribe');
    throw const ApiException(503, 'voice is not configured');
  }

  @override
  Future<Uint8List> speech(String text) async {
    await _begin('speech');
    throw const ApiException(503, 'voice is not configured');
  }

  // ===========================================================================
  // 36: the realtime Guide (it needs the server, so never runs offline)
  // ===========================================================================

  @override
  LiveEndpoint? liveEndpoint(String path) => null;

  @override
  Future<List<ChatMessage>> chatAct(
    String intent, {
    Map<String, Object?> args = const {},
    String said = '',
  }) async {
    await _begin('chatAct');
    throw const ApiException(503, 'voice is not configured');
  }

  @override
  Future<List<ChatMessage>> chatLog(List<({ChatRole role, String content})> lines) async {
    await _begin('chatLog');
    final saved = [
      for (final l in lines)
        if (l.content.trim().isNotEmpty)
          ChatMessage(
            id: _nextChatId++,
            role: l.role,
            content: l.content.trim(),
            agent: l.role == ChatRole.user ? null : 'front_desk',
            createdAt: _clock(),
          ),
    ];
    _chat.addAll(saved);
    final said = saved.where((m) => m.role == ChatRole.user).map((m) => m.content).join('\n');
    if (said.isNotEmpty) {
      _keepFacts(said);
      _logSaid(said);
    }
    return saved;
  }

  // ===========================================================================
  // 37: what live voice costs (offline there is none; reports are kept as sent)
  // ===========================================================================

  final Map<String, Json> _voiceUsage = {};

  @override
  Future<void> reportVoiceUsage(VoiceUsage usage) async {
    await _begin('reportVoiceUsage');
    _voiceUsage[usage.id] = usage.toJson();
  }

  @override
  Future<DevVoice> getDevVoice({int limit = 50}) async {
    await _begin('getDevVoice');
    _require(limit >= 1 && limit <= 200, 'limit must be 1-200');
    var id = 0;
    final sessions = [
      for (final u in _voiceUsage.values)
        DevVoiceSession(
          id: ++id,
          kind: u['kind'] as String,
          model: u['model'] as String,
          startedAt: DateTime.parse(u['started_at'] as String),
          minutes: (u['seconds'] as num) / 60,
          turns: u['turns'] as int,
          audioIn: u['audio_in'] as int,
          audioOut: u['audio_out'] as int,
          cost: 0,
          otherCost: u['kind'] != 'guide'
              ? null
              : (u['seconds'] as num) / 60 * ('${u['model']}'.startsWith('gpt-live') ? 0.072 : 0.05),
        ),
    ];
    final guide = sessions.where((s) => s.kind == 'guide');
    final audits = sessions.where((s) => s.kind != 'guide');
    final guideMinutes = guide.fold(0.0, (t, s) => t + s.minutes);
    return DevVoice(
      guideSessions: guide.length,
      guideMinutes: guideMinutes,
      guideCost: 0,
      guideAllLive: guideMinutes * 0.05,
      guideAllRealtime: guideMinutes * 0.072,
      realtimePerMinute: 0.072,
      auditSessions: audits.length,
      auditMinutes: audits.fold(0.0, (t, s) => t + s.minutes),
      auditCost: 0,
      sessions: sessions.reversed.take(limit).toList(),
    );
  }

  DevAudit _devAuditOf(_FakeAudit a) => DevAudit(
    id: a.id,
    skillId: a.skillId,
    skillTitle: (_nodes[a.skillId] ?? _hiddenNodes[a.skillId])!.title,
    status: a.status,
    score: a.score,
    gaps: a.gaps,
    comment: a.comment,
    turns: List.unmodifiable(a.turns),
    review: a.review,
    leaked: a.leaked,
    createdAt: a.createdAt,
  );

  /// The same sums as the server's `services/audit_review.py`.
  static DevMetrics _devMetrics(List<_FakeAudit> finished) {
    double? rate(num part, int whole) =>
        whole == 0 ? null : (part / whole * 10000).roundToDouble() / 10000;
    final passed = finished.where((a) => a.status == AuditStatus.passed).length;
    final failed = [
      for (final a in finished)
        if (a.status == AuditStatus.failed) a,
    ];
    final reviewed = [
      for (final a in finished)
        if (a.review != null) a,
    ];
    final pairs = [
      for (final a in reviewed)
        (
          a.status == AuditStatus.passed,
          a.review == AuditReview.right
              ? a.status == AuditStatus.passed
              : a.status != AuditStatus.passed,
        ),
    ];
    return DevMetrics(
      finished: finished.length,
      passRate: rate(passed, finished.length),
      avgScore: rate(finished.fold<int>(0, (s, a) => s + (a.score ?? 0)), finished.length),
      avgGapsWhenFailed: rate(failed.fold<int>(0, (s, a) => s + a.gaps.length), failed.length),
      avgAnswers: rate(
        finished.fold<int>(0, (s, a) => s + a.turns.where((t) => t.isUser).length),
        finished.length,
      ),
      challengedRate: rate(finished.where((a) => a.challenged).length, finished.length),
      reviewed: reviewed.length,
      agreement: rate(reviewed.where((a) => a.review == AuditReview.right).length, reviewed.length),
      kappa: cohensKappa(pairs),
      tooStrict: reviewed.where((a) => a.review == AuditReview.tooStrict).length,
      tooLenient: reviewed.where((a) => a.review == AuditReview.tooLenient).length,
      leaked: reviewed.where((a) => a.leaked).length,
    );
  }

  // ===========================================================================
  // 16, 25–27: life as a game (contract Section 6)
  // ===========================================================================

  @override
  Future<StudyPlan?> getCurrentPlan() async {
    await _begin('getCurrentPlan');
    return _plans.lastOrNull;
  }

  @override
  Future<Profile> getProfile() async {
    await _begin('getProfile');
    return _profile;
  }

  @override
  Future<Profile> updateProfile({
    String? identity,
    String? vision,
    String? antiVision,
    List<String>? rules,
    bool? onboarded,
  }) async {
    await _begin('updateProfile');
    for (final text in [identity, vision, antiVision]) {
      _require((text?.trim().length ?? 0) <= Profile.maxTextLength, 'text is too long');
    }
    List<String>? cleaned;
    if (rules != null) {
      cleaned = [
        for (final r in rules)
          if (r.trim().isNotEmpty) r.trim(),
      ];
      _require(cleaned.length <= Profile.maxRules, 'too many rules');
      _require(cleaned.every((r) => r.length <= Profile.maxRuleLength), 'a rule is too long');
    }
    _profile = Profile(
      identity: identity?.trim() ?? _profile.identity,
      vision: vision?.trim() ?? _profile.vision,
      antiVision: antiVision?.trim() ?? _profile.antiVision,
      rules: cleaned == null ? _profile.rules : List.unmodifiable(cleaned),
      updatedAt: _clock(),
      onboarded: onboarded ?? _profile.onboarded,
    );
    return _profile;
  }

  @override
  Future<List<JournalEntry>> listJournal({int limit = 20}) async {
    await _begin('listJournal');
    _require(limit >= 1 && limit <= 100, 'limit must be 1-100');
    return _journal.reversed.take(limit).toList();
  }

  @override
  Future<List<Principle>> listPrinciples() async {
    await _begin('listPrinciples');
    return _principles.reversed.toList();
  }

  // -- 28–31: main quests --------------------------------------------------------

  @override
  Future<List<Goal>> listGoals() async {
    await _begin('listGoals');
    return List.unmodifiable(_goals);
  }

  @override
  Future<Goal> createGoal(String title) async {
    await _begin('createGoal');
    final t = _goalTitle(title);
    if (_goals.length >= Goal.maxGoals) {
      throw const ApiException(409, 'at most ${Goal.maxGoals} main quests');
    }
    final goal = Goal(id: _nextGoalId++, title: t, createdAt: _clock());
    _goals.add(goal);
    return goal;
  }

  /// Opens the first node not mastered of each chapter (a child of the root)
  /// in the course's learning order, and the root once every chapter is done;
  /// locks the other unmastered ones. Returns the ids it opened.
  List<int> _openNext(int courseId) {
    final nodes = [
      for (final n in _nodes.values)
        if (n.courseId == courseId) n,
    ];
    final opened = <int>[];
    final started = <int?>{};
    for (final id in learningOrder(nodes, _edges)) {
      final n = _nodes[id]!;
      if (n.isMastered) continue;
      final chapter = chapterOf(id, _edges);
      final want = started.contains(chapter) || (chapter == null && started.isNotEmpty)
          ? SkillStatus.locked
          : SkillStatus.available;
      started.add(chapter);
      if (n.status != want) {
        _nodes[id] = n.copyWith(status: want);
        if (want == SkillStatus.available) opened.add(id);
      }
    }
    return opened;
  }

  @override
  Future<Goal> updateGoal(int goalId, {String? title, List<int>? courseIds}) async {
    await _begin('updateGoal');
    final index = _goals.indexWhere((g) => g.id == goalId);
    if (index < 0) throw const ApiException(404, 'goal not found');
    final t = title == null ? null : _goalTitle(title);
    List<int>? ids;
    if (courseIds != null) {
      ids = courseIds.toSet().toList();
      for (final id in ids) {
        if (!_courses.any((c) => c.id == id)) throw const ApiException(404, 'course not found');
      }
      for (var i = 0; i < _goals.length; i++) {
        if (i == index) continue;
        final g = _goals[i];
        final kept = [
          for (final c in g.courseIds)
            if (!ids.contains(c)) c,
        ];
        if (kept.length != g.courseIds.length) {
          _goals[i] = Goal(id: g.id, title: g.title, courseIds: kept, createdAt: g.createdAt);
        }
      }
    }
    final g = _goals[index];
    return _goals[index] = Goal(
      id: g.id,
      title: t ?? g.title,
      courseIds: List.unmodifiable(ids ?? g.courseIds),
      createdAt: g.createdAt,
    );
  }

  @override
  Future<void> deleteGoal(int goalId) async {
    await _begin('deleteGoal');
    final before = _goals.length;
    _goals.removeWhere((g) => g.id == goalId);
    if (_goals.length == before) throw const ApiException(404, 'goal not found');
  }

  /// Keeping the nodes moves them out of sight with the course (the lessons
  /// stay); deleting them takes their audits and lessons too.
  @override
  Future<void> deleteCourse(int courseId, {bool deleteNodes = false}) async {
    await _begin('deleteCourse');
    final before = _courses.length;
    _courses.removeWhere((c) => c.id == courseId);
    if (_courses.length == before) throw const ApiException(404, 'course not found');
    for (var i = 0; i < _goals.length; i++) {
      final g = _goals[i];
      if (g.courseIds.contains(courseId)) {
        _goals[i] = Goal(
          id: g.id,
          title: g.title,
          courseIds: [
            for (final c in g.courseIds)
              if (c != courseId) c,
          ],
          createdAt: g.createdAt,
        );
      }
    }
    final nodes = {
      for (final n in _nodes.values)
        if (n.courseId == courseId) n.id,
    };
    for (final id in nodes) {
      final node = _nodes.remove(id)!;
      if (!deleteNodes) _hiddenNodes[id] = node;
    }
    _edges.removeWhere((e) => nodes.contains(e.fromId) || nodes.contains(e.toId));
    for (final n in _nodes.values.toList()) {
      if (n.linkedCourseId == courseId) _nodes[n.id] = n.copyWith(linkedCourseId: () => null);
    }
    if (deleteNodes) {
      final audits = {
        for (final a in _audits.values)
          if (nodes.contains(a.skillId)) a.id,
      };
      _audits.removeWhere((id, _) => audits.contains(id));
      _principles.removeWhere((p) => audits.contains(p.sourceSessionId));
    }
  }

  /// Nodes of courses deleted keeping their nodes.
  final Map<int, SkillNode> _hiddenNodes = {};

  String _goalTitle(String title) {
    final t = title.trim();
    _require(t.isNotEmpty, 'title must not be blank');
    _require(t.length <= Goal.maxTitleLength, 'title is too long');
    return t;
  }

  // ===========================================================================
  // internals
  // ===========================================================================

  /// Latency, then an injected failure if one matches [method].
  Future<void> _begin(String method) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final index = _failures.indexWhere((f) => f.method == null || f.method == method);
    if (index < 0) return;
    final failure = _failures.removeAt(index);
    final code = failure.statusCode;
    final message = failure.message ?? _defaultFailureMessage(method, code);
    throw code == null ? ApiException.network(message) : ApiException(code, message);
  }

  static String _defaultFailureMessage(String method, int? code) {
    if (code == 502) {
      switch (method) {
        case 'generateCourse':
          return 'Course generation failed. Please try again.';
        case 'submitTurn':
          return 'The auditor is temporarily unavailable. Please try again.';
        case 'submitReflection':
          return 'Principle extraction failed. Please try again.';
        case 'narrate':
          return 'Briefing generation failed. Please try again.';
        case 'generatePlan':
          return 'Plan generation failed. Please try again.';
        case 'createSearchPlan':
          return 'Material search failed. Please try again.';
        default:
          return 'Bad gateway';
      }
    }
    if (code == 404) return 'not found';
    if (code == 422) return 'validation error';
    return 'injected failure';
  }

  /// Request validation (FastAPI answers 422).
  static void _require(bool condition, String message) {
    if (!condition) throw ApiException(422, message);
  }

  // -- audits -----------------------------------------------------------------

  /// The opening of a challenge: the first of the smallest units under it,
  /// or, with none yet, what its main parts are.
  String _testOutQuestion(SkillNode node) {
    final parts = [
      for (final id in descendantsOf(node.id, _edges))
        if (_nodes[id] case final n? when n.unexpanded || containsChildren(id, _edges).isEmpty)
          n.title,
    ];
    if (parts.isEmpty) {
      return 'So you already know “${node.title}”. Prove it: what are its main parts, '
          'and how does the most important one work?';
    }
    return 'So you already know “${node.title}”. Prove it, one part at a time. '
        'Start with “${parts.first}”: how does it work?';
  }

  String _openingQuestion(SkillNode node, NodePosition position) {
    final title = node.title;
    if (node.nodeType == NodeType.task) return 'How exactly will you do “$title”?';
    switch (position) {
      case NodePosition.leaf:
        return 'Explain “$title” from scratch to someone who has never heard of it.';
      case NodePosition.branch:
        final children = containsChildren(
          node.id,
          _edges,
        ).map((id) => _nodes[id]!.title).join(', ');
        return '“$title” covers $children. '
            'Why do these belong together, and when do you use which?';
      case NodePosition.root:
        return 'Which problems call for “$title”, and which don\'t? '
            'How do you decide?';
    }
  }

  static const String _genericProbe =
      'Pick the most important term in your explanation and tell me what it means and why it matters.';
  static const String _challengerQuestion =
      'Before I pass this: give one case where this idea does not hold, and explain why.';

  /// Returns the probe, or — if the turn limit is reached — a failing verdict.
  TurnResult _probeOrForcedFail(_FakeAudit audit, String question, int userTurns) {
    if (userTurns >= audit.maxTurns) {
      return _finishFail(
        audit,
        score: 0,
        gaps: const ["You couldn't explain the core idea within the turn limit."],
        comment: 'The turns ran out before the explanation was complete.',
      );
    }
    audit.turns.add(AuditTurn(role: AuditRole.auditor, content: question));
    return ProbeResult(question: question);
  }

  VerdictResult _finishFail(
    _FakeAudit audit, {
    required int score,
    required List<String> gaps,
    required String comment,
  }) {
    audit
      ..status = AuditStatus.failed
      ..score = score
      ..gaps = gaps
      ..comment = comment;
    return VerdictResult(passed: false, score: score, gaps: gaps, comment: comment);
  }

  VerdictResult _finishPass(_FakeAudit audit, int characters) {
    final score = math.min(95, 70 + characters ~/ 10);
    const comment = 'You explained the core idea and why it holds.';
    audit
      ..status = AuditStatus.passed
      ..score = score
      ..gaps = const []
      ..comment = comment;

    final mastered = _nodes[audit.skillId]!.copyWith(
      status: SkillStatus.mastered,
      masteryScore: score,
    );
    _nodes[mastered.id] = mastered;
    if (audit.testOut) {
      for (final id in descendantsOf(mastered.id, _edges)) {
        final n = _nodes[id];
        if (n != null && !n.isMastered) {
          _nodes[id] = n.copyWith(status: SkillStatus.mastered, testedOut: true);
        }
      }
    }

    final unlocked = _openNext(mastered.courseId);
    _syncLinks();

    // Reward: base 10 × difficulty × 1.1^level (level = mastered nodes ~/ 5 + 1).
    final typeWeight = mastered.nodeType == NodeType.concept ? 2.0 : 1.0;
    final difficulty = typeWeight * (1 + 0.5 * depthOf(mastered.id, _edges));
    final level = _nodes.values.where((n) => n.isMastered).length ~/ 5 + 1;
    final multiplier = (math.pow(1.1, level) * 10000).round() / 10000;

    final reward = (10 * difficulty * multiplier).round();
    audit.reward = reward;
    return VerdictResult(
      passed: true,
      score: score,
      comment: comment,
      unlockedSkillIds: unlocked,
      rewardAmount: reward,
      rewardMultiplier: multiplier,
    );
  }

  /// Memory Retriever: up to 3 lessons, most recent first, from the node
  /// itself, its direct contains/requires neighbours, or principles linked to
  /// those.
  List<Principle> _retrieveLessons(int skillId) {
    final scope = <int>{skillId};
    for (final e in _edges) {
      if (e.fromId == skillId) scope.add(e.toId);
      if (e.toId == skillId) scope.add(e.fromId);
    }
    final hits = {
      for (final p in _principles)
        if (scope.contains(p.skillId)) p.id,
    };
    final linked = <int>{};
    for (final l in _links) {
      if (hits.contains(l.fromId)) linked.add(l.toId);
      if (hits.contains(l.toId)) linked.add(l.fromId);
    }
    final ids = {...hits, ...linked};
    final lessons = [
      for (final p in _principles)
        if (ids.contains(p.id)) p,
    ]..sort((a, b) => b.id.compareTo(a.id));
    return lessons.take(3).toList();
  }

  // -- facts, tiers, briefing ---------------------------------------------------

  Briefing _briefing() =>
      Briefing(facts: _facts(), narrative: _narrative, narrativeGeneratedAt: _narrativeAt);

  ProfileFacts _facts() {
    final nodes = _nodes.values.toList();
    final mastered = nodes.where((n) => n.isMastered).length;
    final passed = _audits.values.where((a) => a.status == AuditStatus.passed).length;
    final failed = _audits.values.where((a) => a.status == AuditStatus.failed).length;
    return ProfileFacts(
      nodes: NodeCounts(
        total: nodes.length,
        mastered: nodes.where((n) => n.isMastered).length,
        available: nodes.where((n) => n.isAvailable).length,
        locked: nodes.where((n) => n.isLocked).length,
      ),
      // Completed audits only (a session abandoned mid-dialogue is not counted).
      audits: AuditCounts(total: passed + failed, passed: passed, failed: failed),
      misconceptionClusters: _clusters(),
      condition: _conditionFacts(),
      xp: XpFacts(
        total: _audits.values.fold(0, (sum, a) => sum + a.reward),
        level: mastered ~/ 5 + 1,
        levelProgress: (mastered % 5) / 5,
      ),
    );
  }

  /// Groups principles whose misconceptions overlap (single linkage over
  /// [_relevance] ≥ 6) into clusters; cross-skill clusters first.
  List<MisconceptionCluster> _clusters() {
    final items = _principles.where((p) => p.hasMisconception).toList();
    final parent = List<int>.generate(items.length, (i) => i);
    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }

    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        if (_relevance(items[i].misconception!, items[j].misconception!) >= 6) {
          final a = find(i);
          final b = find(j);
          if (a != b) parent[math.max(a, b)] = math.min(a, b);
        }
      }
    }

    final groups = <int, List<Principle>>{};
    for (var i = 0; i < items.length; i++) {
      groups.putIfAbsent(find(i), () => []).add(items[i]);
    }
    final clusters = [
      for (final members in groups.values)
        MisconceptionCluster(
          label: members.first.misconception!,
          occurrences: members.length,
          skills: {for (final m in members) m.skillTitle}.toList(),
          crossSkill: {for (final m in members) m.skillId}.length >= 2,
          principleIds: [for (final m in members) m.id],
        ),
    ];
    clusters.sort((a, b) {
      if (a.crossSkill != b.crossSkill) return a.crossSkill ? -1 : 1;
      if (a.occurrences != b.occurrences) return b.occurrences.compareTo(a.occurrences);
      return b.principleIds.last.compareTo(a.principleIds.last);
    });
    return clusters;
  }

  /// Character-bigram overlap plus twice the number of shared latin words.
  static int _relevance(String a, String b) {
    Map<String, int> bigrams(String s) {
      final t = s.replaceAll(RegExp(r'\s+'), '');
      final counts = <String, int>{};
      for (var i = 0; i + 1 < t.length; i++) {
        counts.update(t.substring(i, i + 2), (v) => v + 1, ifAbsent: () => 1);
      }
      return counts;
    }

    Set<String> words(String s) => {
      for (final m in RegExp(r'[A-Za-z0-9]{2,}').allMatches(s)) m.group(0)!.toLowerCase(),
    };

    final ba = bigrams(a);
    final bb = bigrams(b);
    var overlap = 0;
    ba.forEach((k, v) {
      final other = bb[k];
      if (other != null) overlap += math.min(v, other);
    });
    return overlap + 2 * words(a).intersection(words(b)).length;
  }

  /// Condition over the last three check-ins (contract: `ProfileFacts.condition`).
  ConditionFacts _conditionFacts() {
    final recent = (_checkIns.values.toList()..sort((a, b) => b.date.compareTo(a.date)))
        .take(3)
        .toList();
    final sleeps = [
      for (final c in recent)
        if (c.sleepHours != null) c.sleepHours!,
    ];
    final stresses = [
      for (final c in recent)
        if (c.stress != null) c.stress!.toDouble(),
    ];
    final focuses = [
      for (final c in recent)
        if (c.focus != null) c.focus!.toDouble(),
    ];
    double? mean(List<double> v) => v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
    double? round1(double? v) => v == null ? null : (v * 10).round() / 10;

    final avgSleep = mean(sleeps);
    final avgStress = mean(stresses);
    final ConditionFlag flag;
    if (recent.isEmpty) {
      flag = ConditionFlag.unknown;
    } else if ((avgSleep != null && avgSleep < 6) ||
        (avgStress != null && avgStress >= 4) ||
        ((mean(focuses) ?? 5) <= 2)) {
      flag = ConditionFlag.low;
    } else {
      flag = ConditionFlag.normal;
    }
    return ConditionFacts(
      days: recent.length,
      avgSleepHours: round1(avgSleep),
      avgStress: round1(avgStress),
      flag: flag,
    );
  }

  // Not part of the contract's offline script: a simple deterministic heuristic.
  ContextBucket _contextBucket(ConditionFacts c) {
    if (c.flag == ConditionFlag.low) return ContextBucket.low;
    final sleepy = c.avgSleepHours ?? 0;
    if (c.days > 0 && sleepy >= 7.5 && (c.avgStress ?? 0) < 3) return ContextBucket.high;
    return ContextBucket.mid;
  }

  Tier _suggestedTier(ContextBucket bucket) => switch (bucket) {
    ContextBucket.low => Tier.easy,
    ContextBucket.mid => Tier.medium,
    ContextBucket.high => Tier.hard,
  };
}

// =============================================================================
// Mock search, generic helpers
// =============================================================================

/// The first three results of the mock search provider.
List<SearchItem> _mockSearch(String query, {String reason = ''}) => [
  for (var i = 1; i <= 3; i++)
    SearchItem(
      title: '“$query” — resource $i',
      url: 'https://example.org/$i',
      snippet: 'Mock search result $i for “$query”. Offline demo text.',
      reason: reason,
    ),
];

/// Cuts [text] to at most [max] characters (code points).
/// The Planner's title cap (backend `short_title`): at most 48 characters,
/// cut at a word boundary, without a trailing connector or punctuation.
String _shortTitle(String title) {
  const max = 48;
  const connectors = {'and', 'or', 'of', 'the', 'a', 'an', 'to', 'in', 'for', 'with', '&'};
  const trailing = ' ,:;-–—/&';
  String trimEnd(String t) {
    var end = t.length;
    while (end > 0 && trailing.contains(t[end - 1])) {
      end--;
    }
    return t.substring(0, end);
  }

  final text = title.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
  if (text.length <= max) return text;
  final head = text.substring(0, max + 1);
  final cut = head.lastIndexOf(' ');
  final short = cut > 0 ? head.substring(0, cut) : text.substring(0, max);
  final words = trimEnd(short).split(' ');
  while (words.length > 1 && connectors.contains(words.last.toLowerCase())) {
    words.removeLast();
  }
  return trimEnd(words.join(' '));
}

String _cut(String text, int max) {
  final runes = text.runes;
  return runes.length <= max ? text : String.fromCharCodes(runes.take(max));
}

// =============================================================================
// Internal records
// =============================================================================

class _FakeAudit {
  _FakeAudit({
    required this.id,
    required this.skillId,
    required this.position,
    required this.maxTurns,
    required this.createdAt,
    this.testOut = false,
  });

  final int id;
  final DateTime createdAt;
  final bool testOut;
  int reward = 0;
  final int skillId;
  final NodePosition position;
  int maxTurns;
  final List<AuditTurn> turns = [];
  AuditStatus status = AuditStatus.active;
  int? score;
  List<String> gaps = const [];
  String? comment;
  bool challenged = false;
  AuditReview? review;
  bool leaked = false;
  int? principleId;

  AuditSession toModel() => AuditSession(
    id: id,
    skillId: skillId,
    nodePosition: position,
    status: status,
    score: score,
    gaps: List.unmodifiable(gaps),
    comment: comment,
    turns: List.unmodifiable(turns),
    testOut: testOut,
  );
}

/// The intents of the Mock front desk.
sealed class _Intent {
  const _Intent();
}

class _None extends _Intent {
  const _None(this.reply);
  final String reply;
}

class _GenerateCourse extends _Intent {
  const _GenerateCourse(this.topic, {this.files = const []});
  final String topic;

  /// Names of the uploaded files the course is built from.
  final List<String> files;
}

class _OpenSkill extends _Intent {
  const _OpenSkill(this.skill);
  final SkillNode skill;
}

class _CheckIn extends _Intent {
  const _CheckIn();
}

class _Plan extends _Intent {
  const _Plan();
}

class _Briefing extends _Intent {
  const _Briefing();
}

class _OpenMap extends _Intent {
  const _OpenMap();
}

class _FakeUpload {
  const _FakeUpload({
    required this.id,
    required this.filename,
    required this.chars,
    required this.createdAt,
  });

  final int id;
  final String filename;
  final int chars;
  final DateTime createdAt;
}

class _Link {
  const _Link(this.fromId, this.toId, this.kind, this.reason);
  final int fromId;
  final int toId;
  final GraphEdgeKind kind;
  final String reason;
}

class _InjectedFailure {
  const _InjectedFailure(this.method, this.statusCode, this.message);
  final String? method;
  final int? statusCode;
  final String? message;
}

// =============================================================================
// Course scripts (contract Section 4.2)
// =============================================================================

class _NodeSpec {
  const _NodeSpec(this.slug, this.title, this.parents, this.description, {this.expand = false});

  final String slug;
  final String title;

  /// Left to break down later ([FakeApiClient.expandSkill]).
  final bool expand;

  /// 1-based positions (in the course's node list) of the contains parents;
  /// the first is the main parent. Empty for the root.
  final List<int> parents;
  final String description;
}

class _RequiresSpec {
  const _RequiresSpec(this.from, this.to, this.reason);

  /// 1-based positions in the course's node list.
  final int from;
  final int to;
  final String reason;
}

const List<_NodeSpec> _mathNodes = [
  _NodeSpec(
    'high-school-math',
    'High School Math',
    [],
    'The backbone of high school math: knowing which tool solves which problem.',
  ),
  _NodeSpec('algebra', 'Algebra', [
    1,
  ], 'Working with numbers and expressions: equations, inequalities, sequences.'),
  _NodeSpec('functions', 'Functions', [
    1,
  ], 'Describing how two variables relate, with formulas and graphs.'),
  _NodeSpec('calculus', 'Calculus', [
    1,
  ], 'Using limits and rates of change to handle slopes and areas.'),
  _NodeSpec('quadratic-equation', 'Quadratic Equations', [
    2,
  ], 'How to solve equations of the form ax²+bx+c=0 and what the roots mean.'),
  _NodeSpec('discriminant', 'Discriminant', [
    5,
  ], 'A tool that tells you the kind of roots from the coefficients alone.'),
  _NodeSpec('root-coefficient', 'Roots and Coefficients', [
    5,
  ], 'The link between the sum and product of the roots and the coefficients.'),
  _NodeSpec('sequences', 'Sequences', [
    2,
  ], 'Numbers listed by a rule, including arithmetic and geometric sequences.'),
  _NodeSpec('linear-function', 'Linear Functions', [
    3,
  ], 'The slope and intercept of the straight line y=ax+b.'),
  _NodeSpec('quadratic-function', 'Quadratic Functions', [
    3,
  ], 'The vertex, axis and x-intercepts of a parabola.'),
  _NodeSpec('sequence-limit', 'Limits of Sequences', [
    4,
    8,
  ], 'The value a sequence approaches as its terms go on forever.'),
  _NodeSpec('derivative', 'Derivatives', [
    4,
  ], 'The instantaneous rate of change at a point, defined as a limit.'),
];

const List<_RequiresSpec> _mathRequires = [
  _RequiresSpec(
    5,
    10,
    'The x-intercepts of a quadratic function are the roots of a quadratic equation.',
  ),
  _RequiresSpec(9, 10, 'You need the graph of a linear function first.'),
  _RequiresSpec(11, 12, 'The derivative is defined as a limit.'),
];

/// The `vision` course, in layers (the server Mock's `_VISION_NODES`).
const List<_NodeSpec> _visionNodes = [
  _NodeSpec(
    'computer-vision',
    'Computer Vision',
    [],
    'Seeing with cameras and code: features, geometry and recognition.',
  ),
  _NodeSpec(
    'image-features',
    'Image Features',
    [1],
    'Points and patches an algorithm can find again: corners and descriptors.',
  ),
  _NodeSpec(
    'harris',
    'Harris Corners',
    [2],
    'Find corners from the structure tensor and explain why edges and flat areas are rejected.',
  ),
  _NodeSpec(
    'sift',
    'SIFT',
    [2],
    'Build scale-invariant keypoints and descriptors and explain how they are matched.',
  ),
  _NodeSpec(
    'geometry',
    'Geometric Vision',
    [1],
    'Cameras and 3D: calibration, homography, epipolar geometry, triangulation.',
    expand: true,
  ),
  _NodeSpec(
    'recognition',
    'Visual Recognition',
    [1],
    'Telling what is in an image: classification, detection, segmentation.',
    expand: true,
  ),
];

/// Generic course: root = topic, branches `Core Concepts` / `Key Methods` / `Applications`,
/// two leaves each.
List<_NodeSpec> _genericNodes(String rootTitle) => [
  _NodeSpec('root', rootTitle, const [], 'The starting point that covers all of “$rootTitle”.'),
  const _NodeSpec('core-concepts', 'Core Concepts', [
    1,
  ], 'The basic ideas that hold this field up.'),
  const _NodeSpec('main-methods', 'Key Methods', [1], 'The standard ways to solve problems.'),
  const _NodeSpec('applications', 'Applications', [
    1,
  ], 'Applying what you learned to real problems.'),
  const _NodeSpec('core-concept-1', 'Core Concepts 1', [2], 'The first core concept.'),
  const _NodeSpec('core-concept-2', 'Core Concepts 2', [2], 'The second core concept.'),
  const _NodeSpec('main-method-1', 'Key Methods 1', [3], 'The first key method.'),
  const _NodeSpec('main-method-2', 'Key Methods 2', [3], 'The second key method.'),
  const _NodeSpec('application-1', 'Applications 1', [4], 'The first application.'),
  const _NodeSpec('application-2', 'Applications 2', [4], 'The second application.'),
];

const List<_RequiresSpec> _genericRequires = [
  _RequiresSpec(5, 7, 'You need the core concepts before using this method.'),
  _RequiresSpec(7, 9, 'You need the method before you can apply it.'),
];

// =============================================================================
// Check-in parsing (contract Section 4.5)
// =============================================================================

typedef _Parsed = ({
  double? sleepHours,
  bool? exercised,
  String? dietNote,
  int? focus,
  int? stress,
});

final RegExp _weightPattern = RegExp(
  r'\b(\d+(?:\.\d+)?)\s*(?:kg|kilos?|kilograms?)\b',
  caseSensitive: false,
);
final RegExp _minutesPattern = RegExp(
  r'\b(?:ran|run|jogged|walked|swam|cycled|exercised|worked out|gym|yoga)\b[^.!?\n]*?\b(\d+)\s*(?:minutes?|mins?)\b'
  r'|\b(\d+)\s*(?:minutes?|mins?)\s+(?:of\s+)?(?:running|exercise|workout|walking|swimming|cycling|yoga)\b',
  caseSensitive: false,
);
final RegExp _sleepQualityPattern = RegExp(
  r'\bsleep quality (?:was |is |of )?(\d)\b',
  caseSensitive: false,
);

final RegExp _injuredPattern = RegExp(
  r'\b(?:hurt|injured|sprained|broke|pulled) my (\w+)|\bmy (\w+) (?:is|got) (?:injured|hurt|sprained)',
  caseSensitive: false,
);
final RegExp _healedPattern = RegExp(
  r'\bmy (\w+) (?:is|feels) (?:fine|better|healed|ok|okay)\b|\b(\w+) (?:has )?healed\b',
  caseSensitive: false,
);
final RegExp _nightShiftPattern = RegExp(r'\bnight shifts?\b', caseSensitive: false);
final RegExp _dietPattern = RegExp(r'\b(vegetarian|vegan)\b', caseSensitive: false);
final RegExp _examsPattern = RegExp(r'\bexams? until ([^.,!?\n]+)', caseSensitive: false);

/// Weight, minutes of exercise and a numbered sleep quality, only when said
/// (the server Mock's `_checkin_extras`).
double? _parseWeight(String text) {
  final m = _weightPattern.firstMatch(text);
  return m == null ? null : double.parse(m.group(1)!);
}

int? _parseExerciseMinutes(String text) {
  final m = _minutesPattern.firstMatch(text);
  return m == null ? null : int.parse(m.group(1) ?? m.group(2)!);
}

int? _parseSleepQuality(String text) {
  final m = _sleepQualityPattern.firstMatch(text);
  return m == null ? null : int.parse(m.group(1)!);
}

_Parsed _parseTranscript(String text) {
  // English rules first; the Korean rules below stay as a fallback because
  // user content may still be Korean.
  final t = text.replaceAll('\u2019', "'");
  return (
    sleepHours: _parseSleepEn(t) ?? _parseSleep(text),
    exercised: _parseExerciseEn(t) ?? _parseExercise(text),
    dietNote: _parseDietEn(t) ?? _parseDiet(text),
    focus: _parseFocusEn(t) ?? _parseFocus(text),
    stress: _parseStressEn(t) ?? _parseStress(text),
  );
}

const Map<String, double> _englishNumbers = {
  'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
  'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12, //
};

final RegExp _sleepPatternEn = RegExp(
  r'(\d+(?:\.\d+)?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s*(?:hours?|hrs?|h)\b',
  caseSensitive: false,
);

/// A number (digits or `one`…`twelve`) followed by `hour(s)` / `h`, in a
/// sentence that mentions `sleep` / `slept`.
double? _parseSleepEn(String text) {
  for (final sentence in text.split(RegExp(r'[.!?\n](?!\d)'))) {
    if (!RegExp(r'sleep|slept', caseSensitive: false).hasMatch(sentence)) continue;
    for (final m in _sleepPatternEn.allMatches(sentence)) {
      final token = m.group(1)!.toLowerCase();
      final value = _englishNumbers[token] ?? double.tryParse(token);
      if (value != null && value >= 0 && value <= 14) return value;
    }
    // "slept from 11 to 7": the clock hours apart, on a 12-hour dial.
    final span = _sleepSpanPattern.firstMatch(sentence);
    if (span != null) {
      final hours = (int.parse(span.group(2)!) - int.parse(span.group(1)!)) % 12;
      if (hours > 0) return hours.toDouble();
    }
  }
  return null;
}

final RegExp _sleepSpanPattern = RegExp(
  r'\bfrom (\d{1,2})(?::\d\d)?\s*(?:pm|am)? (?:to|until|till) (\d{1,2})\b',
  caseSensitive: false,
);

/// `didn't exercise` / `no exercise` / `skipped the gym` / `didn't work out`
/// → false; `exercised` / `worked out` / `went to the gym` / `went for a run`
/// → true.
bool? _parseExerciseEn(String text) {
  final lower = text.toLowerCase();
  if (RegExp(
    r"didn't exercise|did not exercise|no exercise|skipped (?:the )?gym|didn't work out|did not work out",
  ).hasMatch(lower)) {
    return false;
  }
  if (RegExp(r'exercised|worked out|went to the gym|went for a run').hasMatch(lower)) return true;
  return null;
}

/// `had ramen for lunch` → `lunch: ramen`; also `for lunch I had ramen`.
String? _parseDietEn(String text) {
  const food = r'((?:(?!\b(?:had|ate)\b)[^.!?,\n])+?)';
  const meal = r'(breakfast|lunch|dinner)';
  RegExpMatch? m = RegExp(
    '\\b(?:had|ate)\\s+$food\\s+for\\s+$meal\\b',
    caseSensitive: false,
  ).firstMatch(text);
  var mealName = m?.group(2);
  var what = m?.group(1);
  if (m == null) {
    m = RegExp(
      '\\bfor\\s+$meal\\b[^.!?\\n]*?\\b(?:had|ate)\\s+([^.!?,\\n]+?)(?=\\s+(?:and|but)\\b|[.!?,\\n]|\$)',
      caseSensitive: false,
    ).firstMatch(text);
    mealName = m?.group(1);
    what = m?.group(2);
  }
  if (m == null || mealName == null || what == null) return null;
  what = what.trim().replaceFirst(RegExp(r'^(?:a|an|the|some)\s+', caseSensitive: false), '');
  if (what.isEmpty) return null;
  return '${mealName.toLowerCase()}: $what';
}

/// `focused well` → 4; `couldn't focus` → 2.
int? _parseFocusEn(String text) {
  final lower = text.toLowerCase();
  if (RegExp(r"couldn't focus|could not focus").hasMatch(lower)) return 2;
  if (lower.contains('focused well')) return 4;
  return null;
}

/// `stressed` / `a lot of stress` → 4; `relaxed` / `no stress` → 2.
int? _parseStressEn(String text) {
  final lower = text.toLowerCase();
  if (RegExp(r"relaxed|no stress|not stressed|wasn't stressed").hasMatch(lower)) return 2;
  if (RegExp(r'stressed|a lot of stress').hasMatch(lower)) return 4;
  return null;
}

const Map<String, double> _koreanNumbers = {
  '한': 1, '두': 2, '세': 3, '네': 4, '다섯': 5, '여섯': 6, '일곱': 7, '여덟': 8, '아홉': 9, //
  '열': 10, '열한': 11, '열두': 12, '열세': 13, '열네': 14,
};

final RegExp _sleepPattern = RegExp(r'(\d+(?:\.\d+)?|열한|열두|열세|열네|다섯|여섯|일곱|여덟|아홉|열|한|두|세|네)\s*시간');

/// Korean fallback: a number (digits or `한 두 세 …`) followed by `시간`.
double? _parseSleep(String text) {
  for (final m in _sleepPattern.allMatches(text)) {
    final token = m.group(1)!;
    final value = _koreanNumbers[token] ?? double.tryParse(token);
    if (value != null && value >= 0 && value <= 14) return value;
  }
  return null;
}

/// `운동` + `안 했/안했/못 했/못했/쉬었` → false; `운동` + `했/갔` → true.
bool? _parseExercise(String text) {
  final i = text.indexOf('운동');
  if (i < 0) return null;
  final m = RegExp(r'안\s*했|못\s*했|쉬었|했|갔').firstMatch(text.substring(i + 2));
  if (m == null) return null;
  final hit = m.group(0)!;
  return !(hit.startsWith('안') || hit.startsWith('못') || hit.startsWith('쉬'));
}

/// `(아침|점심|저녁)` + the word before `먹` → e.g. `점심 라면`.
String? _parseDiet(String text) {
  final m = RegExp(r'(아침|점심|저녁)[^.!?\n]*?\s([^\s먹.!?,]+)\s*먹').firstMatch(text);
  if (m == null) return null;
  var food = m.group(2)!;
  if (food.length > 1 && (food.endsWith('을') || food.endsWith('를'))) {
    food = food.substring(0, food.length - 1);
  }
  if (food == '안' || food == '못') return null; // "점심은 안 먹었어요" names no food
  return '${m.group(1)} $food';
}

const List<String> _topicWords = ['집중', '스트레스', '운동', '아침', '점심', '저녁', '시간', '수면'];

/// The text after [keyword] up to the end of that thought: a sentence end,
/// comma, connective (`…고 `, `는데`, `지만`) or another topic word.
String? _clauseAfter(String text, String keyword) {
  final i = text.indexOf(keyword);
  if (i < 0) return null;
  final rest = text.substring(i + keyword.length);
  final others = _topicWords.where((w) => w != keyword).join('|');
  final stop = RegExp('[.!?,\\n]|고\\s|고\$|는데|지만|$others').firstMatch(rest);
  return stop == null ? rest : rest.substring(0, stop.start);
}

final RegExp _negation = RegExp(r'(?:^|\s)(?:안|못)(?:\s|[됐되돼했하])|지\s*(?:는\s*)?(?:않|못)');

/// `집중` with `잘` → 4; with `안` / `못` → 2.
int? _parseFocus(String text) {
  final clause = _clauseAfter(text, '집중');
  if (clause == null) return null;
  if (_negation.hasMatch(clause)) return 2;
  return clause.contains('잘') ? 4 : null;
}

/// `스트레스` with `많` / `심` / `높` → 4; with `없` / `적` / `낮` → 2.
/// A negation (`많지 않아요`) flips the result.
int? _parseStress(String text) {
  final clause = _clauseAfter(text, '스트레스');
  if (clause == null) return null;
  final high = RegExp('많|심|높').firstMatch(clause);
  final low = RegExp('없|적|낮').firstMatch(clause);
  int? value;
  if (high != null && (low == null || high.start < low.start)) {
    value = 4;
  } else if (low != null) {
    value = 2;
  }
  if (value == null) return null;
  if (RegExp(r'지\s*(?:는\s*)?않|(?:^|\s)안\s*(?:많|심|높|적|낮|없)').hasMatch(clause)) {
    value = value == 4 ? 2 : 4;
  }
  return value;
}

/// Cohen's kappa over (auditor passed, human passed) pairs; null when it is
/// undefined (no pairs, or both always gave the same verdict).
double? cohensKappa(List<(bool, bool)> pairs) {
  if (pairs.isEmpty) return null;
  final n = pairs.length;
  final observed = pairs.where((p) => p.$1 == p.$2).length / n;
  final auditor = pairs.where((p) => p.$1).length / n;
  final human = pairs.where((p) => p.$2).length / n;
  final chance = auditor * human + (1 - auditor) * (1 - human);
  if (chance == 1) return null;
  return (((observed - chance) / (1 - chance)) * 10000).roundToDouble() / 10000;
}
