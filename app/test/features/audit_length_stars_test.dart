// The audit length preference (contract #53) and the stars a verdict is shown
// as: the setting in the ◎ menu, the star row, the verdict card and the node's
// best stars.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/features/audit/verdict_card.dart';
import 'package:self_infinity/features/chat/home_scene.dart';
import 'package:self_infinity/features/skill/node_card.dart';
import 'package:self_infinity/l10n/l10n.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/theme/app_theme.dart';
import 'package:self_infinity/widgets/widgets.dart';

import '../support/scene_helpers.dart';

Future<void> pumpCard(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

Finder key(String k) => find.byKey(Key(k));

final String longAnswer = 'x' * 200;

/// Audits node 6 to a pass at the length the account has chosen.
Future<VerdictResult> pass(FakeApiClient api, String length, {int skillId = 6}) async {
  await api.setAuditLength(length);
  final start = await api.startAudit(skillId, restart: true);
  await api.submitTurn(start.session.id, 'a first try');
  return await api.submitTurn(start.session.id, longAnswer) as VerdictResult;
}

void main() {
  late FakeApiClient api;

  setUp(() async {
    api = await seededFakeApi();
  });

  group('the star row', () {
    testWidgets('fills as many stars as were earned, out of three', (tester) async {
      for (final n in [0, 1, 2, 3]) {
        await pumpCard(tester, StarRow(stars: n));
        expect(key('stars-$n'), findsOneWidget);
        expect(find.byIcon(Icons.star_rounded), findsNWidgets(n));
        expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(3 - n));
      }
    });

    testWidgets('never shows more than three or fewer than none', (tester) async {
      await pumpCard(tester, const StarRow(stars: 9));
      expect(key('stars-3'), findsOneWidget);
      await pumpCard(tester, const StarRow(stars: -1));
      expect(key('stars-0'), findsOneWidget);
    });
  });

  group('the models', () {
    test('an audit without stars is 2 for a pass and 0 for anything else', () {
      Map<String, dynamic> summary(String status, [int? stars]) => {
        'id': 1,
        'skill_id': 1,
        'skill_title': 'T',
        'status': status,
        'created_at': '2026-11-07T00:00:00Z',
        'stars': ?stars,
      };
      expect(AuditSummary.fromJson(summary('passed')).stars, 2);
      expect(AuditSummary.fromJson(summary('failed')).stars, 0);
      expect(AuditSummary.fromJson(summary('passed', 3)).stars, 3);
      expect(
        VerdictResult.fromJson({'passed': true, 'score': 90}).stars,
        2,
      );
      expect(VerdictResult.fromJson({'passed': false, 'score': 10}).stars, 0);
      expect(VerdictResult.fromJson({'passed': true, 'score': 90, 'stars': 1}).stars, 1);
    });

    test('a node has best stars only when the server sent them', () {
      final base = {
        'id': 1,
        'course_id': 1,
        'slug': 's',
        'title': 'T',
        'description': '',
        'status': 'mastered',
        'node_type': 'concept',
      };
      expect(SkillNode.fromJson(base).bestStars, isNull);
      expect(SkillNode.fromJson({...base, 'best_stars': 3}).bestStars, 3);
    });
  });

  group('the verdict card', () {
    for (final (stars, passed) in [(1, true), (2, true), (3, true), (0, false)]) {
      testWidgets('shows $stars star${stars == 1 ? '' : 's'}', (tester) async {
        await pumpCard(
          tester,
          VerdictCard(verdict: VerdictResult(passed: passed, score: 80, stars: stars), onBack: () {}),
        );
        expect(
          find.descendant(of: key('verdict-stars'), matching: key('stars-$stars')),
          findsOneWidget,
        );
        expect(find.text('Failed'), findsNothing);
      });
    }
  });

  group('the fake API', () {
    test('a pass is worth 1, 2 or 3 stars by the length and the node keeps its best', () async {
      expect(await api.getAuditLength(), 'standard');
      expect((await pass(api, 'short')).stars, 1);
      expect((await api.getCourseMap(1)).nodes.firstWhere((n) => n.id == 6).bestStars, 1);
      expect((await pass(api, 'thorough')).stars, 3);
      expect((await pass(api, 'short')).stars, 1);
      expect((await api.getCourseMap(1)).nodes.firstWhere((n) => n.id == 6).bestStars, 3);
      expect((await api.getSkillOverview(6)).skill.bestStars, 3);
      final audits = (await api.getSkillOverview(6)).audits;
      expect(audits.map((a) => a.stars).toList()..sort(), [1, 1, 3]);
    });

    test('standard is two stars; a fail is none', () async {
      expect((await pass(api, 'standard')).stars, 2);
      await api.setAuditLength('short');
      final start = await api.startAudit(6, restart: true);
      expect(start.session.length, 'short');
      expect(start.session.points, hasLength(1));
      await api.submitTurn(start.session.id, 'a first try');
      final fail = await api.submitTurn(start.session.id, 'no') as VerdictResult;
      expect(fail.passed, isFalse);
      expect(fail.stars, 0);
    });

    test('an unknown length is a 400', () async {
      await expectLater(api.setAuditLength('endless'), throwsA(isA<Object>()));
      expect(await api.getAuditLength(), 'standard');
    });
  });

  group('the node card', () {
    SkillOverview overview({int? bestStars}) => SkillOverview(
      skill: SkillNode(
        id: 6,
        courseId: 1,
        slug: 's',
        title: 'Discriminant',
        description: '',
        status: SkillStatus.mastered,
        nodeType: NodeType.concept,
        bestStars: bestStars,
      ),
      course: Course(id: 1, topic: 'Math', createdAt: DateTime(2026)),
    );

    testWidgets('shows its best stars when it has any', (tester) async {
      await pumpCard(
        tester,
        SkillNodeCard(overview: overview(bestStars: 3), boss: false, chips: const [], lessons: const []),
      );
      expect(find.descendant(of: key('skill-best-stars'), matching: key('stars-3')), findsOneWidget);
    });

    testWidgets('and nothing when it has none', (tester) async {
      await pumpCard(
        tester,
        SkillNodeCard(overview: overview(), boss: false, chips: const [], lessons: const []),
      );
      expect(key('skill-best-stars'), findsNothing);
    });
  });

  group('the setting', () {
    testWidgets('Audit length in the ◎ menu: choosing Thorough saves it, and it shows chosen next time', (
      tester,
    ) async {
      await pumpScene(tester, const HomeScene(), api: api);
      await tester.tap(key('settings-button'));
      await tester.pumpAndSettle();
      await tester.tap(key('settings-audit-length'));
      await tester.pumpAndSettle();

      for (final id in ['short', 'standard', 'thorough']) {
        expect(key('audit-length-$id'), findsOneWidget);
      }
      expect(
        find.descendant(of: key('audit-length-standard'), matching: key('audit-length-selected')),
        findsOneWidget,
      );
      await tester.tap(key('audit-length-thorough'));
      await tester.pumpAndSettle();

      expect(await api.getAuditLength(), 'thorough');
      expect(key('audit-length-dialog'), findsNothing);

      await tester.tap(key('settings-button'));
      await tester.pumpAndSettle();
      await tester.tap(key('settings-audit-length'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: key('audit-length-thorough'), matching: key('audit-length-selected')),
        findsOneWidget,
      );
    });
  });
}
