// Parses the JSON examples of docs/api-contract.md Section 5 (stage UI).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/models.dart';

Json obj(String source) => jsonDecode(source) as Json;

const String courseJson = '''
{"id": 1, "topic": "math", "source_course": null, "source_url": null,
 "created_at": "2026-10-05T03:00:00Z"}''';

const String nodeJson = '''
{"id": 5, "course_id": 1, "slug": "quadratic-equation", "title": "Quadratic Equations",
 "description": "...", "status": "available", "node_type": "concept", "mastery_score": null}''';

const String checkinResultJson = '''
{"checkin": {"date": "2026-10-05", "sleep_hours": 6, "exercised": false, "diet_note": "lunch: ramen",
             "focus": null, "stress": null, "transcript": "Last night I slept six hours", "source": "voice"},
 "missing_fields": ["focus", "stress"]}''';

const String factsJson = '''
{"nodes": {"total": 12, "mastered": 4, "available": 3, "locked": 5},
 "audits": {"total": 6, "passed": 4, "failed": 2},
 "misconception_clusters": [],
 "condition": {"days": 0, "avg_sleep_hours": null, "avg_stress": null, "flag": "unknown"}''';

const String planJson = '''
{"id": 3, "suggested_tier": "medium", "context_bucket": "mid", "created_at": "2026-10-05T03:31:00Z",
 "steps": [{"skill_id": 9, "course_id": 1, "skill_title": "Quadratic Functions", "node_type": "concept",
            "rationale": "...", "focus_hint": "..."}]}''';

ChatMessage message(String action) => ChatMessage.fromJson(
  obj('''
  {"id": 12, "role": "assistant", "content": "...", "agent": "front_desk",
   "action": $action, "created_at": "2026-10-05T03:00:00Z"}'''),
);

void main() {
  group('ProfileFacts.xp', () {
    test('parses total, level and progress', () {
      final f = ProfileFacts.fromJson(
        obj('$factsJson, "xp": {"total": 220, "level": 2, "level_progress": 0.4}}'),
      );
      expect(f.xp.total, 220);
      expect(f.xp.level, 2);
      expect(f.xp.levelProgress, 0.4);
    });

    test('an older server without xp: level 1 + mastered // 5, no XP total', () {
      final f = ProfileFacts.fromJson(obj('$factsJson}'));
      expect(f.nodes.mastered, 4);
      expect(f.xp.total, 0);
      expect(f.xp.level, 1);
      expect(f.xp.levelProgress, 0.8);
      expect(XpFacts.fromMastered(5).level, 2);
      expect(XpFacts.fromMastered(5).levelProgress, 0);
      expect(const XpFacts().level, 1);
    });

    test('integer progress values are accepted', () {
      final f = ProfileFacts.fromJson(
        obj('$factsJson, "xp": {"total": 0, "level": 1, "level_progress": 0}}'),
      );
      expect(f.xp.levelProgress, 0);
    });
  });

  group('ChatMessage', () {
    test('a user message has no agent and no action', () {
      final m = ChatMessage.fromJson(
        obj('''
        {"id": 11, "role": "user", "content": "I want to learn math", "agent": null,
         "action": null, "created_at": "2026-10-05T03:00:00Z"}'''),
      );
      expect(m.isUser, isTrue);
      expect(m.role, ChatRole.user);
      expect(m.agent, isNull);
      expect(m.action, isNull);
      expect(m.createdAt, DateTime.utc(2026, 10, 5, 3));
    });

    test('an assistant message without action', () {
      final m = message('null');
      expect(m.isUser, isFalse);
      expect(m.agent, 'front_desk');
      expect(m.action, isNull);
    });

    test('action course', () {
      final a = message('{"type": "course", "course": $courseJson, "node_count": 12}').action;
      expect(a, isA<CourseAction>());
      a as CourseAction;
      expect(a.course.id, 1);
      expect(a.nodeCount, 12);
    });

    test('action checkin carries the endpoint 12 body', () {
      final a = message('{"type": "checkin", "result": $checkinResultJson}').action;
      expect(a, isA<CheckInAction>());
      a as CheckInAction;
      expect(a.result.checkin.sleepHours, 6);
      expect(a.result.missingFields, [CheckInField.focus, CheckInField.stress]);
    });

    test('action plan', () {
      final a = message('{"type": "plan", "plan": $planJson}').action;
      expect(a, isA<PlanAction>());
      expect((a as PlanAction).plan.steps.single.skillTitle, 'Quadratic Functions');
    });

    test('action briefing', () {
      final a = message(
        '{"type": "briefing", "briefing": {"facts": $factsJson}, "narrative": "n", "narrative_generated_at": null}}',
      ).action;
      expect(a, isA<BriefingAction>());
      expect((a as BriefingAction).briefing.narrative, 'n');
    });

    test('action navigate: map and skill (there is no dex scene any more)', () {
      var a = message('{"type": "navigate", "scene": "map"}').action as NavigateAction;
      expect(a.scene, NavScene.map);
      expect(a.skillId, isNull);
      expect(() => message('{"type": "navigate", "scene": "dex"}'), throwsFormatException);
      a = message('{"type": "navigate", "scene": "skill", "skill_id": 5}').action as NavigateAction;
      expect(a.scene, NavScene.skill);
      expect(a.skillId, 5);
    });

    test('unknown action types, scenes and roles are rejected', () {
      expect(() => message('{"type": "teleport"}'), throwsFormatException);
      expect(() => message('{"type": "navigate", "scene": "moon"}'), throwsFormatException);
      expect(
        () => ChatMessage.fromJson(
          obj('{"id": 1, "role": "system", "content": "", "created_at": "2026-10-05T03:00:00Z"}'),
        ),
        throwsFormatException,
      );
    });
  });

  group('ChatSuggestion', () {
    test('with and without skill_id', () {
      final a = ChatSuggestion.fromJson(
        obj('{"label": "How was your day?", "message": "Let me log my day", "skill_id": null}'),
      );
      expect(a.label, 'How was your day?');
      expect(a.message, 'Let me log my day');
      expect(a.skillId, isNull);
      final b = ChatSuggestion.fromJson(
        obj(
          '{"label": "Start with “Discriminant”", "message": "Start with “Discriminant”", "skill_id": 6}',
        ),
      );
      expect(b.skillId, 6);
    });
  });

  group('AuditSummary', () {
    test('parses an audit line', () {
      final a = AuditSummary.fromJson(
        obj('''
        {"id": 31, "skill_id": 5, "skill_title": "Quadratic Equations", "status": "failed", "score": 45,
         "created_at": "2026-10-05T03:20:00Z"}'''),
      );
      expect(a.id, 31);
      expect(a.skillId, 5);
      expect(a.skillTitle, 'Quadratic Equations');
      expect(a.status, AuditStatus.failed);
      expect(a.score, 45);
      expect(a.createdAt, DateTime.utc(2026, 10, 5, 3, 20));
    });

    test('an active audit has no score', () {
      final a = AuditSummary.fromJson(
        obj('''
        {"id": 32, "skill_id": 5, "skill_title": "x", "status": "active", "score": null,
         "created_at": "2026-10-05T03:20:00Z"}'''),
      );
      expect(a.status, AuditStatus.active);
      expect(a.score, isNull);
    });
  });

  group('SkillOverview', () {
    test('parses parents, prerequisites, audits and materials', () {
      final o = SkillOverview.fromJson(
        obj('''
        {"skill": $nodeJson, "course": $courseJson,
         "contains_parents": [{"id": 2, "course_id": 1, "slug": "algebra", "title": "Algebra",
                               "description": "", "status": "mastered", "node_type": "concept",
                               "mastery_score": 80}],
         "requires": [{"skill": $nodeJson, "reason": "You need to know it first"}],
         "audits": [{"id": 31, "skill_id": 5, "skill_title": "Quadratic Equations", "status": "passed",
                     "score": 90, "created_at": "2026-10-05T03:20:00Z"}],
         "materials": [{"id": 2, "skill_id": 5, "gap": "g", "queries": ["q"],
                        "items": [{"title": "t", "url": "https://example.org/1", "snippet": "s", "reason": "r"}],
                        "created_at": "2026-10-05T03:40:00Z"}]}'''),
      );
      expect(o.skill.title, 'Quadratic Equations');
      expect(o.course.id, 1);
      expect(o.containsParents.single.title, 'Algebra');
      expect(o.requires.single.reason, 'You need to know it first');
      expect(o.requires.single.skill.id, 5);
      expect(o.audits.single.status, AuditStatus.passed);
      expect(o.materials.single.items.single.url, 'https://example.org/1');
    });

    test('empty lists and a missing reason are fine', () {
      final o = SkillOverview.fromJson(
        obj('''
        {"skill": $nodeJson, "course": $courseJson, "contains_parents": [],
         "requires": [{"skill": $nodeJson, "reason": null}], "audits": [], "materials": []}'''),
      );
      expect(o.containsParents, isEmpty);
      expect(o.requires.single.reason, isNull);
      expect(o.audits, isEmpty);
      expect(o.materials, isEmpty);
    });
  });
}
