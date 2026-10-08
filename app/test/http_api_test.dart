// HttpApi against a MockClient: method, path, query, body of every endpoint,
// response parsing, and the mapping of failures to ApiException.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:self_infinity/api/api_exception.dart';
import 'package:self_infinity/api/http_api.dart';
import 'package:self_infinity/api/models.dart';

// -- fixtures ---------------------------------------------------------------

const Map<String, dynamic> courseJson = {
  'id': 1,
  'topic': 'math',
  'source_course': null,
  'source_url': null,
  'created_at': '2026-10-05T03:00:00Z',
};

const Map<String, dynamic> nodeJson = {
  'id': 5,
  'course_id': 1,
  'slug': 'quadratic-equation',
  'title': 'Quadratic Equations',
  'description': '...',
  'status': 'available',
  'node_type': 'concept',
  'mastery_score': null,
};

const Map<String, dynamic> edgeJson = {
  'from_id': 2,
  'to_id': 5,
  'kind': 'contains',
  'is_primary': true,
  'reason': null,
};

const Map<String, dynamic> principleJson = {
  'id': 7,
  'title': 'State the range of the solution first',
  'body':
      'When I talk about the solution of an equation, I first say which number range it lives in.',
  'misconception': 'Thought no real roots means no solution at all',
  'source_session_id': 31,
  'skill_id': 5,
  'skill_title': 'Quadratic Equations',
  'created_at': '2026-10-05T03:20:00Z',
};

const Map<String, dynamic> factsJson = {
  'nodes': {'total': 12, 'mastered': 4, 'available': 3, 'locked': 5},
  'audits': {'total': 6, 'passed': 4, 'failed': 2},
  'misconception_clusters': [],
  'condition': {'days': 0, 'avg_sleep_hours': null, 'avg_stress': null, 'flag': 'unknown'},
};

const Map<String, dynamic> briefingJson = {
  'facts': factsJson,
  'narrative': "You've cleared 4 of 12 nodes.",
  'narrative_generated_at': '2026-10-05T03:30:00Z',
};

const Map<String, dynamic> planJson = {
  'id': 3,
  'suggested_tier': 'medium',
  'context_bucket': 'mid',
  'created_at': '2026-10-05T03:31:00Z',
  'steps': [
    {
      'skill_id': 9,
      'course_id': 1,
      'skill_title': 'Quadratic Functions',
      'node_type': 'concept',
      'rationale': '...',
      'focus_hint': '...',
    },
  ],
};

const Map<String, dynamic> checkinResultJson = {
  'checkin': {
    'date': '2026-10-05',
    'sleep_hours': 6,
    'exercised': false,
    'diet_note': 'lunch: ramen',
    'focus': null,
    'stress': null,
    'transcript': 'Last night I slept six hours ...',
    'source': 'voice',
  },
  'missing_fields': ['focus', 'stress'],
};

// -- harness ------------------------------------------------------------------

http.Response jsonResponse(Object? body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

class Harness {
  Harness(this._respond, {String baseUrl = 'http://127.0.0.1:8000/api'}) {
    api = HttpApi(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        requests.add(request);
        return _respond(request);
      }),
    );
  }

  final http.Response Function(http.Request request) _respond;
  final List<http.Request> requests = [];
  late final HttpApi api;

  http.Request get last => requests.last;
  Object? get lastBody => jsonDecode(last.body);
}

Harness ok(Object? body) => Harness((_) => jsonResponse(body));

Future<ApiException> failure(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('expected an ApiException');
}

void main() {
  group('requests', () {
    test('2 generateCourse: POST /skills/generate with the five settings', () async {
      final h = ok({
        'course': courseJson,
        'nodes': [nodeJson],
        'edges': [edgeJson],
      });
      final r = await h.api.generateCourse(
        const GenerateRequest(
          topic: 'math',
          nodeCount: 20,
          maxDepth: 5,
          difficulty: Difficulty.deep,
          searchSyllabus: false,
        ),
      );
      expect(h.last.method, 'POST');
      expect(h.last.url.path, '/api/skills/generate');
      expect(h.lastBody, {
        'topic': 'math',
        'node_count': 20,
        'max_depth': 5,
        'difficulty': 'deep',
        'search_syllabus': false,
      });
      expect(r.course.id, 1);
      expect(r.nodes.single.title, 'Quadratic Equations');
      expect(r.edges.single.isPrimary, isTrue);
    });

    test('3 listCourses: GET /courses', () async {
      final h = ok([courseJson]);
      final r = await h.api.listCourses();
      expect(h.last.method, 'GET');
      expect(h.last.url.path, '/api/courses');
      expect(h.last.url.hasQuery, isFalse);
      expect(h.last.body, isEmpty);
      expect(r.single.topic, 'math');
    });

    test('4 getCourseMap: GET /courses/{id}/map', () async {
      final h = ok({
        'course': courseJson,
        'nodes': [nodeJson],
        'edges': [edgeJson],
      });
      final r = await h.api.getCourseMap(3);
      expect(h.last.method, 'GET');
      expect(h.last.url.path, '/api/courses/3/map');
      expect(r.nodes, hasLength(1));
    });

    test('5 listSkills: GET /skills with and without course_id', () async {
      final h = ok([nodeJson]);
      await h.api.listSkills(courseId: 3);
      expect(h.last.method, 'GET');
      expect(h.last.url.path, '/api/skills');
      expect(h.last.url.queryParameters, {'course_id': '3'});
      final r = await h.api.listSkills();
      expect(h.last.url.path, '/api/skills');
      expect(h.last.url.hasQuery, isFalse);
      expect(r.single.id, 5);
    });

    test('7 startAudit: POST /skills/{id}/audits {mode}', () async {
      final h = ok({
        'session': {
          'id': 31,
          'skill_id': 5,
          'node_position': 'leaf',
          'status': 'active',
          'score': null,
          'gaps': [],
          'comment': null,
          'turns': [
            {'role': 'auditor', 'content': 'q'},
          ],
        },
        'opening_question': 'q',
      });
      await h.api.startAudit(5);
      expect(h.last.method, 'POST');
      expect(h.last.url.path, '/api/skills/5/audits');
      expect(h.lastBody, {'mode': 'day'});
      final r = await h.api.startAudit(5, mode: 'night');
      expect(h.lastBody, {'mode': 'night'});
      expect(r.session.id, 31);
      expect(r.openingQuestion, 'q');
    });

    test('8 submitTurn: POST /audits/{id}/turns {content} → probe or verdict', () async {
      final probe = ok({'type': 'probe', 'question': 'Why is that?'});
      final r1 = await probe.api.submitTurn(31, 'Here is my explanation');
      expect(probe.last.method, 'POST');
      expect(probe.last.url.path, '/api/audits/31/turns');
      expect(probe.lastBody, {'content': 'Here is my explanation'});
      expect(r1, isA<ProbeResult>());
      expect((r1 as ProbeResult).question, 'Why is that?');

      final verdict = ok({
        'type': 'verdict',
        'passed': true,
        'score': 82,
        'gaps': [],
        'comment': 'ok',
        'unlocked_skill_ids': [6, 7],
        'reward_amount': 22,
        'reward_multiplier': 1.1,
      });
      final r2 = await verdict.api.submitTurn(31, 'x') as VerdictResult;
      expect(r2.passed, isTrue);
      expect(r2.unlockedSkillIds, [6, 7]);
      expect(r2.rewardAmount, 22);
    });

    test('9 submitReflection: POST /audits/{id}/reflection {reflection}', () async {
      final h = ok(principleJson);
      final r = await h.api.submitReflection(31, "I didn't think about the range");
      expect(h.last.method, 'POST');
      expect(h.last.url.path, '/api/audits/31/reflection');
      expect(h.lastBody, {'reflection': "I didn't think about the range"});
      expect(r.title, 'State the range of the solution first');
    });

    test('13 getBriefing: GET /narrator/briefing', () async {
      final h = ok(briefingJson);
      final r = await h.api.getBriefing();
      expect(h.last.method, 'GET');
      expect(h.last.url.path, '/api/narrator/briefing');
      expect(r.narrative, "You've cleared 4 of 12 nodes.");
    });

    test(
      '17 createSearchPlan: POST /skills/{id}/search-plan with gap or misconception_id',
      () async {
        final h = ok({
          'id': 2,
          'skill_id': 5,
          'gap': 'g',
          'queries': ['a', 'b'],
          'items': [
            {'title': 't', 'url': 'https://example.org/1', 'snippet': 's', 'reason': 'r'},
          ],
          'created_at': '2026-10-05T03:40:00Z',
        });
        final r = await h.api.createSearchPlan(5, gap: 'when the discriminant is negative');
        expect(h.last.method, 'POST');
        expect(h.last.url.path, '/api/skills/5/search-plan');
        expect(h.lastBody, {'gap': 'when the discriminant is negative'});
        expect(r.items.single.url, 'https://example.org/1');

        await h.api.createSearchPlan(5, misconceptionId: 7);
        expect(h.lastBody, {'misconception_id': 7});
      },
    );

    test('a trailing slash in the base URL is harmless', () async {
      final h = Harness((_) => jsonResponse([courseJson]), baseUrl: 'http://example.test/api/');
      await h.api.listCourses();
      expect(h.last.url.toString(), 'http://example.test/api/courses');
    });
  });

  group('responses', () {
    test(
      'non-ASCII text (“curly quotes”, 한글) is decoded as UTF-8 even without a charset',
      () async {
        final h = Harness(
          (_) => http.Response.bytes(
            utf8.encode(jsonEncode({...principleJson, 'title': '“Quoted” title — 한글'})),
            200,
            headers: {'content-type': 'text/plain'},
          ),
        );
        final p = await h.api.submitReflection(1, 'x');
        expect(p.title, '“Quoted” title — 한글');
      },
    );

    test('a 2xx body that does not match the contract becomes an ApiException', () async {
      final h = ok({'unexpected': true});
      final e = await failure(() => h.api.listCourses());
      expect(e.statusCode, 200);
      expect(e.userMessage, ApiException.unknownText);

      final h2 = ok({'course': courseJson}); // nodes/edges missing is tolerated...
      final map = await h2.api.getCourseMap(1);
      expect(map.nodes, isEmpty);

      final h3 = ok({'id': 'not-a-number'});
      final e3 = await failure(() => h3.api.getCourseMap(1));
      expect(e3.statusCode, 200);
    });
  });

  group('errors', () {
    Harness failing(int status, Object? body) => Harness((_) => jsonResponse(body, status));

    test('invalid JSON in a 2xx body becomes an ApiException', () async {
      final h = Harness((_) => http.Response('<html>nope</html>', 200));
      final e = await failure(() => h.api.getBriefing());
      expect(e.statusCode, 200);
    });

    test('422 with the FastAPI list body', () async {
      final h = failing(422, {
        'detail': [
          {
            'loc': ['body', 'message'],
            'msg': 'String should have at least 1 character',
            'type': 'string_too_short',
          },
        ],
      });
      final e = await failure(() => h.api.sendChat(''));
      expect(e.statusCode, 422);
      expect(e.serverMessage, contains('at least 1 character'));
      expect(e.userMessage, 'Please check what you entered.');
    });

    test('other statuses and non-JSON error bodies', () async {
      final h500 = failing(500, {'detail': 'boom'});
      final e500 = await failure(() => h500.api.getBriefing());
      expect(e500.statusCode, 500);
      expect(e500.userMessage, 'Something went wrong.');

      final html = Harness((_) => http.Response('<html>Bad Gateway</html>', 502));
      final eHtml = await failure(() => html.api.getBriefing());
      expect(eHtml.statusCode, 502);
      expect(eHtml.userMessage, ApiException.aiFailureText);

      final empty = Harness((_) => http.Response('', 503));
      final eEmpty = await failure(() => empty.api.getBriefing());
      expect(eEmpty.statusCode, 503);
      expect(eEmpty.serverMessage, isNull);
    });

    test('400 with a known message is translated to English', () async {
      const known = {
        'skill is locked': 'This node is locked. Clear the nodes before it first.',
        'audit session is already closed': 'This audit has already ended.',
        'reflection is only accepted for a failed audit':
            'Lesson cards can only be made after a failed audit.',
        'reflection already submitted for this audit': 'The lesson card is already made.',
        'No node is available yet. Generate a course or pass an existing node first.':
            'No node is ready yet. Make a world first.',
        'A gap or misconception id is required. Search targets a specific gap only.':
            'Pick a gap or misconception to search for.',
      };
      for (final entry in known.entries) {
        final h = failing(400, {'detail': entry.key});
        final e = await failure(() => h.api.startAudit(1));
        expect(e.statusCode, 400);
        expect(e.serverMessage, entry.key);
        expect(e.userMessage, entry.value, reason: entry.key);
      }
    });

    test('400 with an unknown message gets the generic English text', () async {
      final h = failing(400, {'detail': 'something else'});
      final e = await failure(() => h.api.startAudit(1));
      expect(e.userMessage, "You can't do that right now.");
    });

    test('404', () async {
      final h = failing(404, {'detail': 'course not found'});
      final e = await failure(() => h.api.getCourseMap(99));
      expect(e.statusCode, 404);
      expect(e.serverMessage, 'course not found');
      expect(e.userMessage, "We couldn't find that.");
    });

    test('502', () async {
      final h = failing(502, {
        'detail': 'The auditor is temporarily unavailable. Please try again.',
      });
      final e = await failure(() => h.api.submitTurn(1, 'x'));
      expect(e.statusCode, 502);
      expect(e.userMessage, 'Something went wrong on our side. Please try again.');
    });

    test('a network failure has no status code', () async {
      final api = HttpApi(
        client: MockClient((_) async => throw http.ClientException('Connection refused')),
      );
      final e = await failure(() => api.listCourses());
      expect(e.statusCode, isNull);
      expect(e.isNetworkError, isTrue);
      expect(e.userMessage, "Can't reach the server. Check your connection.");
    });

    test('any other exception from the transport is a network failure', () async {
      final api = HttpApi(client: MockClient((_) async => throw const FormatException('bad')));
      final e = await failure(() => api.getBriefing());
      expect(e.statusCode, isNull);
    });

    test('a timeout is a network failure', () async {
      final api = HttpApi(
        timeout: const Duration(milliseconds: 20),
        client: MockClient((_) => Completer<http.Response>().future),
      );
      final e = await failure(() => api.getBriefing());
      expect(e.statusCode, isNull);
      expect(e.serverMessage, contains('timed out'));
    });
  });

  group('ApiException', () {
    test('userMessage never leaks the server message', () {
      const e = ApiException(502, 'secret internal detail');
      expect(e.userMessage, isNot(contains('secret')));
      expect(const ApiException(500, 'x').userMessage, ApiException.unknownText);
      expect(const ApiException(401).userMessage, ApiException.signedOutText);
      expect(const ApiException(403).userMessage, ApiException.unknownText);
      expect(const ApiException.network().userMessage, ApiException.networkText);
    });

    test('known 400 messages are matched ignoring case and surrounding spaces', () {
      expect(
        const ApiException(400, '  Skill is locked ').userMessage,
        'This node is locked. Clear the nodes before it first.',
      );
    });

    test('toString is informative', () {
      expect(const ApiException(404, 'skill not found').toString(), contains('404'));
      expect(const ApiException.network('down').toString(), contains('no response'));
    });
  });
}
