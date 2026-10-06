// The lesson card flips from its back to its front (docs/ux-chat.md 5.9).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/features/audit/lesson_card.dart';
import 'package:self_infinity/theme/app_theme.dart';
import 'package:self_infinity/theme/tokens.dart';
import 'package:self_infinity/widgets/widgets.dart';

Principle principle({String? misconception = 'I thought memorizing the definition was enough'}) =>
    Principle(
      id: 1,
      title: 'Revisit “Quadratic Equations”',
      body: 'I give the reason before the conclusion.',
      misconception: misconception,
      sourceSessionId: 1,
      skillId: 5,
      skillTitle: 'Quadratic Equations',
      createdAt: DateTime.utc(2026, 10, 2),
    );

Future<void> pumpCard(WidgetTester tester, LessonCard card) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: Center(child: card)),
  ),
);

/// The rotation about the vertical axis, in radians (from the transform matrix).
double turnOf(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(of: find.byType(LessonCard), matching: find.byType(Transform)).first,
  );
  final m = transform.transform;
  return m.entry(0, 2).abs() > 1e-9 ? m.entry(0, 2) : 0;
}

/// Whether the front face is the one showing (it keeps its space while hidden).
bool frontShows(WidgetTester tester) => tester
    .widget<Visibility>(
      find
          .ancestor(
            of: find.byKey(const Key('lesson-card-front'), skipOffstage: false),
            matching: find.byType(Visibility),
          )
          .first,
    )
    .visible;

void main() {
  tearDown(() => Avatar.animationsEnabled = false);

  testWidgets('without animation the front shows at once: title, body, misconception', (
    tester,
  ) async {
    await pumpCard(tester, LessonCard(principle: principle(), animate: false));
    expect(find.byKey(const Key('lesson-card-front')), findsOneWidget);
    expect(find.byKey(const Key('lesson-card-back')), findsNothing);
    expect(find.text('Revisit “Quadratic Equations”'), findsOneWidget);
    expect(find.text('I give the reason before the conclusion.'), findsOneWidget);
    expect(find.text('I thought memorizing the definition was enough'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('the misconception is a red small label; without one there is none', (tester) async {
    await pumpCard(tester, LessonCard(principle: principle(), animate: false));
    final label = tester.widget<Text>(find.byKey(const Key('lesson-misconception')));
    expect(label.style!.color, AppColors.danger);
    expect(label.style!.fontSize, 12);
    final chip = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.byKey(const Key('lesson-misconception')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((chip.decoration as BoxDecoration).color, AppColors.dangerSoft);
    await pumpCard(tester, LessonCard(principle: principle(misconception: null), animate: false));
    expect(find.byKey(const Key('lesson-misconception')), findsNothing);
  });

  testWidgets('animated: the back turns away, then the front turns toward us in 300 ms', (
    tester,
  ) async {
    await pumpCard(tester, LessonCard(principle: principle(), animate: true));
    // Start: the back is showing, flat.
    expect(find.byKey(const Key('lesson-card-back')), findsOneWidget);
    expect(frontShows(tester), isFalse);
    expect(
      find.descendant(
        of: find.byKey(const Key('lesson-card-back')),
        matching: find.text('Lesson card'),
      ),
      findsOneWidget,
    );
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byKey(const Key('lesson-card-back')), findsOneWidget);
    expect(frontShows(tester), isFalse);
    final early = turnOf(tester);
    expect(early, isNot(0), reason: 'it is turning');

    await tester.pump(const Duration(milliseconds: 150)); // past the half-way point
    expect(find.byKey(const Key('lesson-card-back')), findsNothing);
    expect(frontShows(tester), isTrue);
    // The front comes in from the opposite side, still turning.
    expect(turnOf(tester).sign, isNot(early.sign));

    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.hasRunningAnimations, isFalse);
    expect(turnOf(tester), 0);
    expect(frontShows(tester), isTrue);
    expect(LessonCard.flipDuration, const Duration(milliseconds: 300));
  });

  testWidgets('by default it follows Avatar.animationsEnabled', (tester) async {
    Avatar.animationsEnabled = false;
    await pumpCard(tester, LessonCard(principle: principle()));
    expect(find.byKey(const Key('lesson-card-front')), findsOneWidget);
    Avatar.animationsEnabled = true;
    await pumpCard(tester, LessonCard(key: UniqueKey(), principle: principle()));
    expect(find.byKey(const Key('lesson-card-back')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('the back and the front are the same size', (tester) async {
    await pumpCard(tester, LessonCard(principle: principle(), animate: true));
    final back = tester.getSize(find.byKey(const Key('lesson-card-back')));
    await tester.pump(const Duration(milliseconds: 300));
    final front = tester.getSize(find.byKey(const Key('lesson-card-front')));
    expect(back, front);
  });
}
