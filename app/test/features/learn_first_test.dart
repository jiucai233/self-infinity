// The node page's Learn first: what there is to study (the knowledge points
// and what was missed, the lesson cards, the materials, Find material on what
// was missed) and the player's own notes (add, edit, delete). On a wide
// screen the card under the node card; on a phone a row that opens a sheet,
// Take it on staying pinned.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/features/skill/skill_scene.dart';
import 'package:self_infinity/testing/test_app.dart';

import '../support/scene_helpers.dart';

Finder key(String k) => find.byKey(Key(k));
Finder get learn => key('skill-contents');

Future<void> pumpNode(WidgetTester tester, FakeApiClient api, int id, {Size size = wideScreen}) =>
    pumpScene(
      tester,
      SkillScene(skillId: id),
      api: api,
      size: size,
    );

Future<void> tapShown(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The phone's Learn first sheet, opened.
Future<void> openSheet(WidgetTester tester) async {
  await tapShown(tester, key('skill-learn'));
  expect(key('learn-sheet'), findsOneWidget);
}

/// Writes [text] in the new-note field and saves it.
Future<void> addNote(WidgetTester tester, String text) async {
  await tester.ensureVisible(key('note-input'));
  await tester.enterText(key('note-input'), text);
  await tester.pumpAndSettle();
  await tapShown(tester, key('note-add'));
}

List<String> noteTexts(WidgetTester tester) =>
    tester.widgetList<Text>(key('note-text')).map((t) => t.data!).toList();

/// Add, edit and delete, wherever the notes are shown.
Future<void> exerciseNotes(WidgetTester tester, FakeApiClient api) async {
  expect(key('note-add'), findsNothing); // nothing to save yet
  await addNote(tester, 'b² − 4ac decides');
  await addNote(tester, 'Negative:\nno real roots');
  expect(noteTexts(tester), ['Negative:\nno real roots', 'b² − 4ac decides']); // newest first
  expect(tester.widget<TextField>(key('note-input')).controller!.text, isEmpty);
  final saved = await api.listNodeNotes(6);
  expect(saved.map((n) => n.content), ['Negative:\nno real roots', 'b² − 4ac decides']);

  // Tap to edit.
  final older = saved.last;
  await tapShown(tester, key('note-open-${older.id}'));
  expect(key('note-edit-field'), findsOneWidget);
  await tester.enterText(key('note-edit-field'), 'The discriminant decides');
  await tester.pumpAndSettle();
  await tapShown(tester, key('note-edit-save'));
  expect(key('note-edit-field'), findsNothing);
  expect(noteTexts(tester), ['Negative:\nno real roots', 'The discriminant decides']);
  expect((await api.listNodeNotes(6)).last.content, 'The discriminant decides');

  // Delete after asking; cancel keeps it.
  final newer = saved.first;
  await tapShown(tester, key('note-delete-${newer.id}'));
  expect(key('note-delete-dialog'), findsOneWidget);
  await tester.tap(find.text('Cancel'));
  await tester.pumpAndSettle();
  expect(noteTexts(tester), hasLength(2));
  await tapShown(tester, key('note-delete-${newer.id}'));
  await tester.tap(key('note-delete-confirm'));
  await tester.pumpAndSettle();
  expect(noteTexts(tester), ['The discriminant decides']);
  expect((await api.listNodeNotes(6)).map((n) => n.content), ['The discriminant decides']);
  expect(tester.takeException(), isNull);
}

void main() {
  late FakeApiClient api;

  setUp(() async {
    api = await seededFakeApi();
  });

  group('wide: the card under the node card', () {
    testWidgets('a fresh node: what it covers and the notes; no Find material', (tester) async {
      await pumpNode(tester, api, 6);
      expect(learn, findsOneWidget);
      expect(find.descendant(of: learn, matching: find.text('Learn first')), findsOneWidget);
      expect(key('skill-description'), findsOneWidget);
      expect(find.text('My notes'), findsOneWidget);
      expect(find.text("Only you see these. They aren't used in the challenge."), findsOneWidget);
      expect(key('learn-find-materials'), findsNothing); // nothing missed: nothing to search for
      // Still one ink button: Take it on.
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('after a fail: the missed point with why, the lesson card once, Find material', (
      tester,
    ) async {
      final failed = await failAudit(api, 6);
      final lesson = await api.submitReflection(failed.sessionId, 'I memorized the formula');
      await pumpNode(tester, api, 6);
      expect(
        find.descendant(of: key('skill-point-0'), matching: find.text(FakeApiClient.failNote)),
        findsOneWidget,
      );
      // The lesson card is in Learn first only, not also under the node card's history.
      final card = key('skill-lesson-${lesson.id}');
      expect(card, findsOneWidget);
      expect(find.descendant(of: learn, matching: card), findsOneWidget);
      expect(find.text(lesson.title), findsOneWidget);
      expect(find.text('Lesson cards'), findsOneWidget);

      expect(key('link-https://example.org/1'), findsNothing);
      await tapShown(tester, key('learn-find-materials'));
      expect(key('link-https://example.org/1'), findsOneWidget);
      final plans = (await api.getSkillOverview(6)).materials;
      expect(plans, hasLength(1));
      expect(plans.single.gap, contains(FakeApiClient.failNote)); // searched on what was missed
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed search says so quietly; the button stays', (tester) async {
      await failAudit(api, 6);
      await pumpNode(tester, api, 6);
      api.failNext(method: 'createSearchPlan');
      await tapShown(tester, key('learn-find-materials'));
      expect(find.text("The search didn't go through. Try again later."), findsOneWidget);
      expect(key('learn-find-materials'), findsOneWidget);
    });

    testWidgets('notes: add, edit, delete', (tester) async {
      await pumpNode(tester, api, 6);
      await exerciseNotes(tester, api);
    });

    testWidgets('notes are kept: they are there on the next visit, for their node only', (
      tester,
    ) async {
      await api.createNodeNote(6, 'From last time');
      await pumpNode(tester, api, 6);
      expect(noteTexts(tester), ['From last time']);
      await pumpNode(tester, api, 7);
      expect(noteTexts(tester), isEmpty);
    });

    testWidgets('an edited note says so', (tester) async {
      final note = await api.createNodeNote(6, 'first');
      await api.updateNodeNote(note.id, 'second');
      await pumpNode(tester, api, 6);
      expect(
        find.descendant(of: key('note-${note.id}'), matching: find.textContaining('edited')),
        findsOneWidget,
      );
    });

    testWidgets('a note that does not save keeps the text and says so', (tester) async {
      await pumpNode(tester, api, 6);
      api.failNext(method: 'createNodeNote');
      await addNote(tester, 'keep me');
      expect(key('note-problem'), findsOneWidget);
      expect(tester.widget<TextField>(key('note-input')).controller!.text, 'keep me');
      expect(await api.listNodeNotes(6), isEmpty);
    });

    testWidgets('notes that do not load say so', (tester) async {
      api.failNext(method: 'listNodeNotes');
      await pumpNode(tester, api, 6);
      expect(key('notes-load-failed'), findsOneWidget);
    });

    testWidgets('a whitespace-only note cannot be saved', (tester) async {
      await pumpNode(tester, api, 6);
      await tester.enterText(key('note-input'), '   \n ');
      await tester.pumpAndSettle();
      expect(key('note-add'), findsNothing);
    });
  });

  group('phone: one row that opens a sheet', () {
    testWidgets('the row sits in the node block; the page stays minimal', (tester) async {
      await pumpNode(tester, api, 6, size: phoneScreen);
      expect(
        find.descendant(of: key('skill-node-block'), matching: key('skill-learn')),
        findsOneWidget,
      );
      expect(learn, findsNothing);
      expect(key('node-notes'), findsNothing);
      expect(key('start-audit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the sheet has the points, the lesson cards, Find material and the notes', (
      tester,
    ) async {
      final failed = await failAudit(api, 6);
      final lesson = await api.submitReflection(failed.sessionId, 'I memorized the formula');
      await pumpNode(tester, api, 6, size: phoneScreen);
      await openSheet(tester);
      expect(find.descendant(of: key('learn-sheet'), matching: learn), findsOneWidget);
      expect(key('skill-point-0'), findsOneWidget);
      expect(key('skill-lesson-${lesson.id}'), findsOneWidget);
      expect(key('learn-find-materials'), findsOneWidget);
      expect(key('node-notes'), findsOneWidget);
      // Details holds only the history now: nothing shows twice.
      expect(key('skill-details-body'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('notes in the sheet: add, edit, delete', (tester) async {
      await pumpNode(tester, api, 6, size: phoneScreen);
      await openSheet(tester);
      await exerciseNotes(tester, api);
    });

    testWidgets('closing the sheet leaves Take it on pinned where it was', (tester) async {
      await pumpNode(tester, api, 6, size: phoneScreen);
      final before = tester.getRect(key('start-audit'));
      await openSheet(tester);
      await tester.tapAt(const Offset(200, 20)); // the scrim above the sheet
      await tester.pumpAndSettle();
      expect(key('learn-sheet'), findsNothing);
      expect(tester.getRect(key('start-audit')), before);
    });
  });
}
