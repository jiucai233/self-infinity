// The workout log on the Life page (contract #54): a said line, the week,
// a day's workouts to fix or delete, routines to check off, CSV in and out.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/features/life/life_scene.dart';
import 'package:self_infinity/features/workout/exercise_library.dart';
import 'package:self_infinity/features/workout/workout_log.dart';
import 'package:self_infinity/testing/fake_file_picker.dart';
import 'package:self_infinity/upload/file_picker_service.dart';

import '../support/scene_helpers.dart';

Finder key(String k) => find.byKey(Key(k));

FakeApiClient newApi() => FakeApiClient(latency: Duration.zero);

String today() => formatKstDate(DateTime.now());

Future<void> pumpSection(WidgetTester tester, FakeApiClient api, {FakeFilePicker? picker}) => pumpScene(
  tester,
  const Scaffold(body: SingleChildScrollView(child: WorkoutLog())),
  api: api,
  picker: picker,
);

String xp(WidgetTester tester) => tester.widget<Text>(key('workout-xp')).data!;

void main() {
  setUp(() => ExerciseLibrary.debugOverride = ExerciseLibrary(const []));
  tearDown(() => ExerciseLibrary.debugOverride = null);

  testWidgets('the Life page has the workout log', (tester) async {
    await pumpScene(tester, const LifeScene(), api: newApi());
    expect(key('workout-section'), findsOneWidget);
  });

  testWidgets('empty: today with nothing logged, no streak, 0 XP, 90 days', (tester) async {
    await pumpSection(tester, newApi());
    expect(key('workout-none'), findsOneWidget);
    expect(key('workout-streak'), findsNothing);
    expect(xp(tester), '0 XP');
    expect(find.descendant(of: key('workout-heatmap'), matching: find.byType(InkWell)), findsNWidgets(90));
    expect(key('workout-next'), findsOneWidget);
    expect(tester.widget<IconButton>(key('workout-next')).onPressed, isNull); // no future days
  });

  testWidgets('a said line becomes workouts, with a streak and XP', (tester) async {
    final api = newApi();
    await pumpSection(tester, api);
    await tester.enterText(key('workout-say'), 'squats 3x20, running 5km 28 min');
    await tester.pump();
    await tester.tap(key('send'));
    await tester.pumpAndSettle();

    expect(find.text('Squat'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.textContaining('3×20'), findsOneWidget);
    expect(find.textContaining('5km · 28min'), findsOneWidget);
    expect(find.text('Logged 2.'), findsOneWidget);
    expect(tester.widget<Text>(key('workout-streak')).data, '1-day streak');
    expect(xp(tester), '20 XP');
    expect(tester.widget<TextField>(key('workout-say')).controller!.text, isEmpty);
  });

  testWidgets('a line that names nothing is kept for another try', (tester) async {
    await pumpSection(tester, newApi());
    await tester.enterText(key('workout-say'), 'felt great');
    await tester.pump();
    await tester.tap(key('send'));
    await tester.pumpAndSettle();
    expect(find.textContaining("couldn't find a workout"), findsOneWidget);
    expect(tester.widget<TextField>(key('workout-say')).controller!.text, 'felt great');
    expect(key('workout-none'), findsOneWidget);
  });

  testWidgets('Add: a catalog exercise asks for its own numbers; a custom one for a category', (
    tester,
  ) async {
    final api = newApi();
    await pumpSection(tester, api);
    await tester.tap(key('workout-add'));
    await tester.pumpAndSettle();

    await tester.enterText(key('workout-exercise'), 'Squat');
    await tester.pumpAndSettle();
    expect(key('workout-category'), findsNothing); // the catalog knows it
    expect(key('amount-sets'), findsOneWidget);
    expect(key('amount-minutes'), findsNothing);

    await tester.tap(key('workout-save'));
    await tester.pumpAndSettle();
    expect(key('workout-error'), findsOneWidget); // no number yet

    await tester.enterText(key('amount-sets'), '4');
    await tester.enterText(key('amount-reps'), '12');
    await tester.enterText(key('amount-weight'), '60');
    await tester.tap(key('workout-save'));
    await tester.pumpAndSettle();
    expect(key('workout-dialog'), findsNothing);
    final saved = (await api.listWorkouts()).single;
    expect(saved.exerciseKey, 'squat');
    expect(saved.amount, const WorkoutAmount(sets: 4, reps: 12, weightKg: 60));
    expect(find.textContaining('Strength · 4×12 · 60kg'), findsOneWidget);

    await tester.tap(key('workout-add'));
    await tester.pumpAndSettle();
    await tester.enterText(key('workout-exercise'), 'Climbing');
    await tester.pumpAndSettle();
    expect(key('workout-category'), findsOneWidget);
  });

  testWidgets('a tap fixes a workout; × deletes it', (tester) async {
    final api = newApi();
    final w = await api.createWorkout(
      WorkoutDraft(date: today(), exercise: 'Plank', amount: const WorkoutAmount(durationMin: 2)),
    );
    await pumpSection(tester, api);

    await tester.tap(key('workout-${w.id}'));
    await tester.pumpAndSettle();
    expect(find.text('Edit workout'), findsOneWidget);
    await tester.enterText(key('amount-minutes'), '5');
    await tester.tap(key('workout-save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('5min'), findsOneWidget);

    await tester.tap(key('workout-delete-${w.id}'));
    await tester.pumpAndSettle();
    expect(await api.listWorkouts(), isEmpty);
    expect(key('workout-none'), findsOneWidget);
  });

  testWidgets("today's routine is checked off item by item; a full routine adds a bonus", (
    tester,
  ) async {
    final api = newApi();
    final weekday = DateTime.parse(today()).weekday - 1;
    final r = await api.createRoutine(
      RoutineDraft(
        name: 'Upper A',
        weekdays: [weekday],
        items: const [
          RoutineItem(exercise: 'Push-up', amount: WorkoutAmount(sets: 3, reps: 15)),
          RoutineItem(exercise: 'Pull-up', amount: WorkoutAmount(sets: 3, reps: 8)),
        ],
      ),
    );
    await pumpSection(tester, api);
    expect(find.text('Upper A'), findsOneWidget);
    expect(key('workout-none'), findsNothing);

    await tester.tap(key('routine-item-${r.id}-0'));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(key('routine-item-${r.id}-0')).value, isTrue);
    expect(xp(tester), '10 XP');

    await tester.tap(key('routine-item-${r.id}-1'));
    await tester.pumpAndSettle();
    expect(xp(tester), '40 XP'); // 2 × 10, +20 for the whole routine
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    await tester.tap(key('routine-item-${r.id}-1')); // unchecked again
    await tester.pumpAndSettle();
    expect(xp(tester), '10 XP');
    // A routine's workouts are its checkboxes, not rows of their own.
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('a routine is made in ⋯ Routines: name, days, exercises', (tester) async {
    final api = newApi();
    await pumpSection(tester, api);
    await tester.tap(key('workout-menu'));
    await tester.pumpAndSettle();
    await tester.tap(key('workout-routines'));
    await tester.pumpAndSettle();
    expect(find.text('No routines yet.'), findsOneWidget);

    await tester.tap(key('routine-new'));
    await tester.pumpAndSettle();
    await tester.enterText(key('routine-name'), 'Legs');
    await tester.tap(key('routine-save'));
    await tester.pumpAndSettle();
    expect(find.text('Pick at least one day.'), findsOneWidget);

    await tester.tap(key('routine-day-0'));
    await tester.tap(key('routine-day-3'));
    await tester.tap(key('routine-add-item'));
    await tester.pumpAndSettle();
    await tester.enterText(key('workout-exercise'), 'Lunge');
    await tester.pumpAndSettle();
    await tester.enterText(key('amount-sets'), '3');
    await tester.enterText(key('amount-reps'), '10');
    await tester.tap(key('routine-item-done'));
    await tester.pumpAndSettle();
    await tester.tap(key('routine-save'));
    await tester.pumpAndSettle();

    final r = (await api.listRoutines()).single;
    expect(r.name, 'Legs');
    expect(r.weekdays, [0, 3]);
    expect(r.items.single.exerciseKey, 'lunge');
    expect(key('routine-${r.id}'), findsOneWidget);
  });

  testWidgets('the arrows and the bars pick the day', (tester) async {
    final api = newApi();
    final yesterday = formatKstDate(DateTime.now().subtract(const Duration(days: 1)));
    await api.createWorkout(
      WorkoutDraft(date: yesterday, exercise: 'Yoga', amount: const WorkoutAmount(durationMin: 30)),
    );
    await pumpSection(tester, api);
    expect(find.text('Yoga'), findsNothing);

    await tester.tap(key('workout-prev'));
    await tester.pumpAndSettle();
    expect(find.text('Yoga'), findsOneWidget);

    await tester.tap(key('workout-day-${today()}'));
    await tester.pumpAndSettle();
    expect(find.text('Yoga'), findsNothing);
  });

  testWidgets('import reads a CSV the picker gives; export says where it works', (tester) async {
    final api = newApi();
    final picker = FakeFilePicker()
      ..next = PickedFile(
        name: 'old.csv',
        bytes: utf8.encode('date,exercise,category,sets,reps,weight_kg,duration_min,distance_km,note\n'
            '${today()},Squat,strength,3,10,,,,\n'
            'bad-date,Squat,strength,3,10,,,,\n'),
      );
    await pumpSection(tester, api, picker: picker);

    await tester.tap(key('workout-menu'));
    await tester.pumpAndSettle();
    await tester.tap(key('workout-import'));
    await tester.pumpAndSettle();
    expect(picker.lastExtensions, ['csv', 'xlsx']);
    expect(find.textContaining('Imported 1, skipped 0.'), findsOneWidget);
    expect(find.textContaining('#3'), findsOneWidget);
    expect(find.text('Squat'), findsOneWidget);

    await tester.tap(key('workout-menu'));
    await tester.pumpAndSettle();
    await tester.tap(key('workout-export-csv'));
    await tester.pumpAndSettle();
    expect(find.text('Export works in the browser.'), findsOneWidget); // no download in a test
  });

  test('the fake reads lines the way the server does', () async {
    final api = FakeApiClient(latency: Duration.zero, language: 'ko');
    final said = await api.sayWorkout('오늘 스쿼트 3세트 20회, 러닝 30분, 기분 좋음');
    expect([for (final w in said.workouts) w.exercise], ['스쿼트', '러닝']);
    expect(said.workouts.first.amount, const WorkoutAmount(sets: 3, reps: 20));
    expect(said.workouts.last.amount.durationMin, 30);
    expect(said.unread, ['기분 좋음']);

    final yesterday = await api.sayWorkout('어제 플랭크 5분');
    expect(yesterday.workouts.single.date, formatKstDate(DateTime.now().subtract(const Duration(days: 1))));

    final zh = FakeApiClient(latency: Duration.zero, language: 'zh');
    final z = await zh.sayWorkout('跑步40分钟，俯卧撑3组15个');
    expect([for (final w in z.workouts) w.exerciseKey], ['running', 'push_up']);
  });
}
