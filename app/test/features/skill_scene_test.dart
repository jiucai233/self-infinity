// Scene 4: the node overview — on a wide screen the node card (kicker, title,
// status chip, Best / Attempts / Lessons, the audit history, the ink Take it
// on), the contents card (one row per material) and the avatar asking Ready
// to try?; on a phone her line first, the node as a quiet block with Details,
// Take it on pinned above the input; questions to the chat.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/app/app_state.dart';
import 'package:self_infinity/app/router.dart';
import 'package:self_infinity/features/skill/skill_scene.dart';
import 'package:self_infinity/testing/fake_voice.dart';
import 'package:self_infinity/testing/test_app.dart';
import 'package:self_infinity/theme/tokens.dart';
import 'package:self_infinity/widgets/widgets.dart';

import '../support/scene_helpers.dart';

Future<void> pumpSkill(
  WidgetTester tester,
  FakeApiClient api,
  int id, {
  Size size = wideScreen,
  FakeVoiceService? voice,
  AppState? state,
}) => pumpScene(
  tester,
  SkillScene(skillId: id),
  api: api,
  size: size,
  voice: voice,
  state: state,
);

Finder get contents => find.byKey(const Key('skill-contents'));

Avatar avatar(WidgetTester tester) => tester.widget<Avatar>(find.byType(Avatar));

/// What she says (the speaker's name above the bubble is not part of it).
String bubble(WidgetTester tester) =>
    textsIn(tester, find.byKey(const Key('skill-bubble'))).skip(1).join();

/// Scrolls [finder] into view (the node card comes first) and taps it.
Future<void> tapShown(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The right panel; the node page has none.
Finder get panel => find.byKey(const Key('history-panel'));

void main() {
  late FakeApiClient api;

  setUp(() async {
    api = await seededFakeApi();
  });

  group('the ⋯ menu', () {
    testWidgets('deletes the course after asking, then goes to the life tree', (tester) async {
      await pumpSkill(tester, api, 5);
      await tester.tap(find.byKey(const Key('skill-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('skill-delete-course')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('course-delete-dialog')), findsOneWidget);
      expect(find.text('Delete “High School Math”?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('course-delete-confirm')));
      await tester.pumpAndSettle();
      expect(await api.listCourses(), isEmpty);
      expect(find.text('route:/map'), findsOneWidget);
    });
  });

  group('the page', () {
    testWidgets('the node card shows the name in the headline style, not node: …', (
      tester,
    ) async {
      await pumpSkill(tester, api, 5);
      final title = tester.widget<Text>(find.byKey(const Key('skill-title')));
      expect(title.data, 'Quadratic Equations');
      expect(title.style!.fontSize, 24);
      expect(title.maxLines, 2); // it may wrap on a phone
      expect(find.textContaining('node:'), findsNothing);
      // Not in the title bar too.
      expect(find.byKey(const Key('stage-title')), findsNothing);
    });

    testWidgets('a status chip next to it: Locked / Ready / Cleared / Failed', (tester) async {
      await pumpSkill(tester, api, 5);
      expect(find.text('Locked'), findsOneWidget);
      await pumpSkill(tester, api, 6);
      expect(find.text('Ready'), findsOneWidget);
      await passAudit(api, 6);
      await pumpSkill(tester, api, 6);
      expect(find.text('Cleared'), findsOneWidget);
      await failAudit(api, 7); // the next node of the order
      await pumpSkill(tester, api, 7);
      final chip = find.descendant(
        of: find.byKey(const Key('skill-chips')),
        matching: find.text('Failed'),
      );
      expect(chip, findsOneWidget);
      // The chips have their own line under the name.
      expect(
        tester.getTopLeft(chip).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.byKey(const Key('skill-title'))).dy),
      );
    });

    testWidgets('no badges, no day/night switch; one ink button, on the card, none in the bubble', (
      tester,
    ) async {
      await pumpSkill(tester, api, 6);
      expect(find.byType(SegmentedButton<String>), findsNothing);
      expect(find.byKey(const Key('mode-toggle')), findsNothing);
      expect(find.text('Day'), findsNothing);
      expect(find.text('Night'), findsNothing);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('skill-node-card')), matching: find.byType(FilledButton)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('skill-bubble')), matching: find.byType(ButtonStyleButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: find.byKey(const Key('skill-bubble')), matching: find.byType(IconButton)),
        findsNothing,
      );
      expect(find.text('Leaf'), findsNothing);
    });

    testWidgets('← goes back to scene 2', (tester) async {
      await pumpSkill(tester, api, 6);
      await tester.tap(find.byKey(const Key('back-map')));
      await tester.pumpAndSettle();
      expect(find.text('route:/map'), findsOneWidget);
    });

    testWidgets('a missing node shows the error with a retry', (tester) async {
      await pumpSkill(tester, api, 999);
      expect(find.text("We couldn't find that."), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('the input asks the chat: no ⊕, no ∿, a mic that types', (tester) async {
      await pumpSkill(tester, api, 6);
      expect(find.text('Ask about this node…'), findsOneWidget);
      expect(find.byKey(const Key('upload')), findsNothing);
      expect(find.byKey(const Key('voice-mode')), findsNothing);
      expect(find.byKey(const Key('dictation-button')), findsOneWidget);
    });
  });

  group('contents card', () {
    testWidgets('a white card with a hairline, radius 16: description and the course source', (
      tester,
    ) async {
      await pumpSkill(tester, api, 5);
      final decoration = tester.widget<DecoratedBox>(contents).decoration as BoxDecoration;
      expect(decoration.color, AppColors.surface);
      expect(decoration.borderRadius, BorderRadius.circular(16));
      expect((decoration.border! as Border).top.color, AppColors.outline);
      expect(find.text('contents'), findsNothing);
      expect(find.text('Learn first'), findsOneWidget);
      expect(find.byKey(const Key('skill-description')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('skill-description'))).data,
        'How to solve equations of the form ax²+bx+c=0 and what the roots mean.',
      );
      expect(find.text('Resources'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('course-source')),
                matching: find.byKey(const Key('material-title')),
              ),
            )
            .data,
        'Source: High School Mathematics Curriculum (Ministry of Education)',
      );
    });

    testWidgets('one row per material: a letter badge, the title and the site', (tester) async {
      await api.createSearchPlan(5, gap: 'what the discriminant means');
      final plan = (await api.getSkillOverview(5)).materials.single;
      await pumpSkill(tester, api, 5);
      for (var i = 0; i < 3; i++) {
        final item = plan.items[i];
        final row = find.byKey(ValueKey('link-${item.url}'));
        expect(row, findsOneWidget);
        final title = tester.widget<Text>(
          find.descendant(of: row, matching: find.byKey(const Key('material-title'))),
        );
        expect(title.data, item.title);
        expect(title.maxLines, 1);
        expect(title.overflow, TextOverflow.ellipsis);
        final domain = tester.widget<Text>(
          find.descendant(of: row, matching: find.byKey(const Key('material-domain'))),
        );
        expect(domain.data, 'example.org');
        expect(domain.style!.color, AppColors.textSecondary);
        // The raw URL is not shown.
        expect(find.text(item.url), findsNothing);
        expect(
          find.descendant(of: row, matching: find.byKey(const Key('material-badge'))),
          findsOneWidget,
        );
      }
      // Nothing for another node.
      await pumpSkill(tester, api, 6);
      expect(find.byKey(const ValueKey('link-https://example.org/1')), findsNothing);
    });

    testWidgets('the badge shows the first letter; the site has no www.', (tester) async {
      await pumpScene(
        tester,
        SkillScene(skillId: 5),
        api: _MaterialsApi(api, const [
          SearchItem(
            title: 'Khan Academy',
            url: 'https://www.khanacademy.org/x',
            snippet: '',
            reason: '',
          ),
          SearchItem(
            title: '“Special” derivative',
            url: 'https://ko.wikipedia.org/wiki/y',
            snippet: '',
            reason: '',
          ),
          SearchItem(title: '', url: 'https://youtu.be/z', snippet: '', reason: ''),
        ]),
      );
      String badge(String url) => textsIn(
        tester,
        find.descendant(
          of: find.byKey(ValueKey('link-$url')),
          matching: find.byKey(const Key('material-badge')),
        ),
      ).single;
      expect(badge('https://www.khanacademy.org/x'), 'K');
      expect(badge('https://ko.wikipedia.org/wiki/y'), 'S');
      expect(
        textsIn(tester, find.byKey(const ValueKey('link-https://www.khanacademy.org/x'))),
        containsAll(['Khan Academy', 'khanacademy.org']),
      );
      // Without a title the site stands in for it.
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('link-https://youtu.be/z')),
                matching: find.byKey(const Key('material-title')),
              ),
            )
            .data,
        'youtu.be',
      );
      expect(firstLetterOf('  “Functions”'), 'F');
      expect(firstLetterOf('...'), '·');
    });

    testWidgets('the whole row is tappable: it opens the link', (tester) async {
      final launched = _recordLaunches(tester);
      await api.createSearchPlan(5, gap: 'what the discriminant means');
      await pumpSkill(tester, api, 5);
      final row = find.byKey(const ValueKey('link-https://example.org/1'));
      expect(find.descendant(of: row, matching: find.byType(InkWell)), findsOneWidget);
      // Tap on the domain line, not on the title: any part of the row works.
      await tapShown(
        tester,
        find.descendant(of: row, matching: find.byKey(const Key('material-domain'))),
      );
      expect(launched, ['https://example.org/1']);
      // Tapping the badge works as well.
      await tapShown(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('link-https://example.org/2')),
          matching: find.byKey(const Key('material-badge')),
        ),
      );
      expect(launched, ['https://example.org/1', 'https://example.org/2']);
    });

    testWidgets('the same URL from two searches is listed once', (tester) async {
      await api.createSearchPlan(5, gap: 'one');
      await api.createSearchPlan(5, gap: 'two');
      await pumpSkill(tester, api, 5);
      expect(find.byKey(const ValueKey('link-https://example.org/1')), findsOneWidget);
    });

    testWidgets('more than four rows: a > pages through them', (tester) async {
      await pumpScene(tester, SkillScene(skillId: 5), api: _MaterialsApi(api, _links(9)));
      expect(find.byKey(const ValueKey('link-https://example.org/page/1')), findsOneWidget);
      expect(find.byKey(const ValueKey('link-https://example.org/page/4')), findsOneWidget);
      expect(find.byKey(const ValueKey('link-https://example.org/page/5')), findsNothing);
      expect(find.byKey(const Key('links-prev')), findsNothing);
      expect(find.text('1/3'), findsOneWidget);

      await tapShown(tester, find.byKey(const Key('links-next')));
      expect(find.byKey(const ValueKey('link-https://example.org/page/1')), findsNothing);
      expect(find.byKey(const ValueKey('link-https://example.org/page/5')), findsOneWidget);
      expect(find.byKey(const Key('links-prev')), findsOneWidget);

      await tapShown(tester, find.byKey(const Key('links-next')));
      expect(find.byKey(const ValueKey('link-https://example.org/page/9')), findsOneWidget);
      expect(find.byKey(const Key('links-next')), findsNothing);
      expect(find.text('3/3'), findsOneWidget);

      await tapShown(tester, find.byKey(const Key('links-prev')));
      expect(find.byKey(const ValueKey('link-https://example.org/page/5')), findsOneWidget);
    });

    testWidgets('four rows need no paging', (tester) async {
      await pumpScene(tester, SkillScene(skillId: 5), api: _MaterialsApi(api, _links(4)));
      expect(find.byKey(const Key('links-next')), findsNothing);
      expect(find.byKey(const ValueKey('link-https://example.org/page/4')), findsOneWidget);
    });

    testWidgets('a course made from uploaded files: the file names as a plain row, no link', (
      tester,
    ) async {
      final up = await api.uploadFile(filename: 'syllabus.md', bytes: [65, 66, 67]);
      await api.sendChat('I want to learn this', uploadIds: [up.id]);
      final course = (await api.listCourses()).first;
      final node = (await api.listSkills(courseId: course.id)).first;
      await pumpSkill(tester, api, node.id);
      final source = find.byKey(const Key('course-source'));
      expect(
        textsIn(tester, source),
        containsAll(['Source: syllabus.md', 'Uploaded course material']),
      );
      expect(find.descendant(of: source, matching: find.byType(InkWell)), findsNothing);
      expect(
        find.descendant(of: source, matching: find.byIcon(Icons.open_in_new_rounded)),
        findsNothing,
      );
    });

    testWidgets('a syllabus with a URL is a whole-row link with its site', (tester) async {
      await pumpSkill(tester, api, 5);
      final source = find.byKey(const Key('course-source'));
      expect(find.descendant(of: source, matching: find.byType(InkWell)), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.descendant(of: source, matching: find.byKey(const Key('material-domain'))),
            )
            .data,
        'example.org',
      );
      final launched = _recordLaunches(tester);
      await tapShown(
        tester,
        find.descendant(of: source, matching: find.byKey(const Key('material-title'))),
      );
      expect(launched, hasLength(1));
      expect(launched.single, startsWith('https://'));
    });

    testWidgets('a course without any source has no source line', (tester) async {
      final other = FakeApiClient(latency: Duration.zero);
      await other.generateCourse(const GenerateRequest(topic: 'Python'));
      await pumpSkill(tester, other, 1);
      expect(find.byKey(const Key('course-source')), findsNothing);
      expect(find.text('Resources'), findsNothing);
    });
  });

  group('the avatar', () {
    testWidgets('an available node: waving, Ready to try? and Take it on on the card', (tester) async {
      await pumpSkill(tester, api, 6);
      expect(bubble(tester), 'Ready to try?');
      expect(find.byKey(const Key('start-audit')), findsOneWidget);
      expect(avatar(tester).wave, isTrue);
      expect(avatar(tester).mood, AvatarMood.smile);
    });

    testWidgets('Take it on opens the audit (scene 4-1) without a mode', (tester) async {
      await pumpSkill(tester, api, 6);
      final button = find.byKey(const Key('start-audit'));
      expect(tester.widget<FilledButton>(button), isA<FilledButton>());
      expect(find.descendant(of: button, matching: find.text('Take it on')), findsOneWidget);
      await tapShown(tester, button);
      expect(find.text('route:/skill/6/audit'), findsOneWidget);
    });

    testWidgets('on a phone Take it on spans the page and opens the audit', (tester) async {
      await pumpSkill(tester, api, 6, size: phoneScreen);
      final button = find.byKey(const Key('start-audit'));
      final block = tester.getRect(find.byKey(const Key('skill-node-block')));
      expect(tester.getSize(button).width, greaterThan(block.width - 8));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('route:/skill/6/audit'), findsOneWidget);
    });

    testWidgets('a locked node: Still locked. Clear “the open node” first. and no →', (
      tester,
    ) async {
      await pumpSkill(tester, api, 5);
      // One node of the course is open at a time: that is the one to clear.
      expect(bubble(tester), 'Still locked. Clear “Discriminant” first.');
      expect(find.byKey(const Key('start-audit')), findsNothing);
      expect(avatar(tester).wave, isFalse);
    });

    testWidgets('a locked node names the open node of its own chapter', (tester) async {
      await pumpSkill(tester, api, 12); // Derivatives, in Calculus
      expect(bubble(tester), 'Still locked. Clear “Limits of Sequences” first.');
    });

    testWidgets('a mastered node can be challenged again', (tester) async {
      await passAudit(api, 6);
      await pumpSkill(tester, api, 6);
      expect(bubble(tester), 'Ready to try?');
      expect(find.byKey(const Key('start-audit')), findsOneWidget);
    });

    testWidgets('her name is above the bubble', (tester) async {
      await pumpSkill(tester, api, 6);
      expect(
        find.descendant(of: find.byKey(const Key('skill-bubble')), matching: find.text('Guide')),
        findsOneWidget,
      );
    });

    testWidgets('the bubble is the soft grey one', (tester) async {
      await pumpSkill(tester, api, 6);
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byKey(const Key('skill-bubble')),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.color, AppColors.surfaceHigh);
    });
  });

  group('the audit history lives only in the node card (wide screens)', () {
    testWidgets('no right panel; the card lists this node\u2019s audits', (tester) async {
      await failAudit(api, 6);
      await passAudit(api, 6);
      await pumpSkill(tester, api, 6);
      expect(panel, findsNothing);
      expect(find.byKey(const Key('collapse-right')), findsNothing);
      expect(find.byKey(const Key('audit-card')), findsNothing);
      expect(find.byKey(const Key('audit-score')), findsNWidgets(2));
    });

    testWidgets('a node with no audits shows none, and no panel either', (tester) async {
      await passAudit(api, 6);
      await pumpSkill(tester, api, 7);
      expect(panel, findsNothing);
      expect(find.byKey(const Key('audit-score')), findsNothing);
    });
  });

  group('asking about the node', () {
    testWidgets('the question goes to the chat; her answer replaces the line in the bubble', (
      tester,
    ) async {
      await pumpSkill(tester, api, 5);
      await say(tester, 'explain it simply');
      final history = await api.getChatHistory();
      expect(history.first.content, 'About “Quadratic Equations”: explain it simply');
      expect(bubble(tester), 'Sure. What would you like to do today?');
      expect(inputText(tester), '');
      expect(avatar(tester).wave, isFalse);
    });

    testWidgets(
      'while she thinks the bubble shows the shimmer; the sent line waits above the input',
      (
        tester,
      ) async {
        final slow = _SlowChatApi();
        await slow.generateCourse(const GenerateRequest(topic: 'math'));
        await pumpSkill(tester, slow, 6);
        await type(tester, 'a question');
        await tester.tap(find.byKey(const Key('send')));
        await tester.pump();
        expect(find.byKey(const Key('thinking-shimmer')), findsOneWidget);
        expect(find.byKey(const Key('typing-dots')), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const Key('last-said')),
            matching: find.text('a question'),
          ),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('thinking-shimmer')), findsNothing);
        expect(find.byKey(const Key('last-said')), findsNothing); // faded after her reply
      },
    );

    testWidgets('a failure: a red line above the input and the text comes back', (tester) async {
      await pumpSkill(tester, api, 6);
      api.failNext(method: 'sendChat');
      await say(tester, 'a question');
      expect(find.byKey(const Key('input-error')), findsOneWidget);
      expect(inputText(tester), 'a question');
      expect(bubble(tester), 'Ready to try?');
    });

    testWidgets('a navigate action in her answer switches the scene', (tester) async {
      await pumpSkill(tester, api, 6);
      await say(tester, 'Show me the map');
      expect(find.text('route:/map'), findsOneWidget);
    });

    testWidgets('after an answer the → is still there', (tester) async {
      await pumpSkill(tester, api, 6);
      await say(tester, 'a question');
      expect(find.byKey(const Key('start-audit')), findsOneWidget);
    });
  });

  group('voice', () {
    testWidgets('the mic types the question; sending it asks the chat', (tester) async {
      final voice = FakeVoiceService();
      await pumpSkill(tester, api, 6, voice: voice);
      await tester.tap(find.byKey(const Key('dictation-button')));
      await tester.pumpAndSettle();
      voice.hear('explain it simply');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('stage-input'))).controller!.text, 'explain it simply');
      expect(voice.spoken, isEmpty);
      await tester.tap(find.byKey(const Key('send')));
      await tester.pumpAndSettle();
      expect(
        (await api.getChatHistory()).first.content,
        'About “Discriminant”: explain it simply',
      );
    });

    testWidgets('without speech recognition: a short message', (tester) async {
      await pumpSkill(tester, api, 6, voice: FakeVoiceService(available: false));
      await tester.tap(find.byKey(const Key('dictation-button')));
      await tester.pumpAndSettle();
      expect(find.text(DictationButton.unavailableText), findsOneWidget);
    });
  });

  group('reload', () {
    testWidgets('new materials (from a failed audit’s background search) show up', (tester) async {
      final state = AppState();
      await pumpSkill(tester, api, 5, state: state);
      expect(find.byKey(const ValueKey('link-https://example.org/1')), findsNothing);
      await api.createSearchPlan(5, gap: 'something');
      state.markDataChanged();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('link-https://example.org/1')), findsOneWidget);
    });

    testWidgets('unlocked after the node before it is cleared', (tester) async {
      final state = AppState();
      await pumpSkill(
        tester,
        api,
        7,
        state: state,
      ); // Roots and Coefficients comes after Discriminant
      expect(find.byKey(const Key('start-audit')), findsNothing);
      await passAudit(api, 6);
      state.markDataChanged();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('start-audit')), findsOneWidget);
    });
  });

  group('a phone: she talks about the node', () {
    final block = find.byKey(const Key('skill-node-block'));
    String phoneBubble(WidgetTester tester) => textsIn(tester, find.byKey(const Key('skill-bubble'))).join();

    testWidgets('her line comes first, without her name; then the node; no card, no contents', (
      tester,
    ) async {
      await api.createSearchPlan(5, gap: 'something');
      await pumpSkill(tester, api, 5, size: phoneScreen);
      expect(tester.takeException(), isNull);
      final said = find.byKey(const Key('skill-bubble'));
      expect(tester.getTopLeft(said).dy, lessThan(tester.getTopLeft(block).dy));
      expect(tester.getBottomLeft(find.byType(Avatar)).dy, lessThan(tester.getTopLeft(block).dy));
      expect(phoneBubble(tester), 'Still locked. Clear “Discriminant” first.');
      expect(find.byKey(const Key('speaker-name')), findsNothing);
      expect(find.text('Guide'), findsNothing);
      expect(find.byKey(const Key('skill-node-card')), findsNothing);
      expect(find.byKey(const Key('skill-kicker')), findsNothing);
      expect(find.byKey(const Key('skill-chips')), findsNothing);
      expect(contents, findsNothing);
      expect(find.byKey(const Key('open-right-drawer')), findsNothing);
      expect(panel, findsNothing);
    });

    testWidgets('one muted line: status · course · main quest', (tester) async {
      await pumpSkill(tester, api, 6, size: phoneScreen);
      final line = tester.widget<Text>(find.byKey(const Key('skill-status-line')));
      expect(line.data, startsWith('Ready · High School Math'));
      expect(line.maxLines, 1);
    });

    testWidgets('one number line: Best and attempts, or none yet', (tester) async {
      await pumpSkill(tester, api, 6, size: phoneScreen);
      expect(tester.widget<Text>(find.byKey(const Key('skill-numbers'))).data, 'No attempts yet');
      await failAudit(api, 6);
      await passAudit(api, 6);
      await pumpSkill(tester, api, 6, size: phoneScreen);
      expect(tester.widget<Text>(find.byKey(const Key('skill-numbers'))).data, matches(RegExp(r'^Best \d+ · 2 attempts$')));
      for (final key in ['skill-best', 'skill-attempts', 'skill-lessons']) {
        expect(find.byKey(Key(key)), findsNothing);
      }
    });

    testWidgets('the history waits behind Details; the contents are in Learn first', (tester) async {
      final failed = await failAudit(api, 6);
      await pumpSkill(tester, api, 6, size: phoneScreen);
      final row = find.byKey(Key('audit-row-${failed.sessionId}'));
      expect(row, findsNothing);
      expect(find.text('Audit history'), findsNothing);
      expect(contents, findsNothing);
      await tester.tap(find.byKey(const Key('skill-details')));
      await tester.pumpAndSettle();
      expect(row, findsOneWidget);
      expect(contents, findsNothing); // not twice: they are in Learn first
      expect(find.text('Hide details'), findsOneWidget);
      await tapShown(tester, row);
      expect(find.text('route:${AppRoutes.replay(failed.sessionId)}'), findsOneWidget);
    });

    testWidgets('Details closes again', (tester) async {
      await pumpSkill(tester, api, 6, size: phoneScreen);
      await tester.tap(find.byKey(const Key('skill-details')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('skill-no-audits')), findsOneWidget);
      await tester.tap(find.byKey(const Key('skill-details')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('skill-no-audits')), findsNothing);
    });

    testWidgets('Take it on is pinned above the input: visible on 390×844 without scrolling', (
      tester,
    ) async {
      await failAudit(api, 6);
      await passAudit(api, 6);
      await pumpSkill(tester, api, 6, size: const Size(390, 844));
      await tester.tap(find.byKey(const Key('skill-details')));
      await tester.pumpAndSettle();
      final button = tester.getRect(find.byKey(const Key('start-audit')));
      expect(button.bottom, lessThanOrEqualTo(844));
      expect(button.bottom, lessThanOrEqualTo(tester.getTopLeft(find.byKey(const Key('stage-input'))).dy));
      expect(
        find.ancestor(of: find.byKey(const Key('start-audit')), matching: find.byType(Scrollable)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the ⋯ menu sits beside the title', (tester) async {
      await pumpSkill(tester, api, 6, size: phoneScreen);
      final menu = find.byKey(const Key('skill-menu'));
      expect(menu, findsOneWidget);
      expect(find.descendant(of: block, matching: menu), findsOneWidget);
    });

    testWidgets('a long title wraps to two lines; the muted line under it', (tester) async {
      await api.editSkill(6, title: 'The discriminant of a quadratic and what its sign says about the roots');
      await pumpSkill(tester, api, 6, size: phoneScreen);
      final title = find.byKey(const Key('skill-title'));
      expect(tester.widget<Text>(title).maxLines, 2);
      expect(tester.getSize(title).height, greaterThan(50)); // two lines of 24 px
      expect(
        tester.getTopLeft(find.byKey(const Key('skill-status-line'))).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(title).dy),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a locked boss: no Take it on; the whole-branch challenge is a quiet text button', (
      tester,
    ) async {
      await pumpSkill(tester, api, 5, size: phoneScreen);
      expect(find.byKey(const Key('start-audit')), findsNothing);
      final testOut = find.byKey(const Key('test-out'));
      expect(tester.widget(testOut), isA<TextButton>());
      expect(find.descendant(of: testOut, matching: find.text('Take the whole branch at once')), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      await tester.tap(testOut);
      await tester.pumpAndSettle();
      expect(find.text('route:${AppRoutes.challenge(5)}'), findsOneWidget);
    });

    testWidgets('an open leaf has no whole-branch challenge', (tester) async {
      await pumpSkill(tester, api, 6, size: phoneScreen);
      expect(find.byKey(const Key('test-out')), findsNothing);
    });
  });

  group('the node card (wide screens, unchanged)', () {
    String number(WidgetTester tester, String key) => textsIn(tester, find.byKey(Key(key))).last;

    testWidgets('the card, the contents and her on the right; no phone block', (tester) async {
      await pumpSkill(tester, api, 6);
      final card = find.byKey(const Key('skill-node-card'));
      expect(card, findsOneWidget);
      expect(find.byKey(const Key('skill-node-block')), findsNothing);
      expect(find.byKey(const Key('skill-phone-actions')), findsNothing);
      expect(tester.getTopLeft(find.byType(Avatar)).dx, greaterThan(tester.getTopRight(card).dx));
      expect(tester.getTopLeft(contents).dy, greaterThan(tester.getBottomLeft(card).dy));
      expect(find.descendant(of: card, matching: find.byKey(const Key('start-audit'))), findsOneWidget);
    });

    testWidgets('Best / Attempts / Lessons and the audit history', (tester) async {
      final failed = await failAudit(api, 6);
      await passAudit(api, 6);
      await pumpSkill(tester, api, 6);
      expect(number(tester, 'skill-attempts'), '2');
      expect(number(tester, 'skill-best'), isNot('—'));
      expect(textsIn(tester, find.byKey(const Key('skill-best'))).first, 'Best');
      expect(find.byKey(Key('audit-row-${failed.sessionId}')), findsOneWidget);
    });

    testWidgets('no audits yet: a dash and zeros', (tester) async {
      await pumpSkill(tester, api, 6);
      expect(number(tester, 'skill-best'), '—');
      expect(number(tester, 'skill-attempts'), '0');
      expect(find.byKey(const Key('skill-no-audits')), findsOneWidget);
    });

    testWidgets('an audit row opens its replay', (tester) async {
      final failed = await failAudit(api, 6);
      await pumpSkill(tester, api, 6);
      await tapShown(tester, find.byKey(Key('audit-row-${failed.sessionId}')));
      expect(find.text('route:${AppRoutes.replay(failed.sessionId)}'), findsOneWidget);
    });

    testWidgets('the chips have their own line under the name', (tester) async {
      await pumpSkill(tester, api, 6);
      expect(
        tester.getTopLeft(find.byKey(const Key('skill-chips'))).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.byKey(const Key('skill-title'))).dy),
      );
    });

    testWidgets('a locked boss: no Take it on; the whole-branch challenge says what it does', (
      tester,
    ) async {
      await pumpSkill(tester, api, 5);
      expect(find.byKey(const Key('start-audit')), findsNothing);
      expect(tester.widget(find.byKey(const Key('test-out'))), isA<OutlinedButton>());
      expect(find.byKey(const Key('test-out-hint')), findsOneWidget);
      await tapShown(tester, find.byKey(const Key('test-out')));
      expect(find.text('route:${AppRoutes.challenge(5)}'), findsOneWidget);
    });
  });
}

/// Answers the `url_launcher` channel and records the URLs it was asked to open.
List<String> _recordLaunches(WidgetTester tester) {
  final launched = <String>[];
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'launch') {
      launched.add((call.arguments as Map)['url'] as String);
      return true;
    }
    return false;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
  return launched;
}

List<SearchItem> _links(int count) => [
  for (var i = 1; i <= count; i++)
    SearchItem(title: 't$i', url: 'https://example.org/page/$i', snippet: '', reason: ''),
];

/// An API whose node overview carries the material [items].
class _MaterialsApi extends FakeApiClient {
  _MaterialsApi(this._seed, this.items) : super(latency: Duration.zero);

  final List<SearchItem> items;
  final FakeApiClient _seed;

  @override
  Future<SkillOverview> getSkillOverview(int skillId) async {
    final base = await _seed.getSkillOverview(skillId);
    return SkillOverview(
      skill: base.skill,
      course: base.course,
      containsParents: base.containsParents,
      requires: base.requires,
      audits: base.audits,
      materials: [
        SearchPlan(
          id: 1,
          skillId: skillId,
          gap: 'g',
          queries: const [],
          items: items,
          createdAt: DateTime.utc(2026),
        ),
      ],
    );
  }

  @override
  Future<List<ChatMessage>> sendChat(
    String message, {
    List<int> uploadIds = const [],
    String? reflectionPrompt,
    String? courseTopic,
  }) => _seed.sendChat(
    message,
    uploadIds: uploadIds,
    reflectionPrompt: reflectionPrompt,
    courseTopic: courseTopic,
  );
}

/// A fake whose chat answers after 200 ms (everything else is instant).
class _SlowChatApi extends FakeApiClient {
  _SlowChatApi() : super(latency: Duration.zero);

  @override
  Future<List<ChatMessage>> sendChat(
    String message, {
    List<int> uploadIds = const [],
    String? reflectionPrompt,
    String? courseTopic,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return super.sendChat(
      message,
      uploadIds: uploadIds,
      reflectionPrompt: reflectionPrompt,
      courseTopic: courseTopic,
    );
  }
}
