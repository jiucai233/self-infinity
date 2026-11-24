// On a phone, Home and the audit are only a talk with 大肥鱼: her, her
// bubble, quick replies, the conversation and the input. Wide is unchanged.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/features/audit/audit_scene.dart';
import 'package:self_infinity/features/chat/home_scene.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/theme/tokens.dart';
import 'package:self_infinity/widgets/widgets.dart';

import '../support/scene_helpers.dart';

Finder key(String k) => find.byKey(Key(k));

Finder inStage(Finder f) => find.descendant(of: key('stage-panel'), matching: f);

void main() {
  group('Home on a phone', () {
    testWidgets('her bubble and the input over the sky; no figure on the tree', (tester) async {
      await pumpScene(tester, const HomeScene(), api: await seededFakeApi(), size: phoneScreen);
      expect(find.descendant(of: key('night-panel'), matching: find.byType(Avatar)), findsNothing);
      // The greeting is her line, in her bubble.
      expect(
        find.descendant(of: key('greeting-bubble'), matching: key('greeting')),
        findsOneWidget,
      );
      expect(find.text('Continue with “High School Math”?'), findsOneWidget);
      expect(find.text('I want to learn…'), findsOneWidget);
      // No cards, no quick replies.
      expect(key('suggestions'), findsNothing);
      // The history button stays, quiet.
      final history = tester.widget<Icon>(
        find.descendant(of: key('open-right-drawer'), matching: find.byType(Icon)),
      );
      expect(history.color, AppColors.textTertiary);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a chat is the thread of this visit, her small figure on top', (tester) async {
      final api = await seededFakeApi();
      await api.sendChat('something said before');
      await pumpScene(tester, const HomeScene(), api: api, size: phoneScreen);
      await say(tester, 'Hello there');
      final thread = key('phone-thread');
      expect(thread, findsOneWidget);
      expect(
        tester.getBottomLeft(key('avatar-tap')).dy,
        lessThanOrEqualTo(tester.getTopLeft(thread).dy),
      );
      expect(find.descendant(of: thread, matching: find.text('Hello there')), findsOneWidget);
      expect(find.descendant(of: thread, matching: key('reply-bubble')), findsOneWidget);
      expect(
        tester.widget<Text>(key('bubble-text')).data,
        'Sure. What would you like to do today?',
      );
      // What was said before is in the drawer, not on the page.
      expect(find.text('something said before'), findsNothing);
      expect(key('last-said'), findsNothing);
      expect(key('greeting'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide: her bubble on the sky, then the big bubble in a chat', (tester) async {
      await pumpScene(tester, const HomeScene(), api: await seededFakeApi());
      expect(key('greeting-bubble'), findsOneWidget);
      await say(tester, 'Hello there');
      expect(key('phone-thread'), findsNothing);
      expect(key('reply-bubble'), findsOneWidget);
    });
  });

  group('the audit on a phone', () {
    late FakeApiClient api;

    setUp(() async {
      api = await seededFakeApi();
      api.debugSetStatus(1, SkillStatus.available);
    });

    testWidgets('no name, tagline or divider: she sits small on top of the bubbles', (
      tester,
    ) async {
      await pumpScene(tester, const AuditScene(skillId: 1), api: api, size: phoneScreen);
      expect(key('audit-speaker'), findsOneWidget);
      expect(find.text('Auditor'), findsNothing);
      expect(find.text('Learns from you and asks where it loses the thread'), findsNothing);
      expect(inStage(find.byType(Divider)), findsNothing);
      expect(find.text('In progress'), findsNothing);
      // Her question is her bubble.
      expect(
        find.ancestor(of: key('audit-bubble-text'), matching: find.byType(ThreadBubble)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the verdict is her message: her bubble shape, no edge, no shadow', (
      tester,
    ) async {
      await pumpScene(tester, const AuditScene(skillId: 1), api: api, size: phoneScreen);
      await say(tester, shortAnswer);
      await say(tester, shortAnswer);
      final card = tester.widget<Container>(key('audit-verdict'));
      final box = card.decoration! as BoxDecoration;
      expect(box.color, AppColors.surfaceHigh);
      expect(box.borderRadius, AppRadius.herBubbleBorder);
      expect(box.border, isNull);
      expect(box.boxShadow, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide: the header names her (no tagline under the name), the card is paper', (tester) async {
      await pumpScene(tester, const AuditScene(skillId: 1), api: api);
      expect(find.text('Auditor'), findsWidgets);
      expect(find.text('Learns from you and asks where it loses the thread'), findsNothing);
      expect(find.byType(ThreadBubble), findsNothing);
      await say(tester, shortAnswer);
      await say(tester, shortAnswer);
      final box = tester.widget<Container>(key('audit-verdict')).decoration! as BoxDecoration;
      expect(box.color, AppColors.surface);
      expect(box.boxShadow, isNotNull);
    });
  });
}
