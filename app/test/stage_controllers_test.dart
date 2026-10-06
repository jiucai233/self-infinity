// StageController (facts, today, mini tree) and ChatController.
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/api/fake_api.dart';
import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/app/app_state.dart';
import 'package:self_infinity/features/chat/chat_controller.dart';
import 'package:self_infinity/features/stage/stage_controller.dart';
import 'package:self_infinity/testing/test_app.dart';

void main() {
  group('StageController', () {
    test('loads facts, today’s check-in and the course map; reloads on data changes', () async {
      final api = await seededFakeApi();
      final state = AppState();
      final stage = StageController(api: api, appState: state);
      expect(stage.loaded, isFalse);
      await pumpEventQueue();
      expect(stage.loaded, isTrue);
      expect(stage.facts!.nodes.total, 12);
      expect(stage.todayCheckIn, isNull);
      expect(stage.courseMap!.nodes, hasLength(12));

      await api.checkInVoice('I slept six hours last night.');
      await passAudit(api, 1);
      state.markDataChanged();
      await pumpEventQueue();
      expect(stage.todayCheckIn!.sleepHours, 6);
      expect(stage.facts!.nodes.mastered, 1);
      expect(stage.courseMap!.nodeById(1)!.isMastered, isTrue);
      stage.dispose();
    });

    test('the map is always that of the newest course', () async {
      final api = await seededFakeApi();
      await api.generateCourse(const GenerateRequest(topic: 'reinforcement learning'));
      final stage = StageController(api: api, appState: AppState());
      await pumpEventQueue();
      expect(stage.courseMap!.course.id, 2);
      stage.dispose();
    });

    test('no course: no map; failures only leave their part empty', () async {
      final api = FakeApiClient(latency: Duration.zero);
      api.failNext(method: 'getBriefing');
      final stage = StageController(api: api, appState: AppState());
      await pumpEventQueue();
      expect(stage.loaded, isTrue);
      expect(stage.facts, isNull);
      expect(stage.courseMap, isNull);
      stage.dispose();
    });

    test('an old result never overwrites a newer one', () async {
      final api = await seededFakeApi();
      final state = AppState();
      final stage = StageController(api: api, appState: state);
      state.markDataChanged();
      state.markDataChanged();
      await pumpEventQueue();
      expect(stage.loaded, isTrue);
      stage.dispose();
    });
  });

  group('ChatController', () {
    late FakeApiClient api;
    late AppState state;
    late ChatController chat;

    setUp(() async {
      api = await seededFakeApi();
      state = AppState();
      chat = ChatController(api: api, appState: state);
    });

    tearDown(() => chat.dispose());

    test('loadHistory loads once', () async {
      await api.sendChat('first thing said');
      await chat.loadHistory();
      expect(chat.historyLoaded, isTrue);
      expect(chat.messages.first.content, 'first thing said');
      final count = chat.messages.length;
      await api.sendChat('second thing said');
      await chat.loadHistory();
      expect(chat.messages, hasLength(count));
    });

    test('a failing history can be retried', () async {
      api.failNext(method: 'getChatHistory');
      await chat.loadHistory();
      expect(chat.messages, isEmpty);
      await chat.loadHistory();
      expect(chat.historyLoaded, isTrue);
    });

    test('send: optimistic user message, then the saved ones', () async {
      final future = chat.send('Hello there');
      expect(chat.sending, isTrue);
      expect(chat.messages.single.id, lessThan(0)); // pending
      final saved = await future;
      expect(chat.sending, isFalse);
      expect(saved, hasLength(2));
      expect(chat.messages.map((m) => m.id), [1, 2]);
      expect(chat.lastAssistant!.content, 'Sure. What would you like to do today?');
      expect(chat.error, isNull);
    });

    test('a history that is still loading never doubles what was sent meanwhile', () async {
      // The history is read after the message was saved, but arrives while the
      // send is still being answered.
      final history = chat.loadHistory();
      final sent = chat.send('Hello there');
      await Future.wait([history, sent]);
      expect(chat.messages.map((m) => m.id).toSet(), hasLength(chat.messages.length));
      expect(chat.messages.where((m) => m.isUser), hasLength(1));
      expect(chat.messages.where((m) => !m.isUser), hasLength(1));
    });

    test('a history read before the send finished keeps the new lines', () async {
      final history = chat.loadHistory();
      final saved = await chat.send('Hello there');
      await history;
      expect(chat.messages.map((m) => m.id), containsAll(saved!.map((m) => m.id)));
    });

    test('send ignores blanks and a message while one is in flight', () async {
      expect(await chat.send('   '), isNull);
      final first = chat.send('one');
      expect(await chat.send('two'), isNull);
      await first;
      expect((await api.getChatHistory()).where((m) => m.isUser), hasLength(1));
    });

    test('send passes the upload ids on', () async {
      final up = await api.uploadFile(filename: 'course.md', bytes: [65, 66]);
      final saved = await chat.send('I want to learn this', uploadIds: [up.id]);
      final course = saved!.map((m) => m.action).whereType<CourseAction>().single.course;
      expect(course.sourceCourse, 'course.md');
    });

    test('a failure removes the pending message and keeps the error', () async {
      api.failNext(method: 'sendChat');
      expect(await chat.send('Hello there'), isNull);
      expect(chat.messages, isEmpty);
      expect(chat.error, 'Something went wrong on our side. Please try again.');
      expect(chat.sending, isFalse);
      await chat.send('again');
      expect(chat.error, isNull);
    });

    test('a checkin or course action signals a data change', () async {
      var revision = state.dataRevision;
      await chat.send('I slept six hours last night');
      expect(state.dataRevision, greaterThan(revision));

      revision = state.dataRevision;
      await chat.send('I want to study reinforcement learning');
      expect(state.dataRevision, greaterThan(revision));
    });

    test('plain answers change no data', () async {
      final revision = state.dataRevision;
      await chat.send('Hello there');
      expect(state.dataRevision, revision);
    });

    test('a new study plan signals a data change (the daily quests)', () async {
      await api.generateCourse(const GenerateRequest(topic: 'math'));
      final revision = state.dataRevision;
      await chat.send('What should I do today?');
      expect(state.dataRevision, greaterThan(revision));
    });

    test('loadSuggestions, and a failure gives an empty list', () async {
      await chat.loadSuggestions();
      expect(chat.suggestions.first.label, 'How was your day?');
      expect(chat.suggestions, hasLength(2));
      api.failNext(method: 'getChatSuggestions');
      await chat.loadSuggestions();
      expect(chat.suggestions, isEmpty);
    });
  });
}
