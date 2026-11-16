// The workout page (contract #54): the log, the library by body part with
// each movement's steps and history, and progress per exercise.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/features/life/life_scene.dart';
import 'package:self_infinity/features/workout/exercise_library.dart';
import 'package:self_infinity/features/workout/workout_charts.dart';
import 'package:self_infinity/features/workout/workout_scene.dart';

import '../support/scene_helpers.dart';

Finder key(String k) => find.byKey(Key(k));

String today() => formatKstDate(DateTime.now());

LibraryExercise ex(String id, String en, String ko, BodyPart body, Equipment equipment, {String? catalog}) =>
    LibraryExercise(
      id: id,
      names: {'en': en, 'ko': ko, 'zh': en},
      body: body,
      category: body == BodyPart.cardio ? WorkoutCategory.cardio : WorkoutCategory.strength,
      equipment: equipment,
      level: 'beginner',
      muscles: const ['quadriceps'],
      unit: body == BodyPart.cardio ? WorkoutUnit.distance : WorkoutUnit.reps,
      steps: const {
        'en': ['Stand tall.', 'Go down.'],
        'ko': ['똑바로 서세요.', '내려가세요.'],
        'zh': ['站直。', '下蹲。'],
      },
      images: const [],
      catalog: catalog,
    );

final library = ExerciseLibrary([
  ex('Barbell_Squat', 'Barbell Squat', '바벨 스쿼트', BodyPart.legs, Equipment.barbell, catalog: 'squat'),
  ex('Pushups', 'Pushups', '푸시업', BodyPart.chest, Equipment.body, catalog: 'push_up'),
  ex('Dumbbell_Curl', 'Dumbbell Curl', '덤벨 컬', BodyPart.arms, Equipment.dumbbell),
  ex('Jogging', 'Jogging', '조깅', BodyPart.cardio, Equipment.body, catalog: 'running'),
]);

Future<void> openTab(WidgetTester tester, String tab) async {
  await tester.tap(key('workout-tab-$tab'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => ExerciseLibrary.debugOverride = library);
  tearDown(() => ExerciseLibrary.debugOverride = null);

  testWidgets('the Life page card opens the workout page', (tester) async {
    await pumpScene(tester, const LifeScene(), api: FakeApiClient(latency: Duration.zero));
    await tester.ensureVisible(key('workout-open'));
    await tester.pumpAndSettle();
    await tester.tap(key('workout-open'));
    await tester.pumpAndSettle();
    expect(find.text('route:/life/workout'), findsOneWidget);
  });

  testWidgets('the library is browsed by body part and searched', (tester) async {
    await pumpScene(tester, const WorkoutScene(), api: FakeApiClient(latency: Duration.zero));
    await openTab(tester, 'library');
    expect(key('exercise-Barbell_Squat'), findsOneWidget);
    expect(key('exercise-Dumbbell_Curl'), findsOneWidget);

    await tester.tap(key('body-legs'));
    await tester.pumpAndSettle();
    expect(key('exercise-Barbell_Squat'), findsOneWidget);
    expect(key('exercise-Pushups'), findsNothing);

    await tester.tap(key('body-all'));
    await tester.pumpAndSettle();
    await tester.enterText(key('library-search'), 'curl');
    await tester.pumpAndSettle();
    expect(key('exercise-Dumbbell_Curl'), findsOneWidget);
    expect(key('exercise-Barbell_Squat'), findsNothing);

    await tester.enterText(key('library-search'), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No exercise matches.'), findsOneWidget);
  });

  testWidgets('a movement shows its steps and history; Log it logs it today', (tester) async {
    final api = FakeApiClient(latency: Duration.zero);
    await api.createWorkout(
      WorkoutDraft(
        date: today(),
        exercise: 'Squat',
        exerciseKey: 'squat',
        amount: const WorkoutAmount(sets: 3, reps: 5, weightKg: 80),
      ),
    );
    await pumpScene(tester, const WorkoutScene(), api: api);
    await openTab(tester, 'library');
    await tester.tap(key('exercise-Barbell_Squat'));
    await tester.pumpAndSettle();

    expect(key('exercise-detail'), findsOneWidget);
    expect(find.text('Stand tall.'), findsOneWidget);
    expect(tester.widget<Text>(key('exercise-best')).data, 'Best 80kg');
    expect(find.text('3×5 · 80kg'), findsOneWidget);

    await tester.tap(key('exercise-log'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(key('workout-exercise')).controller!.text, 'Barbell Squat');
    await tester.enterText(key('amount-sets'), '5');
    await tester.enterText(key('amount-reps'), '5');
    await tester.enterText(key('amount-weight'), '85');
    await tester.tap(key('workout-save'));
    await tester.pumpAndSettle();

    final logged = (await api.listWorkouts()).first;
    expect(logged.exercise, 'Barbell Squat');
    expect(logged.exerciseKey, 'squat');
    expect(logged.amount.weightKg, 85);
  });

  testWidgets('the add dialog offers the library by name', (tester) async {
    final api = FakeApiClient(latency: Duration.zero);
    await pumpScene(tester, const WorkoutScene(), api: api);
    await tester.tap(key('workout-add'));
    await tester.pumpAndSettle();
    await tester.enterText(key('workout-exercise'), 'Dumbbell Curl');
    await tester.pumpAndSettle();
    expect(key('workout-category'), findsNothing); // the library knows it
    await tester.enterText(key('amount-sets'), '3');
    await tester.enterText(key('amount-reps'), '12');
    await tester.tap(key('workout-save'));
    await tester.pumpAndSettle();
    final w = (await api.listWorkouts()).single;
    expect((w.exercise, w.category), ('Dumbbell Curl', WorkoutCategory.strength));
  });

  testWidgets('progress: a line per exercise and the last 30 days by body part', (tester) async {
    final api = FakeApiClient(latency: Duration.zero);
    final yesterday = formatKstDate(DateTime.now().subtract(const Duration(days: 1)));
    for (final (d, kg) in [(yesterday, 60.0), (today(), 65.0)]) {
      await api.createWorkout(
        WorkoutDraft(
          date: d,
          exercise: 'Barbell Squat',
          exerciseKey: 'squat',
          amount: WorkoutAmount(sets: 3, reps: 5, weightKg: kg),
        ),
      );
    }
    await api.createWorkout(
      WorkoutDraft(date: today(), exercise: 'Jogging', amount: const WorkoutAmount(durationMin: 20)),
    );
    await pumpScene(tester, const WorkoutScene(), api: api);
    await openTab(tester, 'stats');

    expect(key('progress-line'), findsOneWidget);
    expect(find.text('Top weight (kg)'), findsOneWidget);
    final bars = tester.widget<CountBars>(key('stats-by-body'));
    expect(bars.rows, containsAll([('Legs', 2), ('Cardio', 1)]));
  });

  testWidgets('progress with nothing logged says how it fills', (tester) async {
    await pumpScene(tester, const WorkoutScene(), api: FakeApiClient(latency: Duration.zero));
    await openTab(tester, 'stats');
    expect(key('stats-none'), findsOneWidget);
  });

  testWidgets('on a phone the page fits', (tester) async {
    await pumpScene(tester, const WorkoutScene(), api: FakeApiClient(latency: Duration.zero), size: phoneScreen);
    for (final tab in ['library', 'stats', 'log']) {
      await openTab(tester, tab);
      expect(tester.takeException(), isNull, reason: tab);
    }
  });
}
