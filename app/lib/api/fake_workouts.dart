/// The workout log of the in-memory [FakeApiClient] (contract #54): a small
/// catalog in three languages, records, routines, the summary and a rule
/// reader for a said line — the same shapes and rules as the server, kept
/// simple.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'api_exception.dart';
import 'models.dart';

/// (key, category, unit, en, zh, ko, aliases).
typedef _Entry = (String, WorkoutCategory, WorkoutUnit, String, String, String, List<String>);

const List<_Entry> _catalog = [
  ('squat', WorkoutCategory.strength, WorkoutUnit.reps, 'Squat', '深蹲', '스쿼트', ['squats']),
  ('push_up', WorkoutCategory.strength, WorkoutUnit.reps, 'Push-up', '俯卧撑', '푸시업', ['pushups', 'push-ups', '팔굽혀펴기']),
  ('pull_up', WorkoutCategory.strength, WorkoutUnit.reps, 'Pull-up', '引体向上', '풀업', ['pullups', '턱걸이']),
  ('bench_press', WorkoutCategory.strength, WorkoutUnit.reps, 'Bench press', '卧推', '벤치프레스', ['bench']),
  ('deadlift', WorkoutCategory.strength, WorkoutUnit.reps, 'Deadlift', '硬拉', '데드리프트', []),
  ('lunge', WorkoutCategory.strength, WorkoutUnit.reps, 'Lunge', '弓步蹲', '런지', ['lunges']),
  ('plank', WorkoutCategory.strength, WorkoutUnit.time, 'Plank', '平板支撑', '플랭크', []),
  ('running', WorkoutCategory.cardio, WorkoutUnit.distance, 'Running', '跑步', '러닝', ['run', 'ran', '런닝', '달리기']),
  ('walking', WorkoutCategory.cardio, WorkoutUnit.distance, 'Walking', '散步', '걷기', ['walk', '산책']),
  ('cycling', WorkoutCategory.cardio, WorkoutUnit.distance, 'Cycling', '骑车', '자전거', ['bike', '骑自行车']),
  ('swimming', WorkoutCategory.cardio, WorkoutUnit.time, 'Swimming', '游泳', '수영', ['swim']),
  ('jump_rope', WorkoutCategory.cardio, WorkoutUnit.time, 'Jump rope', '跳绳', '줄넘기', []),
  ('stretching', WorkoutCategory.flexibility, WorkoutUnit.time, 'Stretching', '拉伸', '스트레칭', ['stretch']),
  ('yoga', WorkoutCategory.flexibility, WorkoutUnit.time, 'Yoga', '瑜伽', '요가', []),
  ('basketball', WorkoutCategory.sports, WorkoutUnit.time, 'Basketball', '篮球', '농구', []),
  ('soccer', WorkoutCategory.sports, WorkoutUnit.time, 'Soccer', '足球', '축구', ['football']),
  ('badminton', WorkoutCategory.sports, WorkoutUnit.time, 'Badminton', '羽毛球', '배드민턴', []),
];

/// The fake's workouts and routines.
class FakeWorkoutStore {
  FakeWorkoutStore({required this.clock, required this.language});

  final DateTime Function() clock;
  final String language;

  final List<Workout> _workouts = [];
  final List<Routine> _routines = [];
  int _nextWorkout = 1;
  int _nextRoutine = 1;

  String get today => formatKstDate(clock());

  String _name(_Entry e) => switch (language) {
    'zh' => e.$5,
    'ko' => e.$6,
    _ => e.$4,
  };

  WorkoutCatalog catalog() => WorkoutCatalog(
    categories: WorkoutCategory.values,
    exercises: [
      for (final e in _catalog) CatalogExercise(key: e.$1, name: _name(e), category: e.$2, unit: e.$3),
    ],
  );

  _Entry? _entry(String? key) => key == null ? null : _catalog.where((e) => e.$1 == key).firstOrNull;

  /// The catalog entry a typed name means, if any.
  _Entry? _match(String name) {
    final n = name.trim().toLowerCase();
    for (final e in _catalog) {
      if ([e.$4, e.$5, e.$6, ...e.$7].any((w) => w.toLowerCase() == n)) return e;
    }
    return null;
  }

  static void _check(WorkoutAmount a, String exercise) {
    void require(bool ok, String what) {
      if (!ok) throw ApiException(422, what);
    }

    require(exercise.trim().isNotEmpty && exercise.trim().length <= 40, 'exercise must be 1-40 characters');
    require(!a.isEmpty, 'set at least one of sets, reps, duration_min, distance_km');
    require(a.sets == null || (a.sets! >= 1 && a.sets! <= 50), 'sets must be 1-50');
    require(a.reps == null || (a.reps! >= 1 && a.reps! <= 1000), 'reps must be 1-1000');
    require(a.weightKg == null || (a.weightKg! >= 0 && a.weightKg! <= 500), 'weight_kg must be 0-500');
    require(a.durationMin == null || (a.durationMin! >= 1 && a.durationMin! <= 600), 'duration_min must be 1-600');
    require(
      a.distanceKm == null || (a.distanceKm! >= 0.1 && a.distanceKm! <= 300),
      'distance_km must be 0.1-300',
    );
  }

  Workout _make(
    WorkoutDraft d, {
    required int id,
    WorkoutSource source = WorkoutSource.manual,
    int? routineId,
    int? routineItem,
    DateTime? createdAt,
  }) {
    _check(d.amount, d.exercise);
    final entry = _entry(d.exerciseKey) ?? _match(d.exercise);
    return Workout(
      id: id,
      date: d.date,
      exercise: d.exercise.trim(),
      exerciseKey: entry?.$1,
      category: d.category ?? entry?.$2 ?? WorkoutCategory.other,
      amount: d.amount,
      note: (d.note?.trim().isEmpty ?? true) ? null : d.note!.trim(),
      source: source,
      routineId: routineId,
      routineItem: routineItem,
      createdAt: createdAt ?? clock(),
    );
  }

  List<Workout> list({String? from, String? to}) {
    final end = to ?? today;
    final start = from ?? formatKstDate(clock().subtract(const Duration(days: 29)));
    final out = [
      for (final w in _workouts)
        if (w.date.compareTo(start) >= 0 && w.date.compareTo(end) <= 0) w,
    ];
    out.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
    return out;
  }

  Workout create(WorkoutDraft d, {WorkoutSource source = WorkoutSource.manual}) {
    final w = _make(d, id: _nextWorkout, source: source);
    _nextWorkout++;
    _workouts.add(w);
    return w;
  }

  Workout update(int id, WorkoutDraft d) {
    final i = _workouts.indexWhere((w) => w.id == id);
    if (i < 0) throw const ApiException(404, 'workout not found');
    final old = _workouts[i];
    final w = _make(
      d,
      id: id,
      source: old.source,
      routineId: old.routineId,
      routineItem: old.routineItem,
      createdAt: old.createdAt,
    );
    _workouts[i] = w;
    return w;
  }

  void delete(int id) {
    final before = _workouts.length;
    _workouts.removeWhere((w) => w.id == id);
    if (_workouts.length == before) throw const ApiException(404, 'workout not found');
  }

  // -- a said line ------------------------------------------------------------

  static final RegExp _split = RegExp(r'[,，、;\n]| and | 그리고 | 하고 |和');
  static final RegExp _setsReps = RegExp(r'(\d+)\s*[x×]\s*(\d+)');
  static final RegExp _sets = RegExp(r'(\d+)\s*(?:세트|sets?|组)', caseSensitive: false);
  static final RegExp _reps = RegExp(r'(\d+)\s*(?:회|개|reps?|次|个)', caseSensitive: false);
  static final RegExp _kg = RegExp(r'(\d+(?:\.\d+)?)\s*(?:kg|킬로|公斤)', caseSensitive: false);
  static final RegExp _km = RegExp(r'(\d+(?:\.\d+)?)\s*(?:km|키로|公里)', caseSensitive: false);
  static final RegExp _min = RegExp(r'(\d+)\s*(?:분|min(?:utes?)?|分钟)', caseSensitive: false);
  static final RegExp _hour = RegExp(r'(\d+)\s*(?:시간|hours?|小时)', caseSensitive: false);
  static final RegExp _yesterday = RegExp(r'어제|yesterday|昨天', caseSensitive: false);

  WorkoutSaid say(String text, {String? date}) {
    if (text.trim().isEmpty || text.length > 300) throw const ApiException(422, 'text must be 1-300 characters');
    var day = date ?? today;
    if (_yesterday.hasMatch(text)) {
      day = formatKstDate(DateTime.parse(day).add(const Duration(hours: 12)).subtract(const Duration(days: 1)));
    }
    final saved = <Workout>[];
    final unread = <String>[];
    for (final raw in text.split(_split)) {
      final piece = raw.trim();
      if (piece.isEmpty) continue;
      final amount = _amountOf(piece);
      final entry = _findIn(piece);
      if (amount == null || amount.isEmpty) {
        unread.add(piece);
        continue;
      }
      final name = entry == null ? _words(piece) : _name(entry);
      if (name.isEmpty) {
        unread.add(piece);
        continue;
      }
      try {
        saved.add(
          create(
            WorkoutDraft(date: day, exercise: name, exerciseKey: entry?.$1, amount: amount),
            source: WorkoutSource.said,
          ),
        );
      } on ApiException {
        unread.add(piece);
      }
    }
    return WorkoutSaid(workouts: saved, unread: unread);
  }

  _Entry? _findIn(String piece) {
    final lower = piece.toLowerCase();
    _Entry? best;
    var bestLength = 0;
    for (final e in _catalog) {
      for (final w in [e.$4, e.$5, e.$6, ...e.$7]) {
        if (w.length > bestLength && lower.contains(w.toLowerCase())) {
          best = e;
          bestLength = w.length;
        }
      }
    }
    return best;
  }

  /// The piece without its numbers and filler words: a name the catalog
  /// does not know.
  static String _words(String piece) => piece
      .replaceAll(RegExp(r'\d+(?:\.\d+)?\s*[a-zA-Z가-힣一-龥]*'), ' ')
      .replaceAll(RegExp(r'오늘|어제|했어요?|했다|today|yesterday|did|今天|昨天', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  WorkoutAmount? _amountOf(String piece) {
    int? sets;
    int? reps;
    final sr = _setsReps.firstMatch(piece);
    if (sr != null) {
      sets = int.parse(sr.group(1)!);
      reps = int.parse(sr.group(2)!);
    }
    sets ??= int.tryParse(_sets.firstMatch(piece)?.group(1) ?? '');
    reps ??= int.tryParse(_reps.firstMatch(piece)?.group(1) ?? '');
    final kg = double.tryParse(_kg.firstMatch(piece)?.group(1) ?? '');
    final km = double.tryParse(_km.firstMatch(piece)?.group(1) ?? '');
    var minutes = int.tryParse(_min.firstMatch(piece)?.group(1) ?? '');
    final hours = int.tryParse(_hour.firstMatch(piece)?.group(1) ?? '');
    if (hours != null) minutes = (minutes ?? 0) + hours * 60;
    final entry = _findIn(piece);
    if (sets == null && reps == null && minutes == null && km == null && entry != null && entry.$3 != WorkoutUnit.reps) {
      // A time exercise with a bare number: minutes.
      minutes = int.tryParse(RegExp(r'(\d+)').firstMatch(piece)?.group(1) ?? '');
    }
    return WorkoutAmount(sets: sets, reps: reps, weightKg: kg, durationMin: minutes, distanceKm: km);
  }

  // -- summary ----------------------------------------------------------------

  WorkoutSummary summary({int days = 7}) {
    if (!const {7, 30, 90}.contains(days)) throw const ApiException(422, 'days must be 7, 30 or 90');
    final todayDate = DateTime.parse(today);
    String dayAt(int back) => formatKstDate(todayDate.add(const Duration(hours: 12)).subtract(Duration(days: back)));
    final active = {for (final w in _workouts) w.date};
    var streak = 0;
    var back = active.contains(today) ? 0 : 1;
    while (active.contains(dayAt(back))) {
      streak++;
      back++;
    }
    var best = 0;
    var run = 0;
    final sorted = active.toList()..sort();
    DateTime? previous;
    for (final d in sorted) {
      final t = DateTime.parse(d);
      run = previous != null && t.difference(previous).inHours.abs() <= 25 ? run + 1 : 1;
      if (run > best) best = run;
      previous = t;
    }
    final window = [for (var i = days - 1; i >= 0; i--) dayAt(i)];
    final inWindow = _workouts.where((w) => w.date.compareTo(window.first) >= 0 && w.date.compareTo(today) <= 0);
    final byCategory = <WorkoutCategory, int>{};
    for (final w in inWindow) {
      byCategory[w.category] = (byCategory[w.category] ?? 0) + 1;
    }
    var fullDays = 0;
    for (final d in active) {
      for (final r in _routineDay(d)) {
        if (r.done) fullDays++;
      }
    }
    return WorkoutSummary(
      days: days,
      streak: streak,
      bestStreak: best,
      xp: _workouts.length * 10 + fullDays * 20,
      totalMinutes: inWindow.fold(0, (sum, w) => sum + (w.amount.durationMin ?? 0)),
      workouts: inWindow.length,
      byCategory: byCategory,
      byDay: [
        for (final d in window)
          WorkoutDay(
            date: d,
            minutes: _workouts.where((w) => w.date == d).fold(0, (s, w) => s + (w.amount.durationMin ?? 0)),
            workouts: _workouts.where((w) => w.date == d).length,
          ),
      ],
    );
  }

  // -- export / import --------------------------------------------------------

  static const List<String> _columns = [
    'date',
    'exercise',
    'category',
    'sets',
    'reps',
    'weight_kg',
    'duration_min',
    'distance_km',
    'note',
  ];

  /// CSV for both formats (the fake writes no spreadsheet).
  Uint8List export(String format) {
    if (format != 'csv' && format != 'xlsx') throw const ApiException(422, 'format must be csv or xlsx');
    String cell(Object? v) {
      final s = v == null ? '' : '$v';
      return s.contains(RegExp('[,"\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final rows = [
      _columns.join(','),
      for (final w in list(from: '0000-01-01', to: '9999-12-31').reversed)
        [
          w.date,
          w.exercise,
          w.category.name,
          w.amount.sets,
          w.amount.reps,
          w.amount.weightKg,
          w.amount.durationMin,
          w.amount.distanceKm,
          w.note,
        ].map(cell).join(','),
    ];
    return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('${rows.join('\n')}\n')]);
  }

  WorkoutImport import(String filename, List<int> bytes) {
    if (!filename.toLowerCase().endsWith('.csv')) {
      throw const ApiException(422, 'the offline demo reads .csv files only');
    }
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    final lines = const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty || lines.first.split(',').first.trim() != 'date') {
      throw const ApiException(422, 'the file needs the header row');
    }
    var imported = 0;
    var skipped = 0;
    final errors = <({int row, String reason})>[];
    for (var i = 1; i < lines.length; i++) {
      final c = lines[i].split(',');
      String? at(int k) => k < c.length && c[k].trim().isNotEmpty ? c[k].trim() : null;
      try {
        final date = at(0) ?? '';
        if (DateTime.tryParse(date) == null) throw const ApiException(422, 'bad date');
        final draft = WorkoutDraft(
          date: date,
          exercise: at(1) ?? '',
          category: at(2) == null ? null : WorkoutCategory.fromJson(at(2)),
          amount: WorkoutAmount(
            sets: int.tryParse(at(3) ?? ''),
            reps: int.tryParse(at(4) ?? ''),
            weightKg: double.tryParse(at(5) ?? ''),
            durationMin: int.tryParse(at(6) ?? ''),
            distanceKm: double.tryParse(at(7) ?? ''),
          ),
          note: at(8),
        );
        final same = _workouts.any((w) => w.date == draft.date && w.exercise == draft.exercise && w.amount == draft.amount);
        if (same) {
          skipped++;
          continue;
        }
        create(draft, source: WorkoutSource.import);
        imported++;
      } on ApiException catch (e) {
        errors.add((row: i + 1, reason: e.serverMessage ?? "invalid row"));
      }
    }
    return WorkoutImport(imported: imported, skipped: skipped, errors: errors);
  }

  // -- routines ---------------------------------------------------------------

  void _checkRoutine(RoutineDraft d) {
    if (d.name.trim().isEmpty || d.name.trim().length > Routine.maxName) {
      throw const ApiException(422, 'name must be 1-30 characters');
    }
    if (d.weekdays.isEmpty || d.weekdays.any((w) => w < 0 || w > 6)) {
      throw const ApiException(422, 'weekdays must be 0-6, at least one');
    }
    if (d.items.isEmpty || d.items.length > Routine.maxItems) throw const ApiException(422, '1-12 items');
    for (final i in d.items) {
      _check(i.amount, i.exercise);
    }
  }

  RoutineItem _item(RoutineItem i) {
    final entry = _entry(i.exerciseKey) ?? _match(i.exercise);
    return RoutineItem(
      exercise: i.exercise.trim(),
      exerciseKey: entry?.$1,
      category: i.category ?? entry?.$2 ?? WorkoutCategory.other,
      amount: i.amount,
    );
  }

  List<Routine> routines() => List.unmodifiable(_routines);

  Routine createRoutine(RoutineDraft d) {
    _checkRoutine(d);
    final r = Routine(
      id: _nextRoutine++,
      name: d.name.trim(),
      weekdays: ([...d.weekdays.toSet()]..sort()),
      items: [for (final i in d.items) _item(i)],
      createdAt: clock(),
    );
    _routines.add(r);
    return r;
  }

  Routine updateRoutine(int id, RoutineDraft d) {
    _checkRoutine(d);
    final i = _routines.indexWhere((r) => r.id == id);
    if (i < 0) throw const ApiException(404, 'routine not found');
    final r = Routine(
      id: id,
      name: d.name.trim(),
      weekdays: ([...d.weekdays.toSet()]..sort()),
      items: [for (final it in d.items) _item(it)],
      createdAt: _routines[i].createdAt,
    );
    _routines[i] = r;
    return r;
  }

  void deleteRoutine(int id) {
    final before = _routines.length;
    _routines.removeWhere((r) => r.id == id);
    if (_routines.length == before) throw const ApiException(404, 'routine not found');
  }

  List<RoutineDay> _routineDay(String date) {
    final weekday = DateTime.parse(date).weekday - 1; // 0 = Monday
    return [
      for (final r in _routines)
        if (r.weekdays.contains(weekday))
          () {
            final items = [
              for (final (i, item) in r.items.indexed)
                RoutineDayItem(
                  index: i,
                  item: item,
                  workoutId: _workouts
                      .where((w) => w.routineId == r.id && w.routineItem == i && w.date == date)
                      .firstOrNull
                      ?.id,
                ),
            ];
            return RoutineDay(routine: r, items: items, done: items.every((i) => i.checked));
          }(),
    ];
  }

  List<RoutineDay> routineDay({String? date}) => _routineDay(date ?? today);

  Workout check(int routineId, int index, {String? date}) {
    final day = date ?? today;
    final r = _routines.where((r) => r.id == routineId).firstOrNull;
    if (r == null || index < 0 || index >= r.items.length) throw const ApiException(404, 'routine item not found');
    if (_workouts.any((w) => w.routineId == routineId && w.routineItem == index && w.date == day)) {
      throw const ApiException(409, 'already checked off that day');
    }
    final item = r.items[index];
    final w = _make(
      WorkoutDraft(
        date: day,
        exercise: item.exercise,
        exerciseKey: item.exerciseKey,
        category: item.category,
        amount: item.amount,
      ),
      id: _nextWorkout++,
      source: WorkoutSource.routine,
      routineId: routineId,
      routineItem: index,
    );
    _workouts.add(w);
    return w;
  }

  void uncheck(int routineId, int index, {String? date}) {
    final day = date ?? today;
    final before = _workouts.length;
    _workouts.removeWhere((w) => w.routineId == routineId && w.routineItem == index && w.date == day);
    if (_workouts.length == before) throw const ApiException(404, 'not checked off that day');
  }
}
