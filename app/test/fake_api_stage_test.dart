// FakeApiClient, endpoints 18-24 and ProfileFacts.xp: the Mock front desk
// (with uploads), the two suggestions, overview, audit list (contract Section 5).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/api_exception.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/testing/test_app.dart';

FakeApiClient newApi({DateTime Function()? clock}) =>
    FakeApiClient(latency: Duration.zero, clock: clock);

Future<ApiException> failure(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('expected an ApiException');
}

ChatMessage assistantOf(List<ChatMessage> r, int index) =>
    r.where((m) => !m.isUser).elementAt(index);

void main() {
  group('18 sendChat', () {
    test('returns the saved user message, then 1-2 assistant messages, all persisted', () async {
      final api = newApi();
      final r = await api.sendChat('Hello there');
      expect(r.first.role, ChatRole.user);
      expect(r.first.agent, isNull);
      expect(r.first.content, 'Hello there');
      expect(r, hasLength(2));
      expect(r[1].role, ChatRole.assistant);
      expect(r[1].agent, 'front_desk');
      expect(r[1].content, 'Sure. What would you like to do today?');
      expect(r[1].action, isNull);
      expect((await api.getChatHistory()).map((m) => m.id), r.map((m) => m.id));
    });

    test('a blank message is a 422', () async {
      final api = newApi();
      expect((await failure(() => api.sendChat('   '))).statusCode, 422);
      expect(await api.getChatHistory(), isEmpty);
    });

    test(
      'intent generate_course: a default course and a planner message with the action',
      () async {
        final api = newApi();
        final r = await api.sendChat('I want to learn math');
        expect(r, hasLength(3));
        expect(assistantOf(r, 0).agent, 'front_desk');
        expect(assistantOf(r, 0).content, "I'll build a world for “math”.");
        final second = assistantOf(r, 1);
        expect(second.agent, 'planner');
        expect(second.content, 'Your world “High School Math” is ready — 12 nodes.');
        final action = second.action! as CourseAction;
        expect(action.nodeCount, 12);
        expect(action.course.id, (await api.listCourses()).single.id);
        expect(await api.listSkills(), hasLength(12));
      },
    );

    test('the topic is the message minus the trailing request', () async {
      final api = newApi();
      for (final (message, topic) in [
        ('I want to learn statistics', 'statistics'),
        ("I'd like to learn reinforcement learning.", 'reinforcement learning'),
        ('Teach me physics!', 'physics'),
        ('Build me a world for history', 'history'),
      ]) {
        final r = await api.sendChat(message);
        expect(assistantOf(r, 0).content, "I'll build a world for “$topic”.", reason: message);
      }
      expect(await api.listCourses(), hasLength(4));
    });

    test('an empty topic is asked back and nothing is generated', () async {
      final api = newApi();
      for (final message in ['Build me a world for', 'I want to study', 'Make a world about!']) {
        final r = await api.sendChat(message);
        expect(r, hasLength(2), reason: message);
        expect(assistantOf(r, 0).content, 'What topic should I build?');
        expect(assistantOf(r, 0).action, isNull);
      }
      expect(await api.listCourses(), isEmpty);
    });

    test(
      'intent open_skill: the first message gets a navigate action, no second message',
      () async {
        final api = await seededFakeApi();
        final r = await api.sendChat('Let me try Quadratic Equations');
        expect(r, hasLength(2));
        expect(assistantOf(r, 0).content, 'Taking you to “Quadratic Equations”.');
        final nav = assistantOf(r, 0).action! as NavigateAction;
        expect(nav.scene, NavScene.skill);
        expect(nav.skillId, 5);
        for (final word in ['audit', 'open', 'continue', 'start', 'challenge']) {
          final again = await api.sendChat('Discriminant $word');
          expect((assistantOf(again, 0).action! as NavigateAction).skillId, 6, reason: word);
        }
      },
    );

    test(
      'a title without challenge|audit|try|open|continue|start does not open the node',
      () async {
        final api = await seededFakeApi();
        final r = await api.sendChat('Quadratic Equations is hard');
        expect(assistantOf(r, 0).action, isNull);
        expect(assistantOf(r, 0).content, 'Sure. What would you like to do today?');
      },
    );

    test('when several titles match, the longest wins', () async {
      final api = await seededFakeApi();
      final r = await api.sendChat('Challenge Limits of Sequences');
      expect((assistantOf(r, 0).action! as NavigateAction).skillId, 11); // not Sequences (8)
    });

    test('intent checkin: the converter parses the message and lists what was recorded', () async {
      final api = await seededFakeApi();
      final r = await api.sendChat("I slept six hours and didn't exercise. I had ramen for lunch.");
      expect(assistantOf(r, 0).content, 'Got it, logging that.');
      final second = assistantOf(r, 1);
      expect(second.agent, 'checkin_converter');
      expect(second.content, 'Logged: sleep 6 h · exercise no · meals lunch: ramen');
      final action = second.action! as CheckInAction;
      expect(action.result.checkin.sleepHours, 6);
      expect(action.result.missingFields, [CheckInField.focus, CheckInField.stress]);
      expect((await api.getTodayCheckIn())!.dietNote, 'lunch: ramen');
    });

    test('intent checkin with nothing to read still answers', () async {
      final api = newApi();
      final r = await api.sendChat('Let me log my day');
      expect(
        assistantOf(r, 1).content,
        "I couldn't find anything to log. Tell me about sleep, exercise or meals.",
      );
      expect((assistantOf(r, 1).action! as CheckInAction).result.missingFields, hasLength(5));
    });

    test('intent plan: the recommender with the plan', () async {
      final api = await seededFakeApi();
      final r = await api.sendChat('What should I do today?');
      expect(assistantOf(r, 0).content, "Let me pick today's quests.");
      final second = assistantOf(r, 1);
      expect(second.agent, 'recommender');
      expect((second.action! as PlanAction).plan.steps.first.skillTitle, 'High School Math');
    });

    test('intent briefing: the narrator, content = the narrative', () async {
      final api = await seededFakeApi();
      final r = await api.sendChat('Give me a status report');
      expect(assistantOf(r, 0).content, 'Let me sum up where you are.');
      final second = assistantOf(r, 1);
      expect(second.agent, 'narrator');
      expect(second.content, startsWith("You've cleared 0 of 12 nodes."));
      expect((second.action! as BriefingAction).briefing.narrative, second.content);
    });

    test('intent open_map; there is no dex any more', () async {
      final api = newApi();
      var r = await api.sendChat('Show me the map');
      expect(r, hasLength(2));
      expect(assistantOf(r, 0).content, 'Opening your life tree.');
      expect((assistantOf(r, 0).action! as NavigateAction).scene, NavScene.map);
      r = await api.sendChat('Open the world');
      expect((assistantOf(r, 0).action! as NavigateAction).scene, NavScene.map);
      r = await api.sendChat('Show me the collection');
      expect(assistantOf(r, 0).action, isNull);
      expect(assistantOf(r, 0).content, 'Sure. What would you like to do today?');
    });

    group('with uploads', () {
      Future<List<int>> upload(
        FakeApiClient api,
        String name, [
        String body = '# Course\nContents',
      ]) async {
        final up = await api.uploadFile(filename: name, bytes: utf8.encode(body));
        return [up.id];
      }

      test(
        'intent none: the front desk replies, then the planner builds a course from the file',
        () async {
          final api = newApi();
          final ids = await upload(api, 'Calculus syllabus.md');
          final r = await api.sendChat('Take a look at this file', uploadIds: ids);
          expect(r, hasLength(3));
          expect(assistantOf(r, 0).agent, 'front_desk');
          final second = assistantOf(r, 1);
          expect(second.agent, 'planner');
          final course = (second.action! as CourseAction).course;
          expect(course.topic, 'Calculus syllabus');
          expect(course.sourceCourse, 'Calculus syllabus.md');
          expect(course.sourceUrl, isNull);
          expect(course.hasSource, isTrue);
          expect(course.hasSourceLink, isFalse);
          expect(await api.listCourses(), hasLength(1));
        },
      );

      test('"I want to learn this" names no topic: the file name does', () async {
        final api = newApi();
        final ids = await upload(api, 'linear algebra.pdf', 'text');
        final r = await api.sendChat('I want to learn this', uploadIds: ids);
        expect((assistantOf(r, 1).action! as CourseAction).course.topic, 'linear algebra');
      });

      test('intent generate_course: the topic of the message names the course', () async {
        final api = newApi();
        final ids = await upload(api, 'course.txt');
        final r = await api.sendChat('I want to study statistics', uploadIds: ids);
        final course = (assistantOf(r, 1).action! as CourseAction).course;
        expect(course.topic, 'statistics');
        expect(course.sourceCourse, 'course.txt');
      });

      test('several files: source_course joins the names with ", "', () async {
        final api = newApi();
        final a = await upload(api, 'a.md');
        final b = await upload(api, 'b.pdf', 'PDF text');
        final r = await api.sendChat('I want to learn this', uploadIds: [...a, ...b]);
        final course = (assistantOf(r, 1).action! as CourseAction).course;
        expect(course.sourceCourse, 'a.md, b.pdf');
      });

      test('other intents ignore the files', () async {
        final api = await seededFakeApi();
        final ids = await upload(api, 'a.md');
        final r = await api.sendChat('Show me the map', uploadIds: ids);
        expect(assistantOf(r, 0).action, isA<NavigateAction>());
        expect(await api.listCourses(), hasLength(1));
      });

      test('an unknown upload id is a 404 and nothing is saved', () async {
        final api = newApi();
        final e = await failure(() => api.sendChat('I want to learn this', uploadIds: [99]));
        expect(e.statusCode, 404);
        expect(e.serverMessage, 'upload not found');
        expect(await api.getChatHistory(), isEmpty);
        expect(await api.listCourses(), isEmpty);
      });
    });

    test('rules are literal and ordered: sleep beats report, learn beats map', () async {
      final api = await seededFakeApi();
      var r = await api.sendChat('sleep report');
      expect(assistantOf(r, 1).agent, 'checkin_converter');
      r = await api.sendChat('study the map');
      expect(assistantOf(r, 1).agent, 'planner');
    });

    test('a failing pipeline is explained in a front_desk message (still a success)', () async {
      final api = newApi();
      var r = await api.sendChat('What should I do today?'); // nothing to plan yet
      expect(r, hasLength(3));
      expect(assistantOf(r, 1).agent, 'front_desk');
      expect(assistantOf(r, 1).action, isNull);
      expect(assistantOf(r, 1).content, 'No node is ready yet. Make a world first.');

      api.failNext(method: 'generateCourse');
      r = await api.sendChat('I want to learn math');
      expect(assistantOf(r, 1).agent, 'front_desk');
      expect(
        assistantOf(r, 1).content,
        "I couldn't build that world. Please try again in a moment.",
      );
      expect(await api.listCourses(), isEmpty);

      await api.generateCourse(const GenerateRequest(topic: 'math'));
      api.failNext(method: 'narrate');
      r = await api.sendChat('status report');
      expect(assistantOf(r, 1).content, "I couldn't put your status together. Please try again.");
    });

    test('a failing front desk is a 502, but the user message is saved', () async {
      final api = newApi();
      api.failNext(method: 'sendChat');
      final e = await failure(() => api.sendChat('Hello there'));
      expect(e.statusCode, 502);
      final history = await api.getChatHistory();
      expect(history.single.content, 'Hello there');
      expect(history.single.isUser, isTrue);
    });
  });

  group('19 getChatHistory', () {
    test('oldest first, the last `limit` messages, ids increasing', () async {
      final api = newApi();
      await api.sendChat('one');
      await api.sendChat('two');
      await api.sendChat('three');
      final all = await api.getChatHistory();
      expect(all.where((m) => m.isUser).map((m) => m.content), ['one', 'two', 'three']);
      expect(all.map((m) => m.id).toList(), [1, 2, 3, 4, 5, 6]);
      final last2 = await api.getChatHistory(limit: 2);
      expect(last2.map((m) => m.id), [5, 6]);
      expect((await api.getChatHistory(limit: 200)), hasLength(6));
    });

    test('limit must be 1-200', () async {
      final api = newApi();
      expect((await failure(() => api.getChatHistory(limit: 0))).statusCode, 422);
      expect((await failure(() => api.getChatHistory(limit: 201))).statusCode, 422);
    });
  });

  group('20 getChatSuggestions', () {
    test('no course, no check-in: the check-in question, then the "tell me" line', () async {
      final s = await newApi().getChatSuggestions();
      expect(s.map((x) => x.label), ['How was your day?', 'Tell me what you want to learn']);
      expect(s[0].message, 'Let me log my day');
      expect(s[1].message, ''); // the client only focuses the input
      expect(s.every((x) => x.skillId == null), isTrue);
    });

    test('checked in: this window\'s reflection prompt, then the second kind', () async {
      final api = newApi(clock: () => DateTime.utc(2026, 10, 5, 3)); // 12:00 KST
      await api.checkInVoice('I slept seven hours.');
      final s = await api.getChatSuggestions();
      expect(s.map((x) => x.label), [
        'What are you putting off right now?',
        'Tell me what you want to learn',
      ]);
      expect(s.map((x) => x.reflection), [true, false]);
      expect(s[0].message, '');
      expect(s[0].skillId, isNull);
    });

    test('a fresh course: the lowest available node of the newest course', () async {
      final api = await seededFakeApi();
      final s = await api.getChatSuggestions();
      expect(s.map((x) => x.label), ['How was your day?', 'Start with “High School Math”']);
      expect(s[1].skillId, 1);
      expect(s[1].message, s[1].label);
    });

    test('the newest course decides which node is offered', () async {
      final api = await seededFakeApi();
      await api.generateCourse(const GenerateRequest(topic: 'reinforcement learning'));
      final s = await api.getChatSuggestions();
      expect(s.last.label, 'Start with “reinforcement learning”');
      expect(s.last.skillId, 13);
    });

    test('the most recent audit, if its node is not mastered: continue it', () async {
      final api = newApi(clock: () => DateTime.utc(2026, 10, 5, 3)); // 12:00 KST
      await api.generateCourse(const GenerateRequest(topic: 'math'));
      await api.checkInVoice('I slept seven hours.');
      await api.sendChat('Later.', reflectionPrompt: 'What are you putting off right now?');
      await failAudit(api, 1);
      final s = await api.getChatSuggestions();
      expect(s.map((x) => x.label), ['Continue “High School Math”']);
      expect(s.single.skillId, 1);
      expect(s.single.message, s.single.label);
    });

    test('an abandoned (active) audit counts as the most recent one', () async {
      final api = await seededFakeApi();
      await api.startAudit(1);
      expect((await api.getChatSuggestions()).last.label, 'Continue “High School Math”');
    });

    test('the most recent audit decides, whichever node it was on', () async {
      final api = await seededFakeApi();
      await passAudit(api, 1); // opens Algebra (2), Functions (3), Calculus (4)
      await failAudit(api, 2);
      await failAudit(api, 3);
      expect((await api.getChatSuggestions()).last.label, 'Continue “Functions”');
    });

    test('when it was mastered, the lowest available node of the newest course', () async {
      final api = await seededFakeApi();
      await failAudit(api, 1);
      await passAudit(api, 1);
      expect((await api.getChatSuggestions()).last.label, 'Start with “Algebra”');
    });

    test('no available node in the newest course: the "tell me" line', () async {
      final api = newApi();
      // A course whose only available node is mastered, with the audit on an older course.
      final map = await api.generateCourse(const GenerateRequest(topic: 'math'));
      await passAudit(api, map.nodes.first.id);
      for (final n in await api.listSkills()) {
        if (n.isAvailable) await passAudit(api, n.id);
      }
      for (var round = 0; round < 6; round++) {
        for (final n in await api.listSkills()) {
          if (n.isAvailable) await passAudit(api, n.id);
        }
      }
      expect((await api.listSkills()).every((n) => n.isMastered), isTrue);
      final s = await api.getChatSuggestions();
      expect(s.last.label, 'Tell me what you want to learn');
      expect(s.last.message, '');
    });
  });

  group('21 getTodayCheckIn', () {
    test('null before any check-in, the record after, null again on the next KST day', () async {
      var now = DateTime.utc(2026, 10, 5, 3);
      final api = newApi(clock: () => now);
      expect(await api.getTodayCheckIn(), isNull);
      await api.checkInVoice('I slept six hours and had ramen for lunch.');
      final today = await api.getTodayCheckIn();
      expect(today!.date, '2026-10-05');
      expect(today.dietNote, 'lunch: ramen');
      now = DateTime.utc(2026, 10, 5, 14, 59); // 23:59 KST: still the same day
      expect(await api.getTodayCheckIn(), isNotNull);
      now = DateTime.utc(2026, 10, 5, 15); // 00:00 KST: the next day
      expect(await api.getTodayCheckIn(), isNull);
    });
  });

  group('22 getSkillOverview', () {
    test('skill, course, parents and prerequisites with reasons', () async {
      final api = await seededFakeApi();
      final o = await api.getSkillOverview(10); // Quadratic Functions
      expect(o.skill.title, 'Quadratic Functions');
      expect(o.course.id, 1);
      expect(o.containsParents.map((n) => n.title), ['Functions']);
      expect(o.requires.map((r) => r.skill.title), ['Quadratic Equations', 'Linear Functions']);
      expect(o.requires.map((r) => r.reason), [
        'The x-intercepts of a quadratic function are the roots of a quadratic equation.',
        'You need the graph of a linear function first.',
      ]);
      expect(o.audits, isEmpty);
      expect(o.materials, isEmpty);
    });

    test('a node with two parents lists both, the main one first', () async {
      final api = await seededFakeApi();
      final o = await api.getSkillOverview(11);
      expect(o.containsParents.map((n) => n.title), ['Calculus', 'Sequences']);
    });

    test('audits and materials, newest first', () async {
      final api = await seededFakeApi();
      await failAudit(api, 1);
      await passAudit(api, 1);
      await api.createSearchPlan(1, gap: 'first gap');
      await api.createSearchPlan(1, gap: 'second gap');
      await api.createSearchPlan(2, gap: 'another node'); // not this node's
      final o = await api.getSkillOverview(1);
      expect(o.audits.map((a) => a.status), [AuditStatus.passed, AuditStatus.failed]);
      expect(o.audits.map((a) => a.skillId), [1, 1]);
      expect(o.audits.first.score, greaterThan(70));
      expect(o.audits.last.score, 45);
      expect(o.audits.first.skillTitle, 'High School Math');
      expect(o.materials.map((p) => p.gap), ['second gap', 'first gap']);
      expect(o.skill.status, SkillStatus.mastered);
    });

    test('404 skill not found', () async {
      final api = await seededFakeApi();
      final e = await failure(() => api.getSkillOverview(999));
      expect(e.statusCode, 404);
      expect(e.serverMessage, 'skill not found');
    });
  });

  group('23 listAudits', () {
    test('all courses, newest first, limited', () async {
      final api = await seededFakeApi();
      await api.generateCourse(const GenerateRequest(topic: 'reinforcement learning'));
      await failAudit(api, 1);
      await passAudit(api, 13);
      final all = await api.listAudits();
      expect(all.map((a) => a.skillTitle), ['reinforcement learning', 'High School Math']);
      expect(all.map((a) => a.status), [AuditStatus.passed, AuditStatus.failed]);
      expect(all.first.id, greaterThan(all.last.id));
      expect(await api.listAudits(limit: 1), hasLength(1));
    });

    test('an unfinished audit is listed as active, without a score', () async {
      final api = await seededFakeApi();
      await api.startAudit(1);
      final a = (await api.listAudits()).single;
      expect(a.status, AuditStatus.active);
      expect(a.score, isNull);
    });

    test('createdAt follows the clock', () async {
      final now = DateTime.utc(2026, 10, 5, 3, 20);
      final api = newApi(clock: () => now);
      await api.generateCourse(const GenerateRequest(topic: 'math'));
      await api.startAudit(1);
      expect((await api.listAudits()).single.createdAt, now);
    });

    test('limit must be 1-100', () async {
      final api = newApi();
      expect((await failure(() => api.listAudits(limit: 0))).statusCode, 422);
      expect((await failure(() => api.listAudits(limit: 101))).statusCode, 422);
      expect(await api.listAudits(limit: 100), isEmpty);
    });
  });

  group('ProfileFacts.xp', () {
    test('level starts at 1; XP is the sum of all rewards; progress is mastered % 5 / 5', () async {
      final api = await seededFakeApi();
      var xp = (await api.getBriefing()).facts.xp;
      expect(xp.total, 0);
      expect(xp.level, 1);
      expect(xp.levelProgress, 0);

      final first = await passAudit(api, 1);
      xp = (await api.getBriefing()).facts.xp;
      expect(xp.total, first.rewardAmount);
      expect(xp.level, 1);
      expect(xp.levelProgress, 0.2);

      var sum = first.rewardAmount!;
      for (final id in [2, 3, 4]) {
        sum += (await passAudit(api, id)).rewardAmount!;
      }
      xp = (await api.getBriefing()).facts.xp;
      expect(xp.total, sum);
      expect(xp.level, 1);
      expect(xp.levelProgress, 0.8);

      sum += (await passAudit(api, 5)).rewardAmount!; // the fifth cleared node
      xp = (await api.getBriefing()).facts.xp;
      expect(xp.total, sum);
      expect(xp.level, 2);
      expect(xp.levelProgress, 0);
    });

    test('a failed audit gives no XP', () async {
      final api = await seededFakeApi();
      await failAudit(api, 1);
      expect((await api.getBriefing()).facts.xp.total, 0);
    });
  });

  test('the new methods take part in failure injection', () async {
    final api = await seededFakeApi();
    for (final (method, call) in <(String, Future<Object?> Function())>[
      ('getChatHistory', () => api.getChatHistory()),
      ('getChatSuggestions', () => api.getChatSuggestions()),
      ('getTodayCheckIn', () => api.getTodayCheckIn()),
      ('getSkillOverview', () => api.getSkillOverview(1)),
      ('listAudits', () => api.listAudits()),
    ]) {
      api.failNext(method: method);
      expect((await failure(call)).statusCode, 502, reason: method);
      await call(); // one-shot
    }
  });
}
