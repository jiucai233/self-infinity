// FakeApiClient in Korean and Chinese, and its demo mode.
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/graph_utils.dart';
import 'package:self_infinity/api/models.dart';

FakeApiClient fake({String language = 'en', bool demo = false}) =>
    FakeApiClient(latency: Duration.zero, language: language, demo: demo);

final _ascii = RegExp(r'^[\x00-\x7F]+$');

/// An English sentence: two or more plain-ASCII words in a row.
final _englishSentence = RegExp(r'[A-Za-z]{3,} [A-Za-z]{2,}');

Future<CourseMap> course(FakeApiClient api, String topic) =>
    api.generateCourse(GenerateRequest(topic: topic));

void expectNoEnglish(String text) =>
    expect(_englishSentence.hasMatch(text), isFalse, reason: 'English in: $text');

void main() {
  test('the default fake still speaks English', () async {
    final api = FakeApiClient(latency: Duration.zero);
    expect(api.language, 'en');
    expect(api.demo, isFalse);
    final map = await course(api, 'math');
    expect(rootNodes(map.nodes, map.edges).single.title, 'High School Math');
    final start = await api.startAudit(map.nodes.firstWhere((n) => n.slug == 'discriminant').id);
    expect(
      start.openingQuestion,
      startsWith('I have never learned “Discriminant”. Start small'),
    );
    expect(FakeApiClient(latency: Duration.zero, language: 'fr').language, 'fr');
    final other = await course(FakeApiClient(latency: Duration.zero, language: 'fr'), 'math');
    expect(other.nodes.first.title, 'High School Math');
  });

  for (final (language, topic, rootTitle, generic) in [
    ('ko', '수학', '고등학교 수학', '우주 탐사'),
    ('zh', '数学', '高中数学', '宇宙探索'),
  ]) {
    group(language, () {
      test('the math course is localized', () async {
        final api = fake(language: language);
        final map = await course(api, topic);
        expect(map.nodes, hasLength(12));
        expect(rootNodes(map.nodes, map.edges).single.title, rootTitle);
        for (final n in map.nodes) {
          expect(_ascii.hasMatch(n.title), isFalse, reason: n.title);
          expectNoEnglish(n.description);
        }
        for (final e in map.edges.where((e) => e.kind == SkillEdgeKind.requires)) {
          expectNoEnglish(e.reason ?? '');
        }
        final withSyllabus = await api.generateCourse(GenerateRequest(topic: topic, searchSyllabus: true));
        expectNoEnglish(withSyllabus.course.sourceCourse!);
      });

      test('a generic course has localized branches', () async {
        final map = await course(fake(language: language), generic);
        expect(map.nodes, hasLength(10));
        final root = rootNodes(map.nodes, map.edges).single;
        expect(root.title, generic);
        for (final n in map.nodes.where((n) => n.id != root.id)) {
          expect(_ascii.hasMatch(n.title), isFalse, reason: n.title);
          expectNoEnglish(n.description);
        }
      });

      test('an audit opens, probes and judges in the language', () async {
        final api = fake(language: language);
        final map = await course(api, topic);
        final leaf = map.nodes.firstWhere((n) => n.slug == 'discriminant');
        final start = await api.startAudit(leaf.id);
        expectNoEnglish(start.openingQuestion);
        for (final p in start.session.points) {
          expectNoEnglish(p.title);
        }
        final probe = await api.submitTurn(start.session.id, 'x') as ProbeResult;
        expectNoEnglish(probe.question);
        expectNoEnglish(probe.feedback!);
        final verdict = await api.submitTurn(start.session.id, 'y') as VerdictResult;
        expect(verdict.passed, isFalse);
        expectNoEnglish(verdict.comment!);
        for (final g in verdict.gaps) {
          expectNoEnglish(g);
        }
        expectNoEnglish(verdict.feedback!);
        final lesson = await api.submitReflection(start.session.id, 'z');
        expectNoEnglish(lesson.title);
        expectNoEnglish(lesson.body);
      });

      test('chat replies are localized', () async {
        final api = fake(language: language);
        final reply = await api.sendChat(
          language == 'ko' ? '수학을 배우고 싶어요' : '我想学数学',
        );
        final said = reply.where((m) => !m.isUser).toList();
        expect(said, hasLength(2));
        for (final m in said) {
          expectNoEnglish(m.content);
        }
        expect(said.last.content, contains(rootTitle));
        final plan = await api.sendChat(language == 'ko' ? '오늘 뭐 하면 좋을까요?' : '今天做什么？');
        for (final m in plan.where((m) => !m.isUser)) {
          expectNoEnglish(m.content);
        }
        expectNoEnglish((await api.sendChat('...')).last.content);
        for (final s in await api.getChatSuggestions()) {
          expectNoEnglish(s.label);
        }
      });
    });
  }

  group('demo mode', () {
    test('a plain message builds the first course, from the topic it names', () async {
      final api = fake(language: 'ko', demo: true);
      final reply = await api.sendChat('배우고 싶은 건 컴퓨터 시스템');
      final action = reply.last.action as CourseAction;
      final map = await api.getCourseMap(action.course.id);
      expect(rootNodes(map.nodes, map.edges).single.title, '컴퓨터 시스템');
    });

    test('the stems of "I want to learn" are taken off', () async {
      for (final (language, said, title) in [
        ('ko', '컴퓨터 시스템을 배우고 싶어요', '컴퓨터 시스템'),
        ('zh', '我想要学习机器学习。', '机器学习'),
        ('zh', '我想学数学', '数学'),
        ('en', "I'd like to learn chess!", 'chess'),
        ('en', 'learn Rust', 'Rust'),
      ]) {
        final api = fake(language: language, demo: true);
        final reply = await api.sendChat(said);
        final map = await api.getCourseMap((reply.last.action as CourseAction).course.id);
        final root = rootNodes(map.nodes, map.edges).single;
        // The math course has its own title; the topic is on the course.
        expect(map.course.topic, title, reason: said);
        expect(root.title.isNotEmpty, isTrue);
      }
    });

    test('hello builds a course titled hello, and then chat is as usual', () async {
      final api = fake(demo: true);
      final first = await api.sendChat('hello');
      final map = await api.getCourseMap((first.last.action as CourseAction).course.id);
      expect(rootNodes(map.nodes, map.edges).single.title, 'hello');
      final second = await api.sendChat('hello again');
      expect(second.where((m) => !m.isUser).single.content, 'Sure. What would you like to do today?');
      expect(await api.listCourses(), hasLength(1));
    });

    test('without demo, hello builds nothing', () async {
      final api = fake();
      await api.sendChat('hello');
      expect(await api.listCourses(), isEmpty);
    });

    test('an audit passes on the second answer, with no Challenger round', () async {
      final api = fake(demo: true);
      final map = await course(api, 'math');
      final start = await api.startAudit(map.nodes.firstWhere((n) => n.slug == 'discriminant').id);
      final probe = await api.submitTurn(start.session.id, 'x');
      expect(probe, isA<ProbeResult>());
      final verdict = await api.submitTurn(start.session.id, 'x');
      expect(verdict, isA<VerdictResult>());
      expect((verdict as VerdictResult).passed, isTrue);
      final session = await api.getAudit(start.session.id);
      expect(session.turns.where((t) => !t.isUser).map((t) => t.content), isNot(contains(contains('Before I pass this'))));
      await expectLater(api.submitTurn(start.session.id, ' '), throwsA(anything));
    });
  });
}
