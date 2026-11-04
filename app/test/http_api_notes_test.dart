// HttpApi, endpoint 52 (study notes on a node): method, path, body, parsing.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:self_infinity/api/api_exception.dart';
import 'package:self_infinity/api/http_api.dart';

const Map<String, dynamic> noteJson = {
  'id': 3,
  'skill_id': 6,
  'content': 'b² − 4ac decides',
  'created_at': '2026-11-04T03:00:00Z',
  'updated_at': '2026-11-04T04:00:00Z',
};

void main() {
  late List<http.Request> requests;

  HttpApi api(Object? body, [int status = 200]) {
    requests = [];
    return HttpApi(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response.bytes(
          utf8.encode(jsonEncode(body)),
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  }

  test('listNodeNotes: GET /skills/{id}/notes', () async {
    final notes = await api([noteJson]).listNodeNotes(6);
    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/skills/6/notes');
    expect(notes.single.content, 'b² − 4ac decides');
    expect(notes.single.skillId, 6);
    expect(notes.single.createdAt, DateTime.utc(2026, 11, 4, 3));
    expect(notes.single.updatedAt, DateTime.utc(2026, 11, 4, 4));
  });

  test('createNodeNote: POST /skills/{id}/notes {content}', () async {
    final note = await api(noteJson).createNodeNote(6, 'b² − 4ac decides');
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/skills/6/notes');
    expect(jsonDecode(requests.single.body), {'content': 'b² − 4ac decides'});
    expect(note.id, 3);
  });

  test('updateNodeNote: PUT /notes/{id} {content}', () async {
    await api(noteJson).updateNodeNote(3, 'new');
    expect(requests.single.method, 'PUT');
    expect(requests.single.url.path, '/api/notes/3');
    expect(jsonDecode(requests.single.body), {'content': 'new'});
  });

  test('deleteNodeNote: DELETE /notes/{id}', () async {
    await api(null, 204).deleteNodeNote(3);
    expect(requests.single.method, 'DELETE');
    expect(requests.single.url.path, '/api/notes/3');
  });

  test('an empty note is a 400 with the server message', () async {
    await expectLater(
      api({'detail': 'note must not be empty'}, 400).createNodeNote(6, ' '),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
    );
  });
}
