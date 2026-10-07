/// Typed, immutable models for every JSON shape in `docs/api-contract.md`
/// (Section 2 shared types plus the Section 3 response bodies).
///
/// Conventions
/// * Hand-written `fromJson` factories; no code generation.
/// * Enums carry their wire string in `value` and parse with `Enum.fromJson`,
///   which throws a [FormatException] on an unknown value.
/// * Datetimes are parsed as UTC. Display them with [formatKst] / [toKst].
/// * Lists inside models are unmodifiable. Treat every model as immutable.
/// * `toJson` exists only where the type is sent to the server
///   ([GenerateRequest]).
library;

import 'package:flutter/foundation.dart' show immutable;
import 'package:intl/intl.dart';

/// A decoded JSON object.
typedef Json = Map<String, dynamic>;

// ---------------------------------------------------------------------------
// JSON access helpers (private)
// ---------------------------------------------------------------------------

FormatException _bad(String what, Object? raw) =>
    FormatException('Invalid "$what": ${raw == null ? 'null' : '$raw (${raw.runtimeType})'}');

int _int(Json j, String key) {
  final v = j[key];
  if (v is int) return v;
  if (v is num && v == v.roundToDouble()) return v.toInt();
  throw _bad(key, v);
}

int? _intN(Json j, String key) => j[key] == null ? null : _int(j, key);

double _double(Json j, String key) {
  final v = j[key];
  if (v is num) return v.toDouble();
  throw _bad(key, v);
}

double? _doubleN(Json j, String key) => j[key] == null ? null : _double(j, key);

String _str(Json j, String key) {
  final v = j[key];
  if (v is String) return v;
  throw _bad(key, v);
}

String? _strN(Json j, String key) {
  final v = j[key];
  if (v == null) return null;
  if (v is String) return v;
  throw _bad(key, v);
}

bool _bool(Json j, String key) {
  final v = j[key];
  if (v is bool) return v;
  throw _bad(key, v);
}

bool? _boolN(Json j, String key) {
  final v = j[key];
  if (v == null) return null;
  if (v is bool) return v;
  throw _bad(key, v);
}

Json _obj(Json j, String key) => _asJson(j[key], key);

Json _asJson(Object? v, String what) {
  if (v is Map) return Map<String, dynamic>.from(v);
  throw _bad(what, v);
}

List<T> _list<T>(Json j, String key, T Function(Json item) parse) {
  final v = j[key];
  if (v == null) return const [];
  if (v is! List) throw _bad(key, v);
  return List<T>.unmodifiable(v.map((e) => parse(_asJson(e, key))));
}

List<String> _strList(Json j, String key) {
  final v = j[key];
  if (v == null) return const [];
  if (v is! List) throw _bad(key, v);
  return List<String>.unmodifiable(
    v.map((e) {
      if (e is String) return e;
      throw _bad(key, e);
    }),
  );
}

List<int> _intList(Json j, String key) {
  final v = j[key];
  if (v == null) return const [];
  if (v is! List) throw _bad(key, v);
  return List<int>.unmodifiable(
    v.map((e) {
      if (e is int) return e;
      if (e is num && e == e.roundToDouble()) return e.toInt();
      throw _bad(key, e);
    }),
  );
}

DateTime _time(Json j, String key) {
  final v = j[key];
  if (v is String) {
    try {
      return parseUtc(v);
    } on FormatException {
      throw _bad(key, v);
    }
  }
  throw _bad(key, v);
}

DateTime? _timeN(Json j, String key) => j[key] == null ? null : _time(j, key);

T _enumFrom<T extends Enum>(List<T> values, String Function(T) wire, Object? raw, String name) {
  for (final v in values) {
    if (wire(v) == raw) return v;
  }
  throw FormatException('Unknown $name: $raw');
}

// ---------------------------------------------------------------------------
// Time helpers (UTC on the wire, KST for display)
// ---------------------------------------------------------------------------

/// `Asia/Seoul` is a fixed UTC+9 with no daylight saving time.
const Duration kstOffset = Duration(hours: 9);

/// Parses an ISO 8601 datetime and returns it in UTC.
///
/// The contract guarantees an explicit offset (`Z` or `+00:00`). A string
/// without an offset is interpreted as UTC as well.
DateTime parseUtc(String iso) {
  final t = DateTime.parse(iso);
  if (t.isUtc) return t;
  return DateTime.utc(
    t.year,
    t.month,
    t.day,
    t.hour,
    t.minute,
    t.second,
    t.millisecond,
    t.microsecond,
  );
}

/// Shifts [t] to Korea Standard Time.
///
/// Caution: the returned [DateTime] is flagged UTC but its fields (`hour`,
/// `day`, ...) hold the **KST wall-clock** values. Use it only to read
/// components; prefer [formatKst] / [formatKstDate] for display.
DateTime toKst(DateTime t) => t.toUtc().add(kstOffset);

/// Formats [t] in KST. The default pattern is `2026.10.05 12:12`.
///
/// [pattern] is an `intl` [DateFormat] pattern such as `'yyyy-MM-dd'`.
String formatKst(DateTime t, {String pattern = 'yyyy.MM.dd HH:mm'}) =>
    DateFormat(pattern).format(toKst(t));

/// How [formatLocal] writes a date, in the app's language (`Intl.defaultLocale`).
enum DateStyle {
  /// `Oct 2, 2026` · `2026年10月2日` · `2026. 10. 2.`
  date,

  /// `Oct 2` · `10月2日` · `10월 2일`
  monthDay,

  /// `Oct 2, 2026 11:04` · `2026年10月2日 11:04` · `2026. 10. 2. 11:04`
  dateTime,

  /// `11:04` (24 h)
  time,
}

/// Formats [t] in the device's local time zone, in the app's language. This
/// is what chat dates and times show.
String formatLocal(DateTime t, {DateStyle style = DateStyle.date}) {
  final format = switch (style) {
    DateStyle.date => DateFormat.yMMMd(),
    DateStyle.monthDay => DateFormat.MMMd(),
    DateStyle.dateTime => DateFormat.yMMMd().add_Hm(),
    DateStyle.time => DateFormat.Hm(),
  };
  return format.format(t.toLocal());
}

/// Formats the KST calendar date of [t] as `YYYY-MM-DD`
/// (the format of `DailyCheckIn.date`).
String formatKstDate(DateTime t) => formatKst(t, pattern: 'yyyy-MM-dd');

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// `SkillNode.status`.
enum SkillStatus {
  locked('locked'),
  available('available'),
  mastered('mastered');

  const SkillStatus(this.value);

  /// The wire string.
  final String value;

  static SkillStatus fromJson(Object? raw) => _enumFrom(values, (e) => e.value, raw, 'SkillStatus');
}

/// `SkillNode.node_type`.
enum NodeType {
  concept('concept'),
  task('task');

  const NodeType(this.value);
  final String value;

  static NodeType fromJson(Object? raw) => _enumFrom(values, (e) => e.value, raw, 'NodeType');
}

/// `SkillEdge.kind`.
enum SkillEdgeKind {
  contains('contains'),
  requires('requires');

  const SkillEdgeKind(this.value);
  final String value;

  static SkillEdgeKind fromJson(Object? raw) =>
      _enumFrom(values, (e) => e.value, raw, 'SkillEdgeKind');
}

/// Position of a node in the contains tree (computed, see `positionOf`).
enum NodePosition {
  root('root'),
  branch('branch'),
  leaf('leaf');

  const NodePosition(this.value);
  final String value;

  static NodePosition fromJson(Object? raw) =>
      _enumFrom(values, (e) => e.value, raw, 'NodePosition');
}

/// `AuditSession.status`.
enum AuditStatus {
  active('active'),
  passed('passed'),
  failed('failed');

  const AuditStatus(this.value);
  final String value;

  static AuditStatus fromJson(Object? raw) => _enumFrom(values, (e) => e.value, raw, 'AuditStatus');
}

/// `AuditTurn.role`.
enum AuditRole {
  user('user'),
  auditor('auditor');

  const AuditRole(this.value);
  final String value;

  static AuditRole fromJson(Object? raw) => _enumFrom(values, (e) => e.value, raw, 'AuditRole');
}

/// Difficulty tiers: `skill_tiers`, `suggested_tier`.
enum Tier {
  easy('easy'),
  medium('medium'),
  hard('hard');

  const Tier(this.value);
  final String value;

  static Tier fromJson(Object? raw) => _enumFrom(values, (e) => e.value, raw, 'Tier');
}

/// `context_bucket` of the recommender.
enum ContextBucket {
  low('low'),
  mid('mid'),
  high('high');

  const ContextBucket(this.value);
  final String value;

  static ContextBucket fromJson(Object? raw) =>
      _enumFrom(values, (e) => e.value, raw, 'ContextBucket');
}

/// `ProfileFacts.condition.flag`.
enum ConditionFlag {
  normal('normal'),
  low('low'),
  unknown('unknown');

  const ConditionFlag(this.value);
  final String value;

  static ConditionFlag fromJson(Object? raw) =>
      _enumFrom(values, (e) => e.value, raw, 'ConditionFlag');
}

/// `DailyCheckIn.source`.
enum CheckInSource {
  voice('voice'),
  manual('manual');

  const CheckInSource(this.value);
  final String value;

  static CheckInSource fromJson(Object? raw) =>
      _enumFrom(values, (e) => e.value, raw, 'CheckInSource');
}

/// The five check-in fields, in the order of `missing_fields`.
enum CheckInField {
  sleepHours('sleep_hours'),
  exercised('exercised'),
  dietNote('diet_note'),
  focus('focus'),
  stress('stress');

  const CheckInField(this.value);
  final String value;

  static CheckInField fromJson(Object? raw) =>
      _enumFrom(values, (e) => e.value, raw, 'CheckInField');
}

/// `GenerateRequest.difficulty` (the depth profile).
enum Difficulty {
  intro('intro'),
  standard('standard'),
  deep('deep');

  const Difficulty(this.value);
  final String value;

  static Difficulty fromJson(Object? raw) => _enumFrom(values, (e) => e.value, raw, 'Difficulty');
}

/// `GraphNode.kind`.
enum GraphNodeKind {
  skill('skill'),
  principle('principle');

  const GraphNodeKind(this.value);
  final String value;

  static GraphNodeKind fromJson(Object? raw) =>
      _enumFrom(values, (e) => e.value, raw, 'GraphNodeKind');
}

/// `GraphEdge.kind` — the five edge kinds of the knowledge graph.
enum GraphEdgeKind {
  contains('contains'),
  requires('requires'),
  origin('origin'),
  related('related'),
  contradicts('contradicts');

  const GraphEdgeKind(this.value);
  final String value;

  static GraphEdgeKind fromJson(Object? raw) =>
      _enumFrom(values, (e) => e.value, raw, 'GraphEdgeKind');
}

// ---------------------------------------------------------------------------
// Courses and the skill graph
// ---------------------------------------------------------------------------

/// A learning course (UI name: quest line). Contract: `Course`.
@immutable
class Course {
  const Course({
    required this.id,
    required this.topic,
    this.sourceCourse,
    this.sourceUrl,
    required this.createdAt,
  });

  factory Course.fromJson(Json json) => Course(
    id: _int(json, 'id'),
    topic: _str(json, 'topic'),
    sourceCourse: _strN(json, 'source_course'),
    sourceUrl: _strN(json, 'source_url'),
    createdAt: _time(json, 'created_at'),
  );

  final int id;

  /// The text sent to `/skills/generate`, including clarification answers.
  /// Display [title] instead.
  final String topic;

  /// Name of the real syllabus the course is based on, or null.
  final String? sourceCourse;

  /// URL of that syllabus; null for a course made from uploaded files, where
  /// [sourceCourse] holds the file names.
  final String? sourceUrl;

  /// UTC.
  final DateTime createdAt;

  /// First line of [topic] — what the UI shows.
  String get title {
    final first = topic.split('\n').first.trim();
    return first.isEmpty ? topic.trim() : first;
  }

  /// Whether the course names where its outline came from: a real syllabus
  /// (with [sourceUrl]) or an uploaded file (without one; several files are
  /// joined with `, `).
  bool get hasSource => sourceCourse != null;

  /// Whether the source can be opened ([sourceUrl] is set).
  bool get hasSourceLink => sourceCourse != null && sourceUrl != null;
}

/// One node of a course. Contract: `SkillNode`.
@immutable
class SkillNode {
  const SkillNode({
    required this.id,
    required this.courseId,
    required this.slug,
    required this.title,
    required this.description,
    required this.status,
    required this.nodeType,
    this.masteryScore,
  });

  factory SkillNode.fromJson(Json json) => SkillNode(
    id: _int(json, 'id'),
    courseId: _int(json, 'course_id'),
    slug: _str(json, 'slug'),
    title: _str(json, 'title'),
    description: _strN(json, 'description') ?? '',
    status: SkillStatus.fromJson(json['status']),
    nodeType: NodeType.fromJson(json['node_type']),
    masteryScore: _intN(json, 'mastery_score'),
  );

  final int id;
  final int courseId;
  final String slug;
  final String title;
  final String description;
  final SkillStatus status;
  final NodeType nodeType;

  /// 0–100, written when an audit passes; otherwise null.
  final int? masteryScore;

  bool get isLocked => status == SkillStatus.locked;
  bool get isAvailable => status == SkillStatus.available;
  bool get isMastered => status == SkillStatus.mastered;

  SkillNode copyWith({SkillStatus? status, NodeType? nodeType, int? masteryScore}) => SkillNode(
    id: id,
    courseId: courseId,
    slug: slug,
    title: title,
    description: description,
    status: status ?? this.status,
    nodeType: nodeType ?? this.nodeType,
    masteryScore: masteryScore ?? this.masteryScore,
  );
}

/// An edge between two skill nodes. Contract: `SkillEdge`.
///
/// * `contains`: [fromId] is the parent, [toId] the child; [isPrimary] marks
///   the main parent; [reason] is null.
/// * `requires`: [fromId] is learned first, [toId] after; [isPrimary] is null;
///   [reason] is a sentence or null.
@immutable
class SkillEdge {
  const SkillEdge({
    required this.fromId,
    required this.toId,
    required this.kind,
    this.isPrimary,
    this.reason,
  });

  factory SkillEdge.fromJson(Json json) => SkillEdge(
    fromId: _int(json, 'from_id'),
    toId: _int(json, 'to_id'),
    kind: SkillEdgeKind.fromJson(json['kind']),
    isPrimary: _boolN(json, 'is_primary'),
    reason: _strN(json, 'reason'),
  );

  final int fromId;
  final int toId;
  final SkillEdgeKind kind;
  final bool? isPrimary;
  final String? reason;

  bool get isContains => kind == SkillEdgeKind.contains;
  bool get isRequires => kind == SkillEdgeKind.requires;
}

/// `{course, nodes, edges}` — the body of `POST /skills/generate` and
/// `GET /courses/{id}/map`.
@immutable
class CourseMap {
  const CourseMap({required this.course, required this.nodes, required this.edges});

  factory CourseMap.fromJson(Json json) => CourseMap(
    course: Course.fromJson(_obj(json, 'course')),
    nodes: _list(json, 'nodes', SkillNode.fromJson),
    edges: _list(json, 'edges', SkillEdge.fromJson),
  );

  final Course course;

  /// Ordered by id.
  final List<SkillNode> nodes;

  /// Edges of both kinds.
  final List<SkillEdge> edges;

  /// The node with [id], or null.
  SkillNode? nodeById(int id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }
}

/// Body of `POST /skills/generate`. Contract endpoint 2.
@immutable
class GenerateRequest {
  const GenerateRequest({
    required this.topic,
    this.nodeCount = 12,
    this.maxDepth = 4,
    this.difficulty = Difficulty.standard,
    this.searchSyllabus = true,
  });

  /// Topic text, optionally with clarification answers (see [composeTopic]).
  final String topic;

  /// 4–30.
  final int nodeCount;

  /// 2–6 levels.
  final int maxDepth;
  final Difficulty difficulty;

  /// Try to find a real syllabus (`Find a real syllabus`).
  final bool searchSyllabus;

  Json toJson() => {
    'topic': topic,
    'node_count': nodeCount,
    'max_depth': maxDepth,
    'difficulty': difficulty.value,
    'search_syllabus': searchSyllabus,
  };
}

/// Builds the topic that is sent to `/skills/generate` from the user's topic
/// and the answers to the clarifying questions (contract endpoint 1, "Client
/// rule"):
///
/// ```
/// {topic}
///
/// Q: {question 1}
/// A: {answer 1}
/// Q: {question 2}
/// A: {answer 2}
/// ```
///
/// [answers] maps each question to its answer, in question order. Questions
/// with a blank answer are omitted; with no answered question the result is
/// just the trimmed [topic].
String composeTopic(String topic, Map<String, String> answers) {
  final buffer = StringBuffer(topic.trim());
  var first = true;
  for (final entry in answers.entries) {
    final answer = entry.value.trim();
    if (answer.isEmpty) continue;
    buffer.write(first ? '\n\n' : '\n');
    buffer.write('Q: ${entry.key.trim()}\nA: $answer');
    first = false;
  }
  return buffer.toString();
}

/// Body of `POST /skills/clarify`. Contract endpoint 1.
@immutable
class ClarifyResult {
  const ClarifyResult({required this.needsClarification, required this.questions});

  factory ClarifyResult.fromJson(Json json) => ClarifyResult(
    needsClarification: _bool(json, 'needs_clarification'),
    questions: _strList(json, 'questions'),
  );

  final bool needsClarification;

  /// At most two questions.
  final List<String> questions;
}

/// One course the scout offers for a vague answer.
@immutable
class ScoutOption {
  const ScoutOption({required this.topic, required this.why});

  factory ScoutOption.fromJson(Json json) =>
      ScoutOption(topic: _str(json, 'topic'), why: _strN(json, 'why') ?? '');

  final String topic;

  /// One line on why it helps the main quest.
  final String why;
}

/// Body of `POST /skills/scout`: how the tutorial reads the first course the
/// player typed. [isClear]: build [topic]. Otherwise show [question] and the
/// [options] to pick from.
@immutable
class CourseScout {
  const CourseScout({
    required this.isClear,
    this.topic = '',
    this.question = '',
    this.options = const [],
  });

  factory CourseScout.fromJson(Json json) => CourseScout(
    isClear: _str(json, 'kind') != 'choose',
    topic: _strN(json, 'topic') ?? '',
    question: _strN(json, 'question') ?? '',
    options: _list(json, 'options', ScoutOption.fromJson),
  );

  final bool isClear;
  final String topic;
  final String question;
  final List<ScoutOption> options;
}

/// Body of `GET /skills/recommendation`. Contract endpoint 6.
@immutable
class Recommendation {
  const Recommendation({
    required this.contextBucket,
    required this.suggestedTier,
    required this.skillTiers,
  });

  factory Recommendation.fromJson(Json json) {
    final tiers = _obj(json, 'skill_tiers');
    return Recommendation(
      contextBucket: ContextBucket.fromJson(json['context_bucket']),
      suggestedTier: Tier.fromJson(json['suggested_tier']),
      skillTiers: Map<int, Tier>.unmodifiable({
        for (final e in tiers.entries) int.parse(e.key): Tier.fromJson(e.value),
      }),
    );
  }

  final ContextBucket contextBucket;
  final Tier suggestedTier;

  /// One entry per skill node, keyed by skill id.
  final Map<int, Tier> skillTiers;

  /// The tier of [skillId], or null when unknown.
  Tier? tierOf(int skillId) => skillTiers[skillId];
}

// ---------------------------------------------------------------------------
// Audits
// ---------------------------------------------------------------------------

/// One message of an audit dialogue. Contract: `AuditSession.turns[]`.
@immutable
class AuditTurn {
  const AuditTurn({required this.role, required this.content});

  factory AuditTurn.fromJson(Json json) =>
      AuditTurn(role: AuditRole.fromJson(json['role']), content: _str(json, 'content'));

  final AuditRole role;
  final String content;

  bool get isUser => role == AuditRole.user;
}

/// An audit session. Contract: `AuditSession`.
@immutable
class AuditSession {
  const AuditSession({
    required this.id,
    required this.skillId,
    required this.nodePosition,
    required this.status,
    this.score,
    this.gaps = const [],
    this.comment,
    this.turns = const [],
  });

  factory AuditSession.fromJson(Json json) => AuditSession(
    id: _int(json, 'id'),
    skillId: _int(json, 'skill_id'),
    nodePosition: NodePosition.fromJson(json['node_position']),
    status: AuditStatus.fromJson(json['status']),
    score: _intN(json, 'score'),
    gaps: _strList(json, 'gaps'),
    comment: _strN(json, 'comment'),
    turns: _list(json, 'turns', AuditTurn.fromJson),
  );

  final int id;
  final int skillId;
  final NodePosition nodePosition;
  final AuditStatus status;
  final int? score;
  final List<String> gaps;
  final String? comment;

  /// The opening question is the first auditor turn.
  final List<AuditTurn> turns;
}

/// Body of `POST /skills/{id}/audits`. Contract endpoint 7.
@immutable
class AuditStart {
  const AuditStart({required this.session, required this.openingQuestion});

  factory AuditStart.fromJson(Json json) => AuditStart(
    session: AuditSession.fromJson(_obj(json, 'session')),
    openingQuestion: _str(json, 'opening_question'),
  );

  final AuditSession session;
  final String openingQuestion;
}

/// Result of `POST /audits/{id}/turns` — exactly one of [ProbeResult] or
/// [VerdictResult]. Use a `switch` over the sealed type.
///
/// A Challenger overturn is returned as a [ProbeResult]; the API does not
/// distinguish it from an Auditor probe.
sealed class TurnResult {
  const TurnResult();

  factory TurnResult.fromJson(Json json) {
    switch (json['type']) {
      case 'probe':
        return ProbeResult.fromJson(json);
      case 'verdict':
        return VerdictResult.fromJson(json);
      default:
        throw _bad('type', json['type']);
    }
  }
}

/// The auditor asks a follow-up question.
final class ProbeResult extends TurnResult {
  const ProbeResult({required this.question});

  factory ProbeResult.fromJson(Json json) => ProbeResult(question: _str(json, 'question'));

  final String question;
}

/// The final verdict of an audit.
final class VerdictResult extends TurnResult {
  const VerdictResult({
    required this.passed,
    required this.score,
    this.gaps = const [],
    this.comment,
    this.unlockedSkillIds = const [],
    this.rewardAmount,
    this.rewardMultiplier,
  });

  factory VerdictResult.fromJson(Json json) => VerdictResult(
    passed: _bool(json, 'passed'),
    score: _int(json, 'score'),
    gaps: _strList(json, 'gaps'),
    comment: _strN(json, 'comment'),
    unlockedSkillIds: _intList(json, 'unlocked_skill_ids'),
    rewardAmount: _intN(json, 'reward_amount'),
    rewardMultiplier: _doubleN(json, 'reward_multiplier'),
  );

  final bool passed;

  /// 0–100.
  final int score;

  /// Empty on a pass.
  final List<String> gaps;
  final String? comment;

  /// Nodes that changed from locked to available (pass only).
  final List<int> unlockedSkillIds;

  /// XP, set on a pass only.
  final int? rewardAmount;
  final double? rewardMultiplier;
}

// ---------------------------------------------------------------------------
// Principles (lesson cards) and the knowledge graph
// ---------------------------------------------------------------------------

/// A lesson card produced from a failed audit. Contract: `Principle`.
/// Limits: title ≤ 20, body ≤ 80, misconception ≤ 40 characters.
@immutable
class Principle {
  const Principle({
    required this.id,
    required this.title,
    required this.body,
    this.misconception,
    required this.sourceSessionId,
    required this.skillId,
    required this.skillTitle,
    required this.createdAt,
  });

  factory Principle.fromJson(Json json) => Principle(
    id: _int(json, 'id'),
    title: _str(json, 'title'),
    body: _str(json, 'body'),
    misconception: _strN(json, 'misconception'),
    sourceSessionId: _int(json, 'source_session_id'),
    skillId: _int(json, 'skill_id'),
    skillTitle: _str(json, 'skill_title'),
    createdAt: _time(json, 'created_at'),
  );

  final int id;
  final String title;
  final String body;

  /// May be null or empty (then search by misconception is unavailable).
  final String? misconception;
  final int sourceSessionId;

  /// The node the source audit was about.
  final int skillId;
  final String skillTitle;

  /// UTC.
  final DateTime createdAt;

  bool get hasMisconception => misconception != null && misconception!.trim().isNotEmpty;
}

/// A node of the knowledge graph. Contract: `Graph.nodes[]`.
///
/// [id] is `"skill:5"` or `"principle:7"`; [entityId] is the numeric part.
/// For principle nodes [status], [nodeType] and [courseId] are null.
@immutable
class GraphNode {
  const GraphNode({
    required this.id,
    required this.kind,
    required this.title,
    this.status,
    this.nodeType,
    this.courseId,
  });

  factory GraphNode.fromJson(Json json) => GraphNode(
    id: _str(json, 'id'),
    kind: GraphNodeKind.fromJson(json['kind']),
    title: _str(json, 'title'),
    status: json['status'] == null ? null : SkillStatus.fromJson(json['status']),
    nodeType: json['node_type'] == null ? null : NodeType.fromJson(json['node_type']),
    courseId: _intN(json, 'course_id'),
  );

  final String id;
  final GraphNodeKind kind;
  final String title;
  final SkillStatus? status;
  final NodeType? nodeType;
  final int? courseId;

  bool get isSkill => kind == GraphNodeKind.skill;
  bool get isPrincipleNode => kind == GraphNodeKind.principle;

  /// The numeric id after the `kind:` prefix.
  int get entityId => int.parse(id.substring(id.indexOf(':') + 1));
}

/// An edge of the knowledge graph. Contract: `Graph.edges[]`.
///
/// Directions: contains parent→child; requires first→after; origin
/// principle→skill it arose on; related principle→principle or skill;
/// contradicts principle→principle. [source]/[target] are graph node ids.
@immutable
class GraphEdge {
  const GraphEdge({required this.source, required this.target, required this.kind, this.reason});

  factory GraphEdge.fromJson(Json json) => GraphEdge(
    source: _str(json, 'source'),
    target: _str(json, 'target'),
    kind: GraphEdgeKind.fromJson(json['kind']),
    reason: _strN(json, 'reason'),
  );

  final String source;
  final String target;
  final GraphEdgeKind kind;
  final String? reason;
}

/// Body of `GET /graph`. Contract: `Graph`.
@immutable
class Graph {
  const Graph({required this.nodes, required this.edges});

  factory Graph.fromJson(Json json) => Graph(
    nodes: _list(json, 'nodes', GraphNode.fromJson),
    edges: _list(json, 'edges', GraphEdge.fromJson),
  );

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
}

// ---------------------------------------------------------------------------
// Condition check-in
// ---------------------------------------------------------------------------

/// One day's condition record. Contract: `DailyCheckIn`.
///
/// Ranges: [sleepHours] 0–14, [focus] 1–5, [stress] 1–5; each may be null.
@immutable
class DailyCheckIn {
  const DailyCheckIn({
    required this.date,
    this.sleepHours,
    this.exercised,
    this.dietNote,
    this.focus,
    this.stress,
    this.transcript,
    required this.source,
  });

  factory DailyCheckIn.fromJson(Json json) => DailyCheckIn(
    date: _str(json, 'date'),
    sleepHours: _doubleN(json, 'sleep_hours'),
    exercised: _boolN(json, 'exercised'),
    dietNote: _strN(json, 'diet_note'),
    focus: _intN(json, 'focus'),
    stress: _intN(json, 'stress'),
    transcript: _strN(json, 'transcript'),
    source: CheckInSource.fromJson(json['source']),
  );

  /// KST calendar date, `YYYY-MM-DD`.
  final String date;
  final double? sleepHours;
  final bool? exercised;
  final String? dietNote;
  final int? focus;
  final int? stress;
  final String? transcript;
  final CheckInSource source;
}

/// Body of `POST /checkins`. Contract endpoint 12.
@immutable
class CheckInResult {
  const CheckInResult({required this.checkin, required this.missingFields});

  factory CheckInResult.fromJson(Json json) => CheckInResult(
    checkin: DailyCheckIn.fromJson(_obj(json, 'checkin')),
    missingFields: List<CheckInField>.unmodifiable(
      (json['missing_fields'] as List? ?? const []).map(CheckInField.fromJson),
    ),
  );

  final DailyCheckIn checkin;

  /// The null fields, in the order sleep_hours, exercised, diet_note, focus,
  /// stress.
  final List<CheckInField> missingFields;
}

// ---------------------------------------------------------------------------
// Briefing, plan, search
// ---------------------------------------------------------------------------

/// `ProfileFacts.nodes`.
@immutable
class NodeCounts {
  const NodeCounts({
    required this.total,
    required this.mastered,
    required this.available,
    required this.locked,
  });

  factory NodeCounts.fromJson(Json json) => NodeCounts(
    total: _int(json, 'total'),
    mastered: _int(json, 'mastered'),
    available: _int(json, 'available'),
    locked: _int(json, 'locked'),
  );

  final int total;
  final int mastered;
  final int available;
  final int locked;
}

/// `ProfileFacts.audits`.
@immutable
class AuditCounts {
  const AuditCounts({required this.total, required this.passed, required this.failed});

  factory AuditCounts.fromJson(Json json) => AuditCounts(
    total: _int(json, 'total'),
    passed: _int(json, 'passed'),
    failed: _int(json, 'failed'),
  );

  final int total;
  final int passed;
  final int failed;
}

/// A recurring misconception. Contract: `ProfileFacts.misconception_clusters[]`.
@immutable
class MisconceptionCluster {
  const MisconceptionCluster({
    required this.label,
    required this.occurrences,
    required this.skills,
    required this.crossSkill,
    required this.principleIds,
  });

  factory MisconceptionCluster.fromJson(Json json) => MisconceptionCluster(
    label: _str(json, 'label'),
    occurrences: _int(json, 'occurrences'),
    skills: _strList(json, 'skills'),
    crossSkill: _bool(json, 'cross_skill'),
    principleIds: _intList(json, 'principle_ids'),
  );

  final String label;
  final int occurrences;

  /// Titles of the skills where it occurred.
  final List<String> skills;

  /// Occurred on two or more different skills (highlight it).
  final bool crossSkill;
  final List<int> principleIds;
}

/// `ProfileFacts.condition` — based on the last 3 check-ins.
@immutable
class ConditionFacts {
  const ConditionFacts({
    required this.days,
    this.avgSleepHours,
    this.avgStress,
    required this.flag,
  });

  factory ConditionFacts.fromJson(Json json) => ConditionFacts(
    days: _int(json, 'days'),
    avgSleepHours: _doubleN(json, 'avg_sleep_hours'),
    avgStress: _doubleN(json, 'avg_stress'),
    flag: ConditionFlag.fromJson(json['flag']),
  );

  /// Number of check-ins used (0–3).
  final int days;
  final double? avgSleepHours;
  final double? avgStress;
  final ConditionFlag flag;
}

/// Facts computed fresh by the server. Contract: `ProfileFacts`.
/// `ProfileFacts.xp` (contract Section 5): `{"total": 220, "level": 2,
/// "level_progress": 0.4}`.
@immutable
class XpFacts {
  const XpFacts({this.total = 0, this.level = 1, this.levelProgress = 0});

  factory XpFacts.fromJson(Json json) => XpFacts(
    total: _int(json, 'total'),
    level: _int(json, 'level'),
    levelProgress: _double(json, 'level_progress'),
  );

  /// The level rule of the server: level 1 plus one per 5 mastered nodes.
  /// [total] is unknown (0).
  factory XpFacts.fromMastered(int mastered) =>
      XpFacts(level: mastered ~/ 5 + 1, levelProgress: (mastered % 5) / 5);

  /// Sum of all rewards.
  final int total;

  /// Mastered nodes // 5 + 1 (starts at 1).
  final int level;

  /// 0–1: `(mastered % 5) / 5`.
  final double levelProgress;
}

@immutable
class ProfileFacts {
  const ProfileFacts({
    required this.nodes,
    required this.audits,
    required this.misconceptionClusters,
    required this.condition,
    this.xp = const XpFacts(),
  });

  factory ProfileFacts.fromJson(Json json) {
    final nodes = NodeCounts.fromJson(_obj(json, 'nodes'));
    return ProfileFacts(
      nodes: nodes,
      audits: AuditCounts.fromJson(_obj(json, 'audits')),
      misconceptionClusters: _list(json, 'misconception_clusters', MisconceptionCluster.fromJson),
      condition: ConditionFacts.fromJson(_obj(json, 'condition')),
      // Older servers send no `xp`: derive the level from the node counts.
      xp: json['xp'] == null
          ? XpFacts.fromMastered(nodes.mastered)
          : XpFacts.fromJson(_obj(json, 'xp')),
    );
  }

  final NodeCounts nodes;
  final AuditCounts audits;
  final List<MisconceptionCluster> misconceptionClusters;
  final ConditionFacts condition;

  /// XP total and level (contract Section 5).
  final XpFacts xp;
}

/// Status briefing. Contract: `Briefing`.
@immutable
class Briefing {
  const Briefing({required this.facts, this.narrative, this.narrativeGeneratedAt});

  factory Briefing.fromJson(Json json) => Briefing(
    facts: ProfileFacts.fromJson(_obj(json, 'facts')),
    narrative: _strN(json, 'narrative'),
    narrativeGeneratedAt: _timeN(json, 'narrative_generated_at'),
  );

  final ProfileFacts facts;

  /// Null until the first narration.
  final String? narrative;

  /// UTC; null until the first narration.
  final DateTime? narrativeGeneratedAt;

  bool get hasNarrative => narrative != null && narrative!.trim().isNotEmpty;
}

/// One step of a study plan (today's quests). Contract: `StudyPlan.steps[]`.
@immutable
class PlanStep {
  const PlanStep({
    required this.skillId,
    required this.courseId,
    required this.skillTitle,
    required this.nodeType,
    required this.rationale,
    required this.focusHint,
  });

  factory PlanStep.fromJson(Json json) => PlanStep(
    skillId: _int(json, 'skill_id'),
    courseId: _int(json, 'course_id'),
    skillTitle: _str(json, 'skill_title'),
    nodeType: NodeType.fromJson(json['node_type']),
    rationale: _str(json, 'rationale'),
    focusHint: _str(json, 'focus_hint'),
  );

  final int skillId;
  final int courseId;
  final String skillTitle;
  final NodeType nodeType;
  final String rationale;
  final String focusHint;
}

/// Contract: `StudyPlan`. Up to five steps, in study order.
@immutable
class StudyPlan {
  const StudyPlan({
    required this.id,
    required this.suggestedTier,
    required this.contextBucket,
    required this.createdAt,
    required this.steps,
  });

  factory StudyPlan.fromJson(Json json) => StudyPlan(
    id: _int(json, 'id'),
    suggestedTier: Tier.fromJson(json['suggested_tier']),
    contextBucket: ContextBucket.fromJson(json['context_bucket']),
    createdAt: _time(json, 'created_at'),
    steps: _list(json, 'steps', PlanStep.fromJson),
  );

  final int id;
  final Tier suggestedTier;
  final ContextBucket contextBucket;

  /// UTC.
  final DateTime createdAt;
  final List<PlanStep> steps;
}

/// One search result. The URL always comes from a search result, never from
/// the model. Contract: `SearchPlan.items[]`.
@immutable
class SearchItem {
  const SearchItem({
    required this.title,
    required this.url,
    required this.snippet,
    required this.reason,
  });

  factory SearchItem.fromJson(Json json) => SearchItem(
    title: _str(json, 'title'),
    url: _str(json, 'url'),
    snippet: _strN(json, 'snippet') ?? '',
    reason: _strN(json, 'reason') ?? '',
  );

  final String title;
  final String url;
  final String snippet;
  final String reason;
}

/// Contract: `SearchPlan`. At most three items.
@immutable
class SearchPlan {
  const SearchPlan({
    required this.id,
    required this.skillId,
    required this.gap,
    required this.queries,
    required this.items,
    required this.createdAt,
  });

  factory SearchPlan.fromJson(Json json) => SearchPlan(
    id: _int(json, 'id'),
    skillId: _int(json, 'skill_id'),
    gap: _str(json, 'gap'),
    queries: _strList(json, 'queries'),
    items: _list(json, 'items', SearchItem.fromJson),
    createdAt: _time(json, 'created_at'),
  );

  final int id;
  final int skillId;
  final String gap;
  final List<String> queries;
  final List<SearchItem> items;

  /// UTC.
  final DateTime createdAt;
}

// ---------------------------------------------------------------------------
// Stage UI additions (contract Section 5)
// ---------------------------------------------------------------------------

enum ChatRole {
  user('user'),
  assistant('assistant');

  const ChatRole(this.value);
  final String value;

  static ChatRole fromJson(Object? raw) => _enumFrom(values, (e) => e.value, raw, 'ChatRole');
}

/// Where a `navigate` chat action points.
enum NavScene {
  map('map'),
  skill('skill');

  const NavScene(this.value);
  final String value;

  static NavScene fromJson(Object? raw) => _enumFrom(values, (e) => e.value, raw, 'NavScene');
}

/// What the app should do after a chat message (`ChatMessage.action`).
sealed class ChatAction {
  const ChatAction();

  factory ChatAction.fromJson(Json json) {
    switch (json['type']) {
      case 'course':
        return CourseAction(
          course: Course.fromJson(_obj(json, 'course')),
          nodeCount: _int(json, 'node_count'),
        );
      case 'checkin':
        return CheckInAction(CheckInResult.fromJson(_obj(json, 'result')));
      case 'plan':
        return PlanAction(StudyPlan.fromJson(_obj(json, 'plan')));
      case 'briefing':
        return BriefingAction(Briefing.fromJson(_obj(json, 'briefing')));
      case 'navigate':
        return NavigateAction(
          scene: NavScene.fromJson(json['scene']),
          skillId: _intN(json, 'skill_id'),
        );
      default:
        throw _bad('type', json['type']);
    }
  }
}

/// A course was generated.
final class CourseAction extends ChatAction {
  const CourseAction({required this.course, required this.nodeCount});

  final Course course;
  final int nodeCount;
}

/// A check-in was recorded.
final class CheckInAction extends ChatAction {
  const CheckInAction(this.result);

  final CheckInResult result;
}

/// A study plan was generated.
final class PlanAction extends ChatAction {
  const PlanAction(this.plan);

  final StudyPlan plan;
}

/// A briefing was narrated.
final class BriefingAction extends ChatAction {
  const BriefingAction(this.briefing);

  final Briefing briefing;
}

/// Switch scene. [skillId] is set only for [NavScene.skill].
final class NavigateAction extends ChatAction {
  const NavigateAction({required this.scene, this.skillId});

  final NavScene scene;
  final int? skillId;
}

/// One message of the front-desk conversation (endpoints 18–19).
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.agent,
    this.action,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Json json) => ChatMessage(
    id: _int(json, 'id'),
    role: ChatRole.fromJson(json['role']),
    content: _str(json, 'content'),
    agent: _strN(json, 'agent'),
    action: json['action'] == null ? null : ChatAction.fromJson(_obj(json, 'action')),
    createdAt: _time(json, 'created_at'),
  );

  final int id;
  final ChatRole role;
  final String content;

  /// `front_desk` · `narrator` · `recommender` · `planner` · `checkin_converter`;
  /// null for user messages. The avatar is picked by this name.
  final String? agent;
  final ChatAction? action;
  final DateTime createdAt;

  bool get isUser => role == ChatRole.user;
}

/// One suggestion line of the home scene (endpoint 20). With [skillId] the
/// client opens that node instead of sending [message]. A [reflection] item
/// (contract Section 6) carries the reflection prompt of the current time
/// window in [label]; the Guide asks it and the next message answers it.
@immutable
class ChatSuggestion {
  const ChatSuggestion({
    required this.label,
    required this.message,
    this.skillId,
    this.reflection = false,
  });

  factory ChatSuggestion.fromJson(Json json) => ChatSuggestion(
    label: _str(json, 'label'),
    message: _str(json, 'message'),
    skillId: _intN(json, 'skill_id'),
    reflection: _boolN(json, 'reflection') ?? false,
  );

  final String label;
  final String message;
  final int? skillId;

  /// A reflection prompt (`"reflection": true`); false on older servers.
  final bool reflection;
}

/// One line of the audit history (endpoints 22 and 23).
@immutable
class AuditSummary {
  const AuditSummary({
    required this.id,
    required this.skillId,
    required this.skillTitle,
    required this.status,
    this.score,
    required this.createdAt,
  });

  factory AuditSummary.fromJson(Json json) => AuditSummary(
    id: _int(json, 'id'),
    skillId: _int(json, 'skill_id'),
    skillTitle: _str(json, 'skill_title'),
    status: AuditStatus.fromJson(json['status']),
    score: _intN(json, 'score'),
    createdAt: _time(json, 'created_at'),
  );

  final int id;
  final int skillId;
  final String skillTitle;
  final AuditStatus status;
  final int? score;
  final DateTime createdAt;
}

/// A prerequisite of a node with the reason (`SkillOverview.requires`).
@immutable
class RequiredSkill {
  const RequiredSkill({required this.skill, this.reason});

  factory RequiredSkill.fromJson(Json json) =>
      RequiredSkill(skill: SkillNode.fromJson(_obj(json, 'skill')), reason: _strN(json, 'reason'));

  final SkillNode skill;
  final String? reason;
}

/// Everything scene 4 shows about a node (endpoint 22).
@immutable
class SkillOverview {
  const SkillOverview({
    required this.skill,
    required this.course,
    this.containsParents = const [],
    this.requires = const [],
    this.audits = const [],
    this.materials = const [],
  });

  factory SkillOverview.fromJson(Json json) => SkillOverview(
    skill: SkillNode.fromJson(_obj(json, 'skill')),
    course: Course.fromJson(_obj(json, 'course')),
    containsParents: _list(json, 'contains_parents', SkillNode.fromJson),
    requires: _list(json, 'requires', RequiredSkill.fromJson),
    audits: _list(json, 'audits', AuditSummary.fromJson),
    materials: _list(json, 'materials', SearchPlan.fromJson),
  );

  final SkillNode skill;
  final Course course;

  /// The nodes that contain this one (the main parent first).
  final List<SkillNode> containsParents;

  /// The nodes this node requires.
  final List<RequiredSkill> requires;

  /// This node's audits, newest first.
  final List<AuditSummary> audits;

  /// Its search plans, newest first.
  final List<SearchPlan> materials;
}

/// A file stored by `POST /api/uploads` (endpoint 24); pass [id] in
/// `upload_ids` of the next chat message.
@immutable
class UploadedFile {
  const UploadedFile({
    required this.id,
    required this.filename,
    required this.chars,
    required this.createdAt,
  });

  factory UploadedFile.fromJson(Json json) => UploadedFile(
    id: _int(json, 'id'),
    filename: _str(json, 'filename'),
    chars: _int(json, 'chars'),
    createdAt: _time(json, 'created_at'),
  );

  final int id;
  final String filename;

  /// Characters of text that were extracted (at most 100 000).
  final int chars;
  final DateTime createdAt;
}

// ---------------------------------------------------------------------------
// Life-as-a-game layer (contract Section 6)
// ---------------------------------------------------------------------------

/// The character sheet (endpoints 25 and 26): who the user is becoming
/// ([identity]), the [vision] (win condition), the [antiVision] (stakes) and up
/// to five [rules]. Every text may be empty.
@immutable
class Profile {
  const Profile({
    this.identity = '',
    this.vision = '',
    this.antiVision = '',
    this.rules = const [],
    this.updatedAt,
    this.onboarded = true,
  });

  factory Profile.fromJson(Json json) => Profile(
    identity: _strN(json, 'identity') ?? '',
    vision: _strN(json, 'vision') ?? '',
    antiVision: _strN(json, 'anti_vision') ?? '',
    rules: _strList(json, 'rules'),
    updatedAt: _timeN(json, 'updated_at'),
    // A server from before accounts sends no flag: never force the tutorial then.
    onboarded: json['onboarded'] is bool ? json['onboarded'] as bool : true,
  );

  /// `identity`, `vision`, `anti_vision` are at most this long.
  static const int maxTextLength = 280;

  /// At most this many rules, each at most [maxRuleLength] characters.
  static const int maxRules = 5;
  static const int maxRuleLength = 120;

  final String identity;
  final String vision;
  final String antiVision;
  final List<String> rules;

  /// UTC; null until the first save.
  final DateTime? updatedAt;

  /// The first-run tutorial was finished or skipped (contract section 7).
  final bool onboarded;

  bool get isEmpty => identity.isEmpty && vision.isEmpty && antiVision.isEmpty && rules.isEmpty;
}

/// One answered reflection prompt (endpoint 27).
@immutable
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.prompt,
    required this.answer,
    required this.createdAt,
  });

  factory JournalEntry.fromJson(Json json) => JournalEntry(
    id: _int(json, 'id'),
    prompt: _str(json, 'prompt'),
    answer: _str(json, 'answer'),
    createdAt: _time(json, 'created_at'),
  );

  final int id;
  final String prompt;
  final String answer;

  /// UTC.
  final DateTime createdAt;
}

/// A main quest: a one-year goal with the courses that serve it (endpoints
/// 28–31). A course under no goal is a side quest.
@immutable
class Goal {
  const Goal({
    required this.id,
    required this.title,
    this.courseIds = const [],
    required this.createdAt,
  });

  factory Goal.fromJson(Json json) => Goal(
    id: _int(json, 'id'),
    title: _str(json, 'title'),
    courseIds: _intList(json, 'course_ids'),
    createdAt: _time(json, 'created_at'),
  );

  /// At most this many goals; a title is at most [maxTitleLength] characters.
  static const int maxGoals = 3;
  static const int maxTitleLength = 80;

  final int id;
  final String title;

  /// In the order they were attached. A course is under one goal at most.
  final List<int> courseIds;

  /// UTC.
  final DateTime createdAt;
}
