// HttpApi, endpoints 16 and 25-27 (life as a game) and the reflection prompt of
// endpoint 18: method, path, body, parsing.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:self_infinity/api/api_exception.dart';
import 'package:self_infinity/api/http_api.dart';

const Map<String, dynamic> profileJson = {
  'identity': 'I am the type of person who explains things from first principles.',
  'vision': 'A clear mind',
  'anti_vision': 'Drifting',
  'rules': ['No phone before the first audit'],
  'updated_at': '2026-10-05T03:00:00Z',
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
  test('25 getProfile: GET /profile', () async {
    final h = Harness(profileJson);
    final p = await h.api.getProfile();
    expect(h.last.method, 'GET');
    expect(h.last.url.toString(), 'http://127.0.0.1:8000/api/profile');
    expect(p.vision, 'A clear mind');
    expect(p.antiVision, 'Drifting');
    expect(p.rules, ['No phone before the first audit']);
    expect(p.updatedAt, DateTime.utc(2026, 10, 5, 3));
  });

  test('26 updateProfile: PUT /profile with only the fields that are given', () async {
    final h = Harness(profileJson);
    await h.api.updateProfile(vision: 'A clear mind');
    expect(h.last.method, 'PUT');
    expect(h.last.url.toString(), 'http://127.0.0.1:8000/api/profile');
    expect(h.last.headers['content-type'], startsWith('application/json'));
    expect(jsonDecode(h.last.body), {'vision': 'A clear mind'});

    await h.api.updateProfile(
      identity: 'I am…',
      antiVision: '',
      rules: ['a', 'b'],
    );
    expect(jsonDecode(h.last.body), {
      'identity': 'I am…',
      'anti_vision': '',
      'rules': ['a', 'b'],
    });

    // An empty text and an empty list are real values, not “omitted”.
    await h.api.updateProfile(vision: '', rules: []);
    expect(jsonDecode(h.last.body), {'vision': '', 'rules': []});
  });

  test('26 updateProfile: an over-limit value is a 422', () async {
    final h = Harness({
      'detail': [
        {'msg': 'String should have at most 280 characters'},
      ],
    }, 422);
    try {
      await h.api.updateProfile(vision: 'x' * 281);
      fail('expected an ApiException');
    } on ApiException catch (e) {
      expect(e.statusCode, 422);
      expect(e.userMessage, ApiException.invalidInputText);
    }
  });

  test('27 listJournal: GET /journal?limit=', () async {
    final h = Harness([
      {
        'id': 4,
        'prompt': 'What are you putting off right now?',
        'answer': 'The taxes',
        'created_at': '2026-10-05T02:10:00Z',
      },
    ]);
    final r = await h.api.listJournal(limit: 5);
    expect(h.last.method, 'GET');
    expect(h.last.url.path, '/api/journal');
    expect(h.last.url.queryParameters, {'limit': '5'});
    expect(r.single.answer, 'The taxes');
    await h.api.listJournal();
    expect(h.last.url.queryParameters, {'limit': '20'});
  });

  test('16 getCurrentPlan: GET /plan/current, a plan or null', () async {
    final plan = {
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
    final h = Harness(plan);
    final p = await h.api.getCurrentPlan();
    expect(h.last.method, 'GET');
    expect(h.last.url.toString(), 'http://127.0.0.1:8000/api/plan/current');
    expect(p!.steps.single.skillTitle, 'Quadratic Functions');

    expect(await Harness(null).api.getCurrentPlan(), isNull);
  });

  test('18 sendChat: reflection_prompt goes in the body only when set', () async {
    final h = Harness({
      'messages': [
        {
          'id': 1,
          'role': 'assistant',
          'content': 'What are you putting off right now?',
          'agent': 'front_desk',
          'action': null,
          'created_at': '2026-10-05T03:00:00Z',
        },
        {
          'id': 2,
          'role': 'user',
          'content': 'The taxes',
          'agent': null,
          'action': null,
          'created_at': '2026-10-05T03:00:00Z',
        },
        {
          'id': 3,
          'role': 'assistant',
          'content': "Noted. It's in your journal.",
          'agent': 'front_desk',
          'action': null,
          'created_at': '2026-10-05T03:00:00Z',
        },
      ],
    });
    final r = await h.api.sendChat(
      'The taxes',
      reflectionPrompt: 'What are you putting off right now?',
    );
    expect(h.last.url.toString(), 'http://127.0.0.1:8000/api/chat');
    expect(jsonDecode(h.last.body), {
      'message': 'The taxes',
      'reflection_prompt': 'What are you putting off right now?',
    });
    expect(r.map((m) => m.content), [
      'What are you putting off right now?',
      'The taxes',
      "Noted. It's in your journal.",
    ]);
    await h.api.sendChat('Hi');
    expect(jsonDecode(h.last.body), {'message': 'Hi'});
    await h.api.sendChat('I want to learn this', uploadIds: [4], courseTopic: '');
    expect(jsonDecode(h.last.body), {
      'message': 'I want to learn this',
      'upload_ids': [4],
      'course_topic': '',
    });
  });
}
