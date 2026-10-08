/// [SelfInfinityApi] over `package:http`, talking to the FastAPI backend.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'api_exception.dart';
import 'models.dart';

/// The real backend client.
///
/// ```dart
/// final api = HttpApi(baseUrl: 'http://127.0.0.1:8000/api');
/// ```
///
/// * Inject [client] (e.g. `MockClient` from `package:http/testing.dart`) in
///   tests. A client you pass in is **not** closed by [close].
/// * Any non-2xx response throws [ApiException] with the status code and the
///   server's `detail` message. A network failure or timeout throws an
///   [ApiException] with `statusCode == null`.
/// * A 2xx response that does not match the contract throws an
///   [ApiException] carrying that status code.
class HttpApi implements SelfInfinityApi {
  HttpApi({
    this.baseUrl = defaultBaseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 240),
    this.token,
    this.onUnauthorized,
    this.language,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  /// The signed-in account's access token (sent as `Authorization: Bearer`),
  /// read before every request; null or no function = no header (local mode).
  final String? Function()? token;

  /// Called when the server answers 401 (the session expired or was revoked).
  final void Function()? onUnauthorized;

  /// The app's language (`en`, `zh`, `ko`), read before every request and sent
  /// as `Accept-Language`: the backend writes its replies in it. No function =
  /// no header (English).
  final String Function()? language;

  /// Local backend (`--dart-define=API_BASE_URL=...` overrides it in `main`).
  static const String defaultBaseUrl = 'http://127.0.0.1:8000/api';

  /// Base URL including `/api`, e.g. `http://127.0.0.1:8000/api`.
  final String baseUrl;

  /// Per-request timeout. It must outlast the server's slowest request, or the
  /// client gives up on a request the server then completes (and a resend
  /// lands on a state the user never saw). Worst cases: an audit turn is the
  /// Auditor plus the Challenger, each up to 2 × 30 s with the JSON retry; a
  /// course is the Syllabus Finder plus up to two Planner attempts, about
  /// 200 s. It stays under Vercel's 300 s function limit.
  final Duration timeout;

  final http.Client _client;
  final bool _ownsClient;

  /// Closes the underlying client if this object created it.
  void close() {
    if (_ownsClient) _client.close();
  }

  @override
  Future<CourseMap> generateCourse(GenerateRequest request) => _post(
    '/skills/generate',
    body: request.toJson(),
    parse: (j) => CourseMap.fromJson(_object(j)),
  );

  // -- 2–5: courses and skills ------------------------------------------------

  @override
  Future<List<Course>> listCourses() => _get(
    '/courses',
    parse: (j) => _array(j).map((e) => Course.fromJson(_object(e))).toList(),
  );

  @override
  Future<CourseMap> getCourseMap(int courseId) => _get(
    '/courses/$courseId/map',
    parse: (j) => CourseMap.fromJson(_object(j)),
  );

  @override
  Future<List<SkillNode>> listSkills({int? courseId}) => _get(
    '/skills',
    query: courseId == null ? null : {'course_id': '$courseId'},
    parse: (j) => _array(j).map((e) => SkillNode.fromJson(_object(e))).toList(),
  );

  // -- 7–9: audits ------------------------------------------------------------

  @override
  Future<AuditStart> startAudit(int skillId, {String mode = 'day'}) => _post(
    '/skills/$skillId/audits',
    body: {'mode': mode},
    parse: (j) => AuditStart.fromJson(_object(j)),
  );

  @override
  Future<TurnResult> submitTurn(int sessionId, String content) => _post(
    '/audits/$sessionId/turns',
    body: {'content': content},
    parse: (j) => TurnResult.fromJson(_object(j)),
  );

  @override
  Future<Principle> submitReflection(int sessionId, String reflection) => _post(
    '/audits/$sessionId/reflection',
    body: {'reflection': reflection},
    parse: (j) => Principle.fromJson(_object(j)),
  );

  // -- 13: briefing ----------------------------------------------

  @override
  Future<Briefing> getBriefing() =>
      _get('/narrator/briefing', parse: (j) => Briefing.fromJson(_object(j)));

  // -- 17: material search ----------------------------------------------------

  @override
  Future<SearchPlan> createSearchPlan(int skillId, {String? gap, int? misconceptionId}) => _post(
    '/skills/$skillId/search-plan',
    body: {
      'gap': ?gap,
      'misconception_id': ?misconceptionId,
    },
    parse: (j) => SearchPlan.fromJson(_object(j)),
  );

  @override
  Future<CourseScout> scoutCourse(String answer) => _post(
    '/skills/scout',
    body: {'answer': answer},
    parse: (j) => CourseScout.fromJson(_object(j)),
  );

  // -- 18–23: stage UI -----------------------------------------------------------

  @override
  Future<List<ChatMessage>> sendChat(
    String message, {
    List<int> uploadIds = const [],
    String? reflectionPrompt,
    String? courseTopic,
  }) => _post(
    '/chat',
    body: {
      'message': message,
      if (uploadIds.isNotEmpty) 'upload_ids': uploadIds,
      'reflection_prompt': ?reflectionPrompt,
      'course_topic': ?courseTopic,
    },
    parse: (j) {
      final messages = _object(j)['messages'];
      return _array(messages).map((e) => ChatMessage.fromJson(_object(e))).toList();
    },
  );

  @override
  Future<List<ChatMessage>> getChatHistory({int limit = 50}) => _get(
    '/chat/history',
    query: {'limit': '$limit'},
    parse: (j) => _array(j).map((e) => ChatMessage.fromJson(_object(e))).toList(),
  );

  @override
  Future<List<ChatSuggestion>> getChatSuggestions() => _get(
    '/chat/suggestions',
    parse: (j) =>
        _array(_object(j)['suggestions']).map((e) => ChatSuggestion.fromJson(_object(e))).toList(),
  );

  @override
  Future<DailyCheckIn?> getTodayCheckIn() => _get(
    '/checkins/today',
    parse: (j) => j == null ? null : DailyCheckIn.fromJson(_object(j)),
  );

  @override
  Future<SkillOverview> getSkillOverview(int skillId) => _get(
    '/skills/$skillId/overview',
    parse: (j) => SkillOverview.fromJson(_object(j)),
  );

  @override
  Future<List<AuditSummary>> listAudits({int limit = 20}) => _get(
    '/audits',
    query: {'limit': '$limit'},
    parse: (j) => _array(j).map((e) => AuditSummary.fromJson(_object(e))).toList(),
  );

  @override
  Future<UploadedFile> uploadFile({required String filename, required List<int> bytes}) => _send(
    'POST',
    '/uploads',
    file: http.MultipartFile.fromBytes('file', bytes, filename: filename),
    parse: (j) => UploadedFile.fromJson(_object(j)),
  );

  // -- 16, 25–27: life as a game ------------------------------------------------

  @override
  Future<StudyPlan?> getCurrentPlan() => _get(
    '/plan/current',
    parse: (j) => j == null ? null : StudyPlan.fromJson(_object(j)),
  );

  @override
  Future<Profile> getProfile() => _get('/profile', parse: (j) => Profile.fromJson(_object(j)));

  @override
  Future<Profile> updateProfile({
    String? identity,
    String? vision,
    String? antiVision,
    List<String>? rules,
    bool? onboarded,
  }) => _send(
    'PUT',
    '/profile',
    body: {
      'identity': ?identity,
      'vision': ?vision,
      'anti_vision': ?antiVision,
      'rules': ?rules,
      'onboarded': ?onboarded,
    },
    parse: (j) => Profile.fromJson(_object(j)),
  );

  @override
  Future<List<JournalEntry>> listJournal({int limit = 20}) => _get(
    '/journal',
    query: {'limit': '$limit'},
    parse: (j) => _array(j).map((e) => JournalEntry.fromJson(_object(e))).toList(),
  );

  @override
  Future<List<Principle>> listPrinciples() => _get(
    '/principles',
    parse: (j) => _array(j).map((e) => Principle.fromJson(_object(e))).toList(),
  );

  // -- 28–31: main quests --------------------------------------------------------

  @override
  Future<List<Goal>> listGoals() =>
      _get('/goals', parse: (j) => _array(j).map((e) => Goal.fromJson(_object(e))).toList());

  @override
  Future<Goal> createGoal(String title) =>
      _post('/goals', body: {'title': title}, parse: (j) => Goal.fromJson(_object(j)));

  @override
  Future<Goal> updateGoal(int goalId, {String? title, List<int>? courseIds}) => _send(
    'PUT',
    '/goals/$goalId',
    body: {'title': ?title, 'course_ids': ?courseIds},
    parse: (j) => Goal.fromJson(_object(j)),
  );

  @override
  Future<void> deleteGoal(int goalId) => _send('DELETE', '/goals/$goalId', parse: (_) {});

  @override
  Future<void> deleteCourse(int courseId, {bool deleteNodes = false}) => _send(
    'DELETE',
    '/courses/$courseId',
    query: {'delete_nodes': '$deleteNodes'},
    parse: (_) {},
  );

  @override
  Future<Me> getMe() => _get('/me', parse: (j) => Me.fromJson(_object(j)));

  @override
  Future<DevAudits> getDevAudits({int limit = 50}) => _get(
    '/dev/audits',
    query: {'limit': '$limit'},
    parse: (j) => DevAudits.fromJson(_object(j)),
  );

  @override
  Future<DevAudit> reviewAudit(int auditId, AuditReview? review, {bool leaked = false}) => _send(
    'PUT',
    '/dev/audits/$auditId/review',
    body: {'review': review?.json, 'leaked': leaked},
    parse: (j) => DevAudit.fromJson(_object(j)),
  );

  // -- 35: voice ---------------------------------------------------------------

  @override
  Future<bool> voiceAvailable() =>
      _get('/voice', parse: (j) => _object(j)['available'] == true);

  @override
  Future<String> transcribe(Uint8List audio, {required String filename}) => _send(
    'POST',
    '/voice/transcribe',
    file: http.MultipartFile.fromBytes('file', audio, filename: filename),
    parse: (j) => '${_object(j)['text'] ?? ''}',
  );

  @override
  Future<Uint8List> speech(String text) => _send(
    'POST',
    '/voice/speech',
    body: {'text': text},
    bytes: true,
    parse: (b) => b! as Uint8List,
  );

  // -- transport --------------------------------------------------------------

  Future<T> _get<T>(
    String path, {
    Map<String, String>? query,
    required T Function(Object?) parse,
  }) => _send('GET', path, query: query, parse: parse);

  Future<T> _post<T>(String path, {Object? body, required T Function(Object?) parse}) =>
      _send('POST', path, body: body, parse: parse);

  Future<T> _send<T>(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    http.MultipartFile? file,
    bool bytes = false,
    required T Function(Object?) parse,
  }) async {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    var uri = Uri.parse('$base$path');
    if (query != null && query.isNotEmpty) uri = uri.replace(queryParameters: query);

    final bearer = token?.call();
    final lang = language?.call();
    final headers = <String, String>{
      'Accept': bytes ? '*/*' : 'application/json',
      if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      if (bearer != null) 'Authorization': 'Bearer $bearer',
      'Accept-Language': ?lang,
    };

    final http.Response response;
    try {
      final Future<http.Response> future;
      if (file != null) {
        final request = http.MultipartRequest(method, uri)
          ..headers['Accept'] = 'application/json'
          ..files.add(file);
        if (bearer != null) request.headers['Authorization'] = 'Bearer $bearer';
        if (lang != null) request.headers['Accept-Language'] = lang;
        future = _client.send(request).then(http.Response.fromStream);
      } else if (method == 'GET') {
        future = _client.get(uri, headers: headers);
      } else if (method == 'DELETE') {
        future = _client.delete(uri, headers: headers);
      } else if (method == 'PUT') {
        future = _client.put(
          uri,
          headers: headers,
          body: body == null ? null : utf8.encode(jsonEncode(body)),
        );
      } else {
        future = _client.post(
          uri,
          headers: headers,
          body: body == null ? null : utf8.encode(jsonEncode(body)),
        );
      }
      response = await future.timeout(timeout);
    } on TimeoutException {
      throw const ApiException.network('request timed out');
    } on http.ClientException catch (e) {
      throw ApiException.network(e.message);
    } on Exception catch (e) {
      // SocketException, HandshakeException, ... (kept out of this file's
      // imports so the package also compiles for the web).
      throw ApiException.network('$e');
    }

    // Always decode as UTF-8, whatever the Content-Type charset says.
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    final status = response.statusCode;
    if (status == 401) onUnauthorized?.call();
    if (status < 200 || status >= 300) throw _errorFor(status, text);
    if (bytes) return parse(response.bodyBytes);

    try {
      final decoded = text.trim().isEmpty ? null : jsonDecode(text);
      return parse(decoded);
    } on Object catch (e) {
      throw ApiException(status, 'Unexpected response: $e');
    }
  }

  /// Builds the exception for a non-2xx response. FastAPI sends
  /// `{"detail": "<message>"}`; a 422 has a list in `detail`.
  static ApiException _errorFor(int status, String text) {
    String? message;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['detail'] != null) {
        final detail = decoded['detail'];
        if (detail is String) {
          message = detail;
        } else if (detail is List) {
          message = detail.map((e) => e is Map ? '${e['msg'] ?? e}' : '$e').join('; ');
        } else {
          message = '$detail';
        }
      }
    } on FormatException {
      // Not JSON (e.g. an HTML error page from a proxy).
    }
    message ??= text.trim().isEmpty ? null : text.trim();
    if (message != null && message.length > 300) message = message.substring(0, 300);
    return ApiException(status, message);
  }

  static Json _object(Object? json) {
    if (json is Map) return Map<String, dynamic>.from(json);
    throw FormatException('Expected a JSON object but got ${json.runtimeType}');
  }

  static List<Object?> _array(Object? json) {
    if (json is List) return json;
    throw FormatException('Expected a JSON array but got ${json.runtimeType}');
  }
}
