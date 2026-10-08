// Scene 4: the node overview — the node's name in the title bar with a status
// chip, the contents card (one row per material), the avatar asking
// Ready to try? →, “Attempts” as cards, questions to the chat.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/app/app_state.dart';
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
    testWidgets('the title bar shows the node name in the headline style, not node: …', (
      tester,
    ) async {
      await pumpSkill(tester, api, 5);
      final title = tester.widget<Text>(find.byKey(const Key('stage-title')));
      expect(title.data, 'Quadratic Equations');
      expect(title.style!.fontSize, 20);
      expect(find.textContaining('node:'), findsNothing);
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
        of: find.byKey(const Key('stage-panel')),
        matching: find.text('Failed'),
      );
      expect(chip, findsOneWidget);
      // The chip sits right of the name.
      expect(
        tester.getTopLeft(chip).dx,
        greaterThan(tester.getTopRight(find.byKey(const Key('stage-title'))).dx),
      );
    });

    testWidgets('no badges, no day/night switch, no audit button outside the bubble', (
      tester,
    ) async {
      await pumpSkill(tester, api, 6);
      expect(find.byType(SegmentedButton<String>), findsNothing);
      expect(find.byKey(const Key('mode-toggle')), findsNothing);
      expect(find.text('Day'), findsNothing);
      expect(find.text('Night'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
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
      expect(find.text('About'), findsOneWidget);
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
      await tester.tap(
        find.descendant(of: row, matching: find.byKey(const Key('material-domain'))),
      );
      await tester.pumpAndSettle();
      expect(launched, ['https://example.org/1']);
      // Tapping the badge works as well.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('link-https://example.org/2')),
          matching: find.byKey(const Key('material-badge')),
        ),
      );
      await tester.pumpAndSettle();
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

      await tester.tap(find.byKey(const Key('links-next')));
      await tester.pump();
      expect(find.byKey(const ValueKey('link-https://example.org/page/1')), findsNothing);
      expect(find.byKey(const ValueKey('link-https://example.org/page/5')), findsOneWidget);
      expect(find.byKey(const Key('links-prev')), findsOneWidget);

      await tester.tap(find.byKey(const Key('links-next')));
      await tester.pump();
      expect(find.byKey(const ValueKey('link-https://example.org/page/9')), findsOneWidget);
      expect(find.byKey(const Key('links-next')), findsNothing);
      expect(find.text('3/3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('links-prev')));
      await tester.pump();
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
      await tester.tap(
        find.descendant(of: source, matching: find.byKey(const Key('material-title'))),
      );
      await tester.pumpAndSettle();
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
    testWidgets('an available node: waving, Ready to try? →', (tester) async {
      await pumpSkill(tester, api, 6);
      expect(bubble(tester), 'Ready to try?');
      expect(find.byKey(const Key('start-audit')), findsOneWidget);
      expect(avatar(tester).wave, isTrue);
      expect(avatar(tester).mood, AvatarMood.smile);
    });

    testWidgets('→ opens the audit (scene 4-1) without a mode', (tester) async {
      await pumpSkill(tester, api, 6);
      await tester.tap(find.byKey(const Key('start-audit')));
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

    testWidgets('any locked node names the same open node', (tester) async {
      await pumpSkill(tester, api, 12);
      expect(bubble(tester), 'Still locked. Clear “Discriminant” first.');
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

  group('Attempts: the audits of this node as cards', () {
    testWidgets('empty', (tester) async {
      await pumpSkill(tester, api, 6);
      expect(find.text('No attempts yet.'), findsOneWidget);
      expect(find.text('Attempts'), findsOneWidget);
    });

    testWidgets('a card per audit: date, a Passed/Failed chip and the score, newest first', (
      tester,
    ) async {
      await failAudit(api, 6);
      await passAudit(api, 6);
      await pumpSkill(tester, api, 6);
      final cards = find.byKey(const Key('audit-card'));
      expect(cards, findsNWidgets(2));
      final newest = textsIn(tester, cards.at(0)).toList();
      final oldest = textsIn(tester, cards.at(1)).toList();
      expect(newest[0], matches(r'^[A-Z][a-z]{2} \d{1,2}, \d{4} \d{2}:\d{2}$'));
      expect(newest[1], endsWith(' pts'));
      expect(newest, contains('Passed'));
      expect(oldest, containsAll(['45 pts', 'Failed']));
      // A card is a white card with a hairline.
      final decoration = tester.widget<DecoratedBox>(cards.first).decoration as BoxDecoration;
      expect(decoration.color, AppColors.surface);
      expect(decoration.borderRadius, BorderRadius.circular(16));
    });

    testWidgets('the chips are colored: green for a pass, red for a fail', (tester) async {
      await failAudit(api, 6);
      await passAudit(api, 6);
      await pumpSkill(tester, api, 6);
      Color colorOf(String label) => tester.widget<Text>(find.text(label)).style!.color!;
      Color fillOf(String label) =>
          (tester
                      .widget<DecoratedBox>(
                        find
                            .ancestor(of: find.text(label), matching: find.byType(DecoratedBox))
                            .first,
                      )
                      .decoration
                  as BoxDecoration)
              .color!;
      expect(colorOf('Passed'), AppColors.success);
      expect(fillOf('Passed'), AppColors.successSoft);
      expect(colorOf('Failed'), AppColors.danger);
      expect(fillOf('Failed'), AppColors.dangerSoft);
    });

    testWidgets('only this node’s audits', (tester) async {
      await passAudit(api, 6);
      await pumpSkill(tester, api, 7);
      expect(find.text('No attempts yet.'), findsOneWidget);
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

  testWidgets('a phone: contents above the avatar, nothing overflows', (tester) async {
    await api.createSearchPlan(5, gap: 'something');
    await pumpSkill(tester, api, 5, size: phoneScreen);
    expect(tester.takeException(), isNull);
    expect(tester.getBottomLeft(contents).dy, lessThan(tester.getTopLeft(find.byType(Avatar)).dy));
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
