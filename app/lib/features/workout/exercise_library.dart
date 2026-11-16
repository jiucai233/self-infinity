/// The exercise library bundled with the app (`assets/exercises/`, built from
/// free-exercise-db by `tool/exercise_library.py`): about 120 movements with
/// names and steps in en / ko / zh, the body part, the equipment, and two
/// frames of the movement.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../api/models.dart';

/// Where on the body a movement works; how the library is browsed.
enum BodyPart {
  chest,
  back,
  shoulders,
  arms,
  legs,
  core,
  cardio,
  stretch;

  static BodyPart fromJson(Object? v) => values.firstWhere((b) => b.name == v, orElse: () => BodyPart.core);
}

/// What a movement is done with.
enum Equipment {
  body,
  dumbbell,
  barbell,
  machine,
  cable,
  kettlebell,
  band,
  other;

  static Equipment fromJson(Object? v) => values.firstWhere((e) => e.name == v, orElse: () => Equipment.other);
}

/// One movement of the library.
@immutable
class LibraryExercise {
  const LibraryExercise({
    required this.id,
    required this.names,
    required this.body,
    required this.category,
    required this.equipment,
    required this.level,
    required this.muscles,
    required this.unit,
    required this.steps,
    required this.images,
    this.catalog,
  });

  factory LibraryExercise.fromJson(Map<String, dynamic> j) {
    Map<String, String> strings(Object? v) => {
      if (v is Map)
        for (final e in v.entries) '${e.key}': '${e.value}',
    };
    Map<String, List<String>> lists(Object? v) => {
      if (v is Map)
        for (final e in v.entries) '${e.key}': [for (final s in (e.value as List? ?? const [])) '$s'],
    };
    return LibraryExercise(
      id: '${j['id']}',
      names: strings(j['name']),
      body: BodyPart.fromJson(j['body']),
      category: WorkoutCategory.fromJson(j['category']),
      equipment: Equipment.fromJson(j['equipment']),
      level: '${j['level'] ?? ''}',
      muscles: [for (final m in (j['muscles'] as List? ?? const [])) '$m'],
      unit: WorkoutUnit.fromJson(j['unit']),
      steps: lists(j['steps']),
      images: [for (final i in (j['images'] as List? ?? const [])) 'assets/exercises/img/$i'],
      catalog: j['catalog'] as String?,
    );
  }

  final String id;
  final Map<String, String> names;
  final BodyPart body;
  final WorkoutCategory category;
  final Equipment equipment;
  final String level;
  final List<String> muscles;
  final WorkoutUnit unit;
  final Map<String, List<String>> steps;

  /// Asset paths of the frames, in order.
  final List<String> images;

  /// The key of the server's quick-log catalog for the same movement.
  final String? catalog;

  String name(String language) => names[language] ?? names['en'] ?? id;
  List<String> stepsIn(String language) => steps[language] ?? steps['en'] ?? const [];

  /// Whether [text] is one of its names (any language), ignoring case.
  bool isCalled(String text) {
    final t = text.trim().toLowerCase();
    return names.values.any((n) => n.toLowerCase() == t);
  }
}

/// The whole library, loaded once.
class ExerciseLibrary {
  ExerciseLibrary(this.exercises);

  final List<LibraryExercise> exercises;

  static const String asset = 'assets/exercises/library.json';

  static Future<ExerciseLibrary>? _loading;

  /// Tests set a library of their own (or an empty one).
  @visibleForTesting
  static ExerciseLibrary? debugOverride;

  /// Reads the bundled library (cached); an empty one when it cannot be read.
  static Future<ExerciseLibrary> load() {
    final override = debugOverride;
    if (override != null) return Future.value(override);
    return _loading ??= () async {
      try {
        final raw = jsonDecode(await rootBundle.loadString(asset));
        return ExerciseLibrary([
          for (final e in raw as List)
            if (e is Map) LibraryExercise.fromJson(Map<String, dynamic>.from(e)),
        ]);
      } on Object catch (e) {
        debugPrint('exercise library unavailable: $e');
        return ExerciseLibrary(const []);
      }
    }();
  }

  /// The movement a logged workout is, by its catalog key or its name.
  LibraryExercise? of(Workout w) => find(key: w.exerciseKey, name: w.exercise);

  LibraryExercise? find({String? key, String? name}) {
    if (key != null) {
      final byKey = exercises.where((e) => e.catalog == key).firstOrNull;
      if (byKey != null) return byKey;
    }
    if (name == null) return null;
    return exercises.where((e) => e.isCalled(name)).firstOrNull;
  }
}
