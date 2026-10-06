// HttpApi, endpoints 18-24 (stage UI): method, path, query, body, parsing.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:self_infinity/api/api_exception.dart';
import 'package:self_infinity/api/http_api.dart';
import 'package:self_infinity/api/models.dart';

const Map<String, dynamic> userMessage = {
  'id': 11,
  'role': 'user',
  'content': 'I want to learn math',
  'agent': null,
  'action': null,
  'created_at': '2026-10-05T03:00:00Z',
};

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

http.Response jsonResponse(Object? body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

class Harness {
  Harness(Object? body, [int status = 200]) {
    api = HttpApi(
      client: MockClient((request) async {
        requests.add(request);
        return jsonResponse(body, status);
      }),
    );
  }

  final List<http.Request> requests = [];
  late final HttpApi api;

  http.Request get last => requests.last;
}

void main() {
  test('18 sendChat: POST /chat {message} → the saved messages', () async {
    final h = Harness({
      'messages': [
        userMessage,
        {
          'id': 12,
          'role': 'assistant',
          'content': "I'll build a world for “math”.",
          'agent': 'front_desk',
          'action': null,
          'created_at': '2026-10-05T03:00:01Z',
        },
        {
          'id': 13,
          'role': 'assistant',
          'content': 'Your world “High School Math” is ready — 12 nodes.',
          'agent': 'planner',
          'action': {'type': 'course', 'course': courseJson, 'node_count': 12},
          'created_at': '2026-10-05T03:00:02Z',
        },
      ],
    });
    final r = await h.api.sendChat('I want to learn math');
    expect(h.last.method, 'POST');
    expect(h.last.url.toString(), 'http://127.0.0.1:8000/api/chat');
    expect(jsonDecode(h.last.body), {'message': 'I want to learn math'});
    expect(r, hasLength(3));
    expect(r.first.isUser, isTrue);
    expect(r.last.agent, 'planner');
    expect((r.last.action! as CourseAction).nodeCount, 12);
  });

  test('18 sendChat: upload_ids are sent only when there are some', () async {
    final h = Harness({
      'messages': [userMessage],
    });
    await h.api.sendChat('I want to learn this', uploadIds: [3, 4]);
    expect(jsonDecode(h.last.body), {
      'message': 'I want to learn this',
      'upload_ids': [3, 4],
    });
    await h.api.sendChat('Hi');
    expect(jsonDecode(h.last.body), {'message': 'Hi'});
  });

  test('18 sendChat: an unknown upload id is a 404', () async {
    final h = Harness({'detail': 'upload not found'}, 404);
    try {
      await h.api.sendChat('x', uploadIds: [99]);
      fail('expected an ApiException');
    } on ApiException catch (e) {
      expect(e.statusCode, 404);
    }
  });

  test('24 uploadFile: POST /uploads, multipart with one `file` field', () async {
    final h = Harness({
      'id': 3,
      'filename': 'Calculus syllabus.md',
      'chars': 18234,
      'created_at': '2026-10-05T03:00:00Z',
    });
    final r = await h.api.uploadFile(
      filename: 'Calculus syllabus.md',
      bytes: utf8.encode('# Calculus'),
    );
    expect(h.last.method, 'POST');
    expect(h.last.url.toString(), 'http://127.0.0.1:8000/api/uploads');
    expect(h.last.headers['content-type'], startsWith('multipart/form-data; boundary='));
    final body = utf8.decode(h.last.bodyBytes);
    expect(body, contains('name="file"'));
    expect(body, contains('filename="Calculus syllabus.md"'));
    expect(body, contains('# Calculus'));
    expect(r.id, 3);
    expect(r.filename, 'Calculus syllabus.md');
    expect(r.chars, 18234);
    expect(r.createdAt, DateTime.utc(2026, 10, 5, 3));
  });

  test('24 uploadFile: 400 messages are translated', () async {
    final h = Harness({'detail': 'Only PDF, TXT or MD files up to 4 MB.'}, 400);
    try {
      await h.api.uploadFile(filename: 'x.exe', bytes: [1]);
      fail('expected an ApiException');
    } on ApiException catch (e) {
      expect(e.statusCode, 400);
      expect(e.userMessage, 'Only PDF, TXT or MD files up to 4 MB.');
    }
    final unreadable = Harness({'detail': 'No text could be read from this file.'}, 400);
    try {
      await unreadable.api.uploadFile(filename: 'x.pdf', bytes: [1]);
      fail('expected an ApiException');
    } on ApiException catch (e) {
      expect(e.userMessage, "Couldn't read any text from this file.");
    }
  });

  test('18 sendChat: a failing front desk is a 502', () async {
    final h = Harness({
      'detail': 'The assistant is temporarily unavailable. Please try again.',
    }, 502);
    try {
      await h.api.sendChat('Hi');
      fail('expected an ApiException');
    } on ApiException catch (e) {
      expect(e.statusCode, 502);
      expect(e.userMessage, ApiException.aiFailureText);
    }
  });

  test('19 getChatHistory: GET /chat/history?limit=', () async {
    final h = Harness([userMessage]);
    final r = await h.api.getChatHistory();
    expect(h.last.method, 'GET');
    expect(h.last.url.path, '/api/chat/history');
    expect(h.last.url.queryParameters, {'limit': '50'});
    expect(r.single.content, 'I want to learn math');

    await h.api.getChatHistory(limit: 200);
    expect(h.last.url.queryParameters, {'limit': '200'});
  });

  test('20 getChatSuggestions: GET /chat/suggestions → the list inside the object', () async {
    final h = Harness({
      'suggestions': [
        {'label': 'How was your day?', 'message': 'Let me log my day', 'skill_id': null},
        {
          'label': 'Start with “Discriminant”',
          'message': 'Start with “Discriminant”',
          'skill_id': 6,
        },
      ],
    });
    final r = await h.api.getChatSuggestions();
    expect(h.last.method, 'GET');
    expect(h.last.url.path, '/api/chat/suggestions');
    expect(r.map((s) => s.skillId), [null, 6]);

    final none = Harness({
      'suggestions': [
        {'label': 'Tell me what you want to learn', 'message': '', 'skill_id': null},
      ],
    });
    final line = (await none.api.getChatSuggestions()).single;
    expect(line.message, isEmpty);
    expect(line.skillId, isNull);

    final empty = Harness({'suggestions': []});
    expect(await empty.api.getChatSuggestions(), isEmpty);
  });

  test('21 getTodayCheckIn: GET /checkins/today → record or JSON null', () async {
    final h = Harness({
      'date': '2026-10-05',
      'sleep_hours': 6,
      'exercised': false,
      'diet_note': 'lunch: ramen',
      'focus': null,
      'stress': null,
      'transcript': 'Last night I slept six hours',
      'source': 'voice',
    });
    final r = await h.api.getTodayCheckIn();
    expect(h.last.method, 'GET');
    expect(h.last.url.path, '/api/checkins/today');
    expect(r!.sleepHours, 6);

    final none = Harness(null);
    expect(await none.api.getTodayCheckIn(), isNull);
  });

  test('22 getSkillOverview: GET /skills/{id}/overview', () async {
    final h = Harness({
      'skill': nodeJson,
      'course': courseJson,
      'contains_parents': [],
      'requires': [],
      'audits': [],
      'materials': [],
    });
    final r = await h.api.getSkillOverview(5);
    expect(h.last.method, 'GET');
    expect(h.last.url.path, '/api/skills/5/overview');
    expect(r.skill.title, 'Quadratic Equations');
  });

  test('22 getSkillOverview: 404 skill not found', () async {
    final h = Harness({'detail': 'skill not found'}, 404);
    try {
      await h.api.getSkillOverview(99);
      fail('expected an ApiException');
    } on ApiException catch (e) {
      expect(e.statusCode, 404);
    }
  });

  test('23 listAudits: GET /audits?limit=', () async {
    final h = Harness([
      {
        'id': 31,
        'skill_id': 5,
        'skill_title': 'Quadratic Equations',
        'status': 'failed',
        'score': 45,
        'created_at': '2026-10-05T03:20:00Z',
      },
    ]);
    final r = await h.api.listAudits();
    expect(h.last.method, 'GET');
    expect(h.last.url.path, '/api/audits');
    expect(h.last.url.queryParameters, {'limit': '20'});
    expect(r.single.status, AuditStatus.failed);

    await h.api.listAudits(limit: 100);
    expect(h.last.url.queryParameters, {'limit': '100'});
  });

  test('a body of the wrong shape becomes an ApiException', () async {
    final h = Harness({'unexpected': true});
    expect(() => h.api.getChatSuggestions(), throwsA(isA<ApiException>()));
    expect(() => h.api.sendChat('x'), throwsA(isA<ApiException>()));
  });
}
