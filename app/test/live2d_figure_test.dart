// Live2DFigure: the fallback off the web, and the messages it sends the model.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/widgets/avatar.dart';
import 'package:self_infinity/widgets/live2d_figure.dart';

const _fallback = Text('fallback', textDirection: TextDirection.ltr);
const _view = Key('live2d-view');

class _FakeHost implements Live2DHost {
  _FakeHost(this.config);

  final Live2DHostConfig config;
  final List<Map<String, Object?>> sent = [];
  bool disposed = false;

  @override
  Widget get view => const SizedBox(key: _view);

  @override
  void send(Map<String, Object?> message) => sent.add(message);

  @override
  void dispose() => disposed = true;
}

Widget _figure({
  AvatarMood mood = AvatarMood.neutral,
  AvatarState state = AvatarState.idle,
  bool wave = false,
  Key? key,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: Live2DFigure(key: key, mood: mood, state: state, wave: wave, fallback: _fallback),
  ),
);

void main() {
  tearDown(() => Live2DFigure.debugHostFactory = null);

  testWidgets('off the web it shows the fallback, at the avatar box size', (tester) async {
    await tester.pumpWidget(_figure());
    expect(find.text('fallback'), findsOneWidget);
    expect(find.byKey(_view), findsNothing);
    final size = tester.getSize(find.byType(Live2DFigure));
    expect(size, const Size(160 * Avatar.aspect, 160));
  });

  testWidgets('messages wait for ready; then the latest mood and state go out', (tester) async {
    late _FakeHost host;
    Live2DFigure.debugHostFactory = (config) => host = _FakeHost(config);

    await tester.pumpWidget(_figure());
    expect(find.text('fallback'), findsOneWidget);
    expect(find.byKey(_view), findsOneWidget);
    expect(host.sent, isEmpty);

    await tester.pumpWidget(_figure(mood: AvatarMood.stern, state: AvatarState.thinking));
    await tester.pumpWidget(_figure(mood: AvatarMood.angry, state: AvatarState.thinking, wave: true));
    expect(host.sent, isEmpty);

    host.config.onReady();
    await tester.pump();
    expect(find.text('fallback'), findsNothing);
    expect(host.sent, [
      {'type': 'state', 'state': 'thinking'},
      {'type': 'mood', 'mood': 'angry'},
      {'type': 'wave'},
    ]);
  });

  testWidgets('after ready each change is one message', (tester) async {
    late _FakeHost host;
    Live2DFigure.debugHostFactory = (config) => host = _FakeHost(config);
    final key = GlobalKey<Live2DFigureState>();

    await tester.pumpWidget(_figure(key: key));
    host.config.onReady();
    await tester.pump();
    expect(host.sent, [
      {'type': 'mood', 'mood': 'neutral'},
      {'type': 'state', 'state': 'idle'},
    ]);
    host.sent.clear();

    await tester.pumpWidget(_figure(key: key, mood: AvatarMood.happy));
    await tester.pumpWidget(_figure(key: key, mood: AvatarMood.happy, state: AvatarState.speaking));
    await tester.pumpWidget(_figure(key: key, mood: AvatarMood.happy, state: AvatarState.speaking));
    await tester.pumpWidget(_figure(key: key, mood: AvatarMood.happy, wave: true));
    await tester.pumpWidget(_figure(key: key, mood: AvatarMood.happy, wave: true));
    key.currentState!.react('surprised');
    expect(host.sent, [
      {'type': 'mood', 'mood': 'happy'},
      {'type': 'state', 'state': 'speaking'},
      {'type': 'state', 'state': 'idle'},
      {'type': 'wave'},
      {'type': 'react', 'kind': 'surprised'},
    ]);
  });

  testWidgets('an error brings the fallback back and drops the host', (tester) async {
    late _FakeHost host;
    Live2DFigure.debugHostFactory = (config) => host = _FakeHost(config);

    await tester.pumpWidget(_figure());
    host.config.onReady();
    await tester.pump();
    expect(find.text('fallback'), findsNothing);

    host.config.onError('no WebGL');
    await tester.pump();
    expect(find.text('fallback'), findsOneWidget);
    expect(find.byKey(_view), findsNothing);
    expect(host.disposed, isTrue);

    host.sent.clear();
    await tester.pumpWidget(_figure(mood: AvatarMood.angry));
    expect(host.sent, isEmpty);
  });

  testWidgets('an error before ready keeps the fallback', (tester) async {
    late _FakeHost host;
    Live2DFigure.debugHostFactory = (config) => host = _FakeHost(config);

    await tester.pumpWidget(_figure());
    host.config.onError('timeout');
    host.config.onReady();
    await tester.pump();
    expect(find.text('fallback'), findsOneWidget);
    expect(host.sent, isEmpty);
  });
}
