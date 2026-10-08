// Contract Section 6 (life as a game): Profile, JournalEntry, the reflection
// flag of a suggestion, the seven prompt windows and the boss rule.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/graph_utils.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/api/reflection_prompts.dart';

Json obj(String source) => jsonDecode(source) as Json;

void main() {
  group('Profile', () {
    test('parses the contract example', () {
      final p = Profile.fromJson(
        obj('''
        {"identity": "I am the type of person who explains things from first principles.",
         "vision": "A clear mind", "anti_vision": "Drifting", "rules": ["No phone before the first audit", "Sleep by 11"],
         "updated_at": "2026-10-05T03:00:00Z"}'''),
      );
      expect(p.identity, startsWith('I am the type of person who'));
      expect(p.vision, 'A clear mind');
      expect(p.antiVision, 'Drifting');
      expect(p.rules, ['No phone before the first audit', 'Sleep by 11']);
      expect(p.updatedAt, DateTime.utc(2026, 10, 5, 3));
      expect(p.isEmpty, isFalse);
    });

    test('a fresh database: empty strings, no rules, no update time', () {
      final p = Profile.fromJson(
        obj('{"identity": "", "vision": "", "anti_vision": "", "rules": [], "updated_at": null}'),
      );
      expect(p.isEmpty, isTrue);
      expect(p.updatedAt, isNull);
    });

    test('limits of the contract', () {
      expect(Profile.maxTextLength, 280);
      expect(Profile.maxRules, 5);
      expect(Profile.maxRuleLength, 120);
    });
  });

  test('JournalEntry parses the contract example', () {
    final e = JournalEntry.fromJson(
      obj('''
      {"id": 4, "prompt": "What are you putting off right now?", "answer": "The taxes",
       "created_at": "2026-10-05T02:10:00Z"}'''),
    );
    expect(e.id, 4);
    expect(e.prompt, 'What are you putting off right now?');
    expect(e.answer, 'The taxes');
    expect(e.createdAt, DateTime.utc(2026, 10, 5, 2, 10));
  });

  group('ChatSuggestion.reflection', () {
    test('true for a reflection item', () {
      final s = ChatSuggestion.fromJson(
        obj('''
        {"label": "What are you putting off right now?", "message": "", "skill_id": null,
         "reflection": true}'''),
      );
      expect(s.reflection, isTrue);
      expect(s.message, '');
      expect(s.skillId, isNull);
    });

    test('false when the flag is false or missing (an older server)', () {
      expect(
        ChatSuggestion.fromJson(
          obj('{"label": "a", "message": "b", "skill_id": null, "reflection": false}'),
        ).reflection,
        isFalse,
      );
      expect(
        ChatSuggestion.fromJson(obj('{"label": "a", "message": "b", "skill_id": 3}')).reflection,
        isFalse,
      );
    });
  });

  group('the seven reflection windows (KST)', () {
    int at(int h, int m) => h * 60 + m;

    test('there are seven distinct prompts', () {
      expect(reflectionPrompts, hasLength(7));
      expect(reflectionPrompts.toSet(), hasLength(7));
    });

    test('boundaries from the contract table', () {
      final table = <(int, int, String)>[
        (3, 0, 'Who are you becoming this week? One sentence.'),
        (10, 59, 'Who are you becoming this week? One sentence.'),
        (11, 0, 'What are you putting off right now?'),
        (13, 29, 'What are you putting off right now?'),
        (13, 30, 'Looking at the last two hours, what were you really after?'),
        (15, 14, 'Looking at the last two hours, what were you really after?'),
        (15, 15, 'Is today pulling you toward your vision or your anti-vision?'),
        (16, 59, 'Is today pulling you toward your vision or your anti-vision?'),
        (17, 0, "What matters most that you've been ignoring?"),
        (19, 29, "What matters most that you've been ignoring?"),
        (19, 30, 'Today, were you guarding an image of yourself or going after what you want?'),
        (20, 59, 'Today, were you guarding an image of yourself or going after what you want?'),
        (21, 0, 'When did you feel most alive today, and when least?'),
        (23, 59, 'When did you feel most alive today, and when least?'),
        (0, 0, 'When did you feel most alive today, and when least?'),
        (2, 59, 'When did you feel most alive today, and when least?'),
      ];
      for (final (h, m, prompt) in table) {
        expect(reflectionPromptAt(at(h, m)), prompt, reason: '$h:$m');
      }
    });
  });

  group('bosses are the root and the branch nodes', () {
    // 1 root → 2, 3 (branch 2 → 4, 5; 3 is a leaf).
    SkillEdge contains(int from, int to) =>
        SkillEdge(fromId: from, toId: to, kind: SkillEdgeKind.contains, isPrimary: true);
    SkillNode node(int id) => SkillNode(
      id: id,
      courseId: 1,
      slug: 's$id',
      title: 'N$id',
      description: '',
      status: SkillStatus.available,
      nodeType: NodeType.concept,
    );
    final edges = [contains(1, 2), contains(1, 3), contains(2, 4), contains(2, 5)];

    test('isBoss: root and branch yes, leaf no', () {
      expect(isBoss(node(1), edges), isTrue);
      expect(isBoss(node(2), edges), isTrue);
      expect(isBoss(node(3), edges), isFalse);
      expect(isBoss(node(4), edges), isFalse);
    });

    test('a category not broken down yet is a boss without children', () {
      expect(isBoss(node(3).copyWith(unexpanded: true), edges), isTrue);
    });

    test('bossIds picks them out of a node list', () {
      expect(bossIds([for (var i = 1; i <= 5; i++) node(i)], edges), {1, 2});
    });

    test('a lone root counts as a boss', () {
      expect(isBoss(node(9), const []), isTrue);
    });
  });
}
