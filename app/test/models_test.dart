// Parses every JSON example of docs/api-contract.md (Sections 2 and 3).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/models.dart';

Json obj(String source) => jsonDecode(source) as Json;

void main() {
  group('Section 2 — shared types', () {
    test('Course', () {
      final c = Course.fromJson(
        obj('''
        {"id": 1, "topic": "Math", "source_course": null, "source_url": null,
         "created_at": "2026-10-05T03:00:00Z"}'''),
      );
      expect(c.id, 1);
      expect(c.topic, 'Math');
      expect(c.sourceCourse, isNull);
      expect(c.sourceUrl, isNull);
      expect(c.hasSource, isFalse);
      expect(c.createdAt, DateTime.utc(2026, 10, 5, 3));
      expect(c.createdAt.isUtc, isTrue);
    });

    test('Course shows only the first line of the topic and keeps the source', () {
      final c = Course.fromJson(
        obj(r'''
        {"id": 2, "topic": "Statistics\n\nQ: Which one?\nA: University statistics",
         "source_course": "CS285", "source_url": "https://example.org/1",
         "created_at": "2026-10-05T03:00:00+00:00"}'''),
      );
      expect(c.title, 'Statistics');
      expect(c.hasSource, isTrue);
      expect(c.hasSourceLink, isTrue);
      expect(c.sourceCourse, 'CS285');
      expect(c.createdAt, DateTime.utc(2026, 10, 5, 3));
    });

    test('a course from uploaded files has a source name but no link', () {
      final c = Course.fromJson(
        obj(r'''
        {"id": 3, "topic": "Calculus", "source_course": "a.md, b.pdf", "source_url": null,
         "created_at": "2026-10-05T03:00:00Z"}'''),
      );
      expect(c.hasSource, isTrue);
      expect(c.hasSourceLink, isFalse);
      expect(c.sourceCourse, 'a.md, b.pdf');
    });

    test('UploadedFile', () {
      final u = UploadedFile.fromJson(
        obj(
          '{"id": 3, "filename": "course.pdf", "chars": 18234, "created_at": "2026-10-05T03:00:00Z"}',
        ),
      );
      expect(u.id, 3);
      expect(u.filename, 'course.pdf');
      expect(u.chars, 18234);
      expect(u.createdAt, DateTime.utc(2026, 10, 5, 3));
      expect(() => UploadedFile.fromJson(obj('{"id": 3}')), throwsFormatException);
    });

    test('SkillNode', () {
      final n = SkillNode.fromJson(
        obj('''
        {"id": 5, "course_id": 1, "slug": "quadratic-equation", "title": "Quadratic Equations",
         "description": "...", "status": "available", "node_type": "concept",
         "mastery_score": null}'''),
      );
      expect(n.id, 5);
      expect(n.courseId, 1);
      expect(n.slug, 'quadratic-equation');
      expect(n.title, 'Quadratic Equations');
      expect(n.status, SkillStatus.available);
      expect(n.isAvailable, isTrue);
      expect(n.nodeType, NodeType.concept);
      expect(n.masteryScore, isNull);
    });

    test('SkillNode with a mastery score and every status / node type', () {
      for (final status in SkillStatus.values) {
        for (final type in NodeType.values) {
          final n = SkillNode.fromJson({
            'id': 1,
            'course_id': 1,
            'slug': 's',
            'title': 't',
            'description': 'd',
            'status': status.value,
            'node_type': type.value,
            'mastery_score': 88,
          });
          expect(n.status, status);
          expect(n.nodeType, type);
          expect(n.masteryScore, 88);
        }
      }
    });

    test('SkillEdge: contains and requires', () {
      final contains = SkillEdge.fromJson(
        obj('{"from_id": 2, "to_id": 5, "kind": "contains", "is_primary": true, "reason": null}'),
      );
      expect(contains.fromId, 2);
      expect(contains.toId, 5);
      expect(contains.kind, SkillEdgeKind.contains);
      expect(contains.isPrimary, isTrue);
      expect(contains.reason, isNull);

      final requires = SkillEdge.fromJson(
        obj(
          '''
        {"from_id": 5, "to_id": 10, "kind": "requires", "is_primary": null,
         "reason": "The x-intercepts of a quadratic function are the roots of a quadratic equation."}''',
        ),
      );
      expect(requires.kind, SkillEdgeKind.requires);
      expect(requires.isPrimary, isNull);
      expect(
        requires.reason,
        'The x-intercepts of a quadratic function are the roots of a quadratic equation.',
      );
    });

    test('AuditSession', () {
      final s = AuditSession.fromJson(
        obj(
          '''
        {"id": 31, "skill_id": 5, "node_position": "leaf", "status": "active", "score": null,
         "gaps": [], "comment": null,
         "turns": [{"role": "auditor", "content": "Explain Quadratic Equations from scratch to someone who has never heard of it."}]}''',
        ),
      );
      expect(s.id, 31);
      expect(s.skillId, 5);
      expect(s.nodePosition, NodePosition.leaf);
      expect(s.status, AuditStatus.active);
      expect(s.score, isNull);
      expect(s.gaps, isEmpty);
      expect(s.comment, isNull);
      expect(s.turns, hasLength(1));
      expect(s.turns.single.role, AuditRole.auditor);
      expect(s.turns.single.content, contains('Quadratic Equations'));
    });

    test('TurnResult: probe', () {
      final r = TurnResult.fromJson(
        obj(
          '{"type": "probe", "question": "What is the discriminant, and why is there no solution when it is negative?"}',
        ),
      );
      expect(r, isA<ProbeResult>());
      expect(
        (r as ProbeResult).question,
        'What is the discriminant, and why is there no solution when it is negative?',
      );
    });

    test('TurnResult: failing verdict', () {
      final r = TurnResult.fromJson(
        obj('''
        {"type": "verdict", "passed": false, "score": 45, "gaps": ["..."], "comment": "...",
         "unlocked_skill_ids": [], "reward_amount": null, "reward_multiplier": null}'''),
      );
      expect(r, isA<VerdictResult>());
      final v = r as VerdictResult;
      expect(v.passed, isFalse);
      expect(v.score, 45);
      expect(v.gaps, ['...']);
      expect(v.comment, '...');
      expect(v.unlockedSkillIds, isEmpty);
      expect(v.rewardAmount, isNull);
      expect(v.rewardMultiplier, isNull);
    });

    test('TurnResult: passing verdict with reward', () {
      final v = TurnResult.fromJson(
        obj('''
        {"type": "verdict", "passed": true, "score": 82, "gaps": [], "comment": "Good",
         "unlocked_skill_ids": [6, 7], "reward_amount": 22, "reward_multiplier": 1.1}'''),
      ) as VerdictResult;
      expect(v.passed, isTrue);
      expect(v.unlockedSkillIds, [6, 7]);
      expect(v.rewardAmount, 22);
      expect(v.rewardMultiplier, 1.1);
      // An integral multiplier may arrive as an int.
      final w = TurnResult.fromJson(
        obj(
          '{"type":"verdict","passed":true,"score":90,"gaps":[],"comment":null,"unlocked_skill_ids":[],"reward_amount":20,"reward_multiplier":1}',
        ),
      ) as VerdictResult;
      expect(w.rewardMultiplier, 1.0);
    });

    test('TurnResult: switch is exhaustive over the sealed type', () {
      String describe(TurnResult r) => switch (r) {
        ProbeResult(:final question) => 'probe:$question',
        VerdictResult(:final passed) => 'verdict:$passed',
      };
      expect(describe(const ProbeResult(question: 'q')), 'probe:q');
      expect(describe(const VerdictResult(passed: true, score: 90)), 'verdict:true');
    });

    test('TurnResult rejects an unknown type', () {
      expect(() => TurnResult.fromJson({'type': 'nope'}), throwsFormatException);
    });

    test('Principle', () {
      final p = Principle.fromJson(
        obj('''
        {"id": 7, "title": "State the range of the solution first",
         "body": "When I talk about the solution of an equation, I first say which number range it lives in.",
         "misconception": "Thought no real roots means no solution at all",
         "source_session_id": 31, "skill_id": 5, "skill_title": "Quadratic Equations",
         "created_at": "2026-10-05T03:20:00Z"}'''),
      );
      expect(p.id, 7);
      expect(p.title, 'State the range of the solution first');
      expect(p.misconception, 'Thought no real roots means no solution at all');
      expect(p.hasMisconception, isTrue);
      expect(p.sourceSessionId, 31);
      expect(p.skillId, 5);
      expect(p.skillTitle, 'Quadratic Equations');
      expect(p.createdAt, DateTime.utc(2026, 10, 5, 3, 20));
    });

    test('Principle without a misconception', () {
      final p = Principle.fromJson({
        'id': 1,
        'title': 't',
        'body': 'b',
        'misconception': null,
        'source_session_id': 1,
        'skill_id': 1,
        'skill_title': 's',
        'created_at': '2026-10-05T03:20:00Z',
      });
      expect(p.hasMisconception, isFalse);
    });

    test('DailyCheckIn', () {
      final c = DailyCheckIn.fromJson(
        obj(
          '''
        {"date": "2026-10-05", "sleep_hours": 6, "exercised": false, "diet_note": "lunch: ramen",
         "focus": null, "stress": null, "transcript": "Last night I slept six hours ...", "source": "voice"}''',
        ),
      );
      expect(c.date, '2026-10-05');
      expect(c.sleepHours, 6.0);
      expect(c.exercised, isFalse);
      expect(c.dietNote, 'lunch: ramen');
      expect(c.focus, isNull);
      expect(c.stress, isNull);
      expect(c.transcript, startsWith('Last night'));
      expect(c.source, CheckInSource.voice);
    });

    test('ProfileFacts', () {
      final f = ProfileFacts.fromJson(
        obj('''
        {
          "nodes": {"total": 12, "mastered": 4, "available": 3, "locked": 5},
          "audits": {"total": 6, "passed": 4, "failed": 2},
          "misconception_clusters": [
            {"label": "Saw no real roots as no solution", "occurrences": 2,
             "skills": ["Quadratic Equations", "Quadratic Functions"], "cross_skill": true, "principle_ids": [7, 9]}
          ],
          "condition": {"days": 3, "avg_sleep_hours": 5.3, "avg_stress": null, "flag": "low"}
        }'''),
      );
      expect(f.nodes.total, 12);
      expect(f.nodes.mastered, 4);
      expect(f.nodes.available, 3);
      expect(f.nodes.locked, 5);
      expect(f.audits.total, 6);
      expect(f.audits.passed, 4);
      expect(f.audits.failed, 2);
      expect(f.misconceptionClusters, hasLength(1));
      final cluster = f.misconceptionClusters.single;
      expect(cluster.label, 'Saw no real roots as no solution');
      expect(cluster.occurrences, 2);
      expect(cluster.skills, ['Quadratic Equations', 'Quadratic Functions']);
      expect(cluster.crossSkill, isTrue);
      expect(cluster.principleIds, [7, 9]);
      expect(f.condition.days, 3);
      expect(f.condition.avgSleepHours, 5.3);
      expect(f.condition.avgStress, isNull);
      expect(f.condition.flag, ConditionFlag.low);
    });

    test('Briefing with and without a narrative', () {
      const facts = '''
        "facts": {"nodes": {"total": 1, "mastered": 0, "available": 1, "locked": 0},
                  "audits": {"total": 0, "passed": 0, "failed": 0},
                  "misconception_clusters": [],
                  "condition": {"days": 0, "avg_sleep_hours": null, "avg_stress": null, "flag": "unknown"}}''';
      final narrated = Briefing.fromJson(
        obj('''
        {$facts, "narrative": "You've cleared 4 of 12 nodes. ...",
         "narrative_generated_at": "2026-10-05T03:30:00Z"}'''),
      );
      expect(narrated.hasNarrative, isTrue);
      expect(narrated.narrative, startsWith("You've cleared 4"));
      expect(narrated.narrativeGeneratedAt, DateTime.utc(2026, 10, 5, 3, 30));
      expect(narrated.facts.condition.flag, ConditionFlag.unknown);

      final fresh = Briefing.fromJson(
        obj('{$facts, "narrative": null, "narrative_generated_at": null}'),
      );
      expect(fresh.hasNarrative, isFalse);
      expect(fresh.narrativeGeneratedAt, isNull);
    });

    test('StudyPlan', () {
      final p = StudyPlan.fromJson(
        obj('''
        {"id": 3, "suggested_tier": "medium", "context_bucket": "mid", "created_at": "2026-10-05T03:31:00Z",
         "steps": [{"skill_id": 9, "course_id": 1, "skill_title": "Quadratic Functions", "node_type": "concept",
                    "rationale": "...", "focus_hint": "..."}]}'''),
      );
      expect(p.id, 3);
      expect(p.suggestedTier, Tier.medium);
      expect(p.contextBucket, ContextBucket.mid);
      expect(p.createdAt, DateTime.utc(2026, 10, 5, 3, 31));
      expect(p.steps, hasLength(1));
      final s = p.steps.single;
      expect(s.skillId, 9);
      expect(s.courseId, 1);
      expect(s.skillTitle, 'Quadratic Functions');
      expect(s.nodeType, NodeType.concept);
      expect(s.rationale, '...');
      expect(s.focusHint, '...');
    });

    test('SearchPlan', () {
      final s = SearchPlan.fromJson(
        obj('''
        {"id": 2, "skill_id": 5, "gap": "Could not explain the solution when the discriminant is negative",
         "queries": ["Discriminant negative complex roots", "quadratic negative discriminant complex roots"],
         "items": [{"title": "...", "url": "https://...", "snippet": "...", "reason": "..."}],
         "created_at": "2026-10-05T03:40:00Z"}'''),
      );
      expect(s.id, 2);
      expect(s.skillId, 5);
      expect(s.gap, 'Could not explain the solution when the discriminant is negative');
      expect(s.queries, hasLength(2));
      expect(s.items.single.url, 'https://...');
      expect(s.items.single.title, '...');
      expect(s.items.single.snippet, '...');
      expect(s.items.single.reason, '...');
      expect(s.createdAt, DateTime.utc(2026, 10, 5, 3, 40));
    });

    test('Graph with all five edge kinds', () {
      final g = Graph.fromJson(
        obj(
          '''
        {"nodes": [{"id": "skill:5", "kind": "skill", "title": "Quadratic Equations", "status": "mastered",
                    "node_type": "concept", "course_id": 1},
                   {"id": "principle:7", "kind": "principle", "title": "State the range of the solution first",
                    "status": null, "node_type": null, "course_id": null}],
         "edges": [{"source": "skill:2", "target": "skill:5", "kind": "contains", "reason": null},
                   {"source": "skill:5", "target": "skill:10", "kind": "requires", "reason": "..."},
                   {"source": "principle:7", "target": "skill:5", "kind": "origin", "reason": null},
                   {"source": "principle:9", "target": "principle:7", "kind": "related", "reason": "..."},
                   {"source": "principle:9", "target": "principle:4", "kind": "contradicts", "reason": "..."}]}''',
        ),
      );
      expect(g.nodes, hasLength(2));
      final skill = g.nodes.first;
      expect(skill.isSkill, isTrue);
      expect(skill.entityId, 5);
      expect(skill.status, SkillStatus.mastered);
      expect(skill.nodeType, NodeType.concept);
      expect(skill.courseId, 1);
      final principle = g.nodes.last;
      expect(principle.isPrincipleNode, isTrue);
      expect(principle.entityId, 7);
      expect(principle.status, isNull);
      expect(principle.nodeType, isNull);
      expect(principle.courseId, isNull);
      expect(g.edges.map((e) => e.kind), GraphEdgeKind.values);
      expect(g.edges[1].reason, '...');
      expect(g.edges[2].source, 'principle:7');
      expect(g.edges[2].target, 'skill:5');
    });
  });

  group('Section 3 — response bodies', () {
    test('clarify (1)', () {
      final c = ClarifyResult.fromJson(
        obj(
          '''
        {"needs_clarification": true, "questions": ["Do you mean high-school probability and statistics, or university-level statistics?"]}''',
        ),
      );
      expect(c.needsClarification, isTrue);
      expect(c.questions, hasLength(1));
      final none = ClarifyResult.fromJson(obj('{"needs_clarification": false, "questions": []}'));
      expect(none.needsClarification, isFalse);
      expect(none.questions, isEmpty);
    });

    test('generate / course map (2, 4)', () {
      final m = CourseMap.fromJson(
        obj(
          '''
        {"course": {"id": 1, "topic": "Math", "source_course": "High School Mathematics Curriculum (Ministry of Education)",
                    "source_url": "https://example.org/1", "created_at": "2026-10-05T03:00:00Z"},
         "nodes": [{"id": 1, "course_id": 1, "slug": "high-school-math", "title": "High School Math",
                    "description": "d", "status": "available", "node_type": "concept", "mastery_score": null},
                   {"id": 2, "course_id": 1, "slug": "algebra", "title": "Algebra",
                    "description": "d", "status": "locked", "node_type": "concept", "mastery_score": null}],
         "edges": [{"from_id": 1, "to_id": 2, "kind": "contains", "is_primary": true, "reason": null}]}''',
        ),
      );
      expect(m.course.hasSource, isTrue);
      expect(m.nodes, hasLength(2));
      expect(m.edges, hasLength(1));
      expect(m.nodeById(2)!.title, 'Algebra');
      expect(m.nodeById(99), isNull);
    });

    test('recommendation (6)', () {
      final r = Recommendation.fromJson(
        obj(
          '''
        {"context_bucket": "mid", "suggested_tier": "medium", "skill_tiers": {"1": "easy", "5": "medium"}}''',
        ),
      );
      expect(r.contextBucket, ContextBucket.mid);
      expect(r.suggestedTier, Tier.medium);
      expect(r.skillTiers, {1: Tier.easy, 5: Tier.medium});
      expect(r.tierOf(5), Tier.medium);
      expect(r.tierOf(9), isNull);
    });

    test('start audit (7)', () {
      final a = AuditStart.fromJson(
        obj('''
        {"session": {"id": 31, "skill_id": 5, "node_position": "leaf", "status": "active", "score": null,
                     "gaps": [], "comment": null,
                     "turns": [{"role": "auditor", "content": "q"}]},
         "opening_question": "q"}'''),
      );
      expect(a.session.id, 31);
      expect(a.openingQuestion, 'q');
      expect(a.session.turns.single.isUser, isFalse);
    });

    test('check-in (12)', () {
      final r = CheckInResult.fromJson(
        obj('''
        {"checkin": {"date": "2026-10-05", "sleep_hours": 6, "exercised": false, "diet_note": "lunch: ramen",
                     "focus": null, "stress": null, "transcript": "...", "source": "voice"},
         "missing_fields": ["focus", "stress"]}'''),
      );
      expect(r.checkin.sleepHours, 6);
      expect(r.missingFields, [CheckInField.focus, CheckInField.stress]);
      expect(r.missingFields.map((f) => f.value), ['focus', 'stress']);
    });

    test('manual check-in with a fractional sleep time', () {
      final r = CheckInResult.fromJson(
        obj('''
        {"checkin": {"date": "2026-10-05", "sleep_hours": 6.5, "exercised": null, "diet_note": null,
                     "focus": 3, "stress": 2, "transcript": null, "source": "manual"},
         "missing_fields": ["exercised", "diet_note"]}'''),
      );
      expect(r.checkin.sleepHours, 6.5);
      expect(r.checkin.source, CheckInSource.manual);
      expect(r.checkin.transcript, isNull);
      expect(r.missingFields, [CheckInField.exercised, CheckInField.dietNote]);
    });

    test('GenerateRequest.toJson (2)', () {
      const request = GenerateRequest(topic: 'Math');
      expect(request.toJson(), {
        'topic': 'Math',
        'node_count': 12,
        'max_depth': 4,
        'difficulty': 'standard',
        'search_syllabus': true,
      });
      expect(
        const GenerateRequest(
          topic: 'x',
          nodeCount: 30,
          maxDepth: 6,
          difficulty: Difficulty.deep,
          searchSyllabus: false,
        ).toJson(),
        {
          'topic': 'x',
          'node_count': 30,
          'max_depth': 6,
          'difficulty': 'deep',
          'search_syllabus': false,
        },
      );
    });
  });

  group('parsing errors', () {
    test('an unknown enum value throws a FormatException', () {
      expect(() => SkillStatus.fromJson('weird'), throwsFormatException);
      expect(() => GraphEdgeKind.fromJson(null), throwsFormatException);
    });

    test('a missing or mistyped field throws a FormatException', () {
      expect(() => Course.fromJson({'id': 'x'}), throwsFormatException);
      expect(() => ClarifyResult.fromJson({'questions': []}), throwsFormatException);
    });
  });

  group('wire values', () {
    test('every enum value round-trips through its wire string', () {
      for (final v in SkillStatus.values) {
        expect(SkillStatus.fromJson(v.value), v);
      }
      for (final v in NodePosition.values) {
        expect(NodePosition.fromJson(v.value), v);
      }
      for (final v in AuditStatus.values) {
        expect(AuditStatus.fromJson(v.value), v);
      }
      for (final v in Tier.values) {
        expect(Tier.fromJson(v.value), v);
      }
      for (final v in Difficulty.values) {
        expect(Difficulty.fromJson(v.value), v);
      }
      for (final v in CheckInField.values) {
        expect(CheckInField.fromJson(v.value), v);
      }
      expect(CheckInField.values.map((f) => f.value), [
        'sleep_hours',
        'exercised',
        'diet_note',
        'focus',
        'stress',
      ]);
    });
  });

  group('composeTopic (client rule of endpoint 1)', () {
    test('appends one Q/A pair per answered question', () {
      expect(
        composeTopic('Statistics', {
          'Do you mean high-school or university statistics?': 'University level',
        }),
        'Statistics\n\nQ: Do you mean high-school or university statistics?\nA: University level',
      );
    });

    test('omits unanswered questions and returns the topic alone without answers', () {
      expect(composeTopic('  Statistics  ', {'Which?': '   '}), 'Statistics');
      expect(composeTopic('Statistics', {}), 'Statistics');
      expect(
        composeTopic('t', {'q1': 'a1', 'q2': '', 'q3': 'a3'}),
        't\n\nQ: q1\nA: a1\nQ: q3\nA: a3',
      );
    });
  });

  group('time helpers', () {
    test('parseUtc handles Z, +00:00, other offsets and a missing offset', () {
      expect(parseUtc('2026-10-05T03:12:45Z'), DateTime.utc(2026, 10, 5, 3, 12, 45));
      expect(parseUtc('2026-10-05T03:12:45+00:00'), DateTime.utc(2026, 10, 5, 3, 12, 45));
      expect(parseUtc('2026-10-05T12:12:45+09:00'), DateTime.utc(2026, 10, 5, 3, 12, 45));
      final naive = parseUtc('2026-10-05T03:12:45');
      expect(naive.isUtc, isTrue);
      expect(naive, DateTime.utc(2026, 10, 5, 3, 12, 45));
      expect(parseUtc('2026-10-05T03:12:45.123456+00:00').isUtc, isTrue);
    });

    test('formatKst shows Korea Standard Time (UTC+9)', () {
      final t = DateTime.utc(2026, 10, 5, 3, 12, 45);
      expect(toKst(t).hour, 12);
      expect(formatKst(t), '2026.10.05 12:12');
      expect(formatKst(t, pattern: 'MMM d, y HH:mm'), 'Oct 5, 2026 12:12');
      expect(formatKstDate(t), '2026-10-05');
    });

    test('formatKst rolls over to the next day after 15:00 UTC', () {
      final t = DateTime.utc(2026, 10, 5, 16, 0);
      expect(formatKstDate(t), '2026-10-06');
      expect(formatKst(t), '2026.10.06 01:00');
      expect(formatKstDate(DateTime.utc(2026, 10, 5, 14, 59)), '2026-10-05');
    });

    test('formatLocal shows English dates and 24 h times in local time', () {
      final t = DateTime(2026, 10, 2, 11, 4).toUtc();
      expect(formatLocal(t), 'Oct 2, 2026');
      expect(formatLocal(t, style: DateStyle.time), '11:04');
      expect(formatLocal(DateTime(2026, 10, 2, 23, 59).toUtc(), style: DateStyle.time), '23:59');
    });

    test('formatKst accepts a local DateTime too', () {
      final local = DateTime.utc(2026, 1, 1, 0, 0).toLocal();
      expect(formatKst(local), '2026.01.01 09:00');
    });
  });
}
