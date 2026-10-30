import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:self_infinity/api/models.dart';
import 'package:self_infinity/features/chat/chat_navigation.dart';

ChatMessage _message(NavigateAction action) => ChatMessage(
  id: 1,
  role: ChatRole.assistant,
  content: 'x',
  action: action,
  createdAt: DateTime.utc(2026, 10, 30),
);

void main() {
  testWidgets('a navigate action to an audit opens its replay', (tester) async {
    late BuildContext inner;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) {
            inner = context;
            return const Text('home');
          },
        ),
        GoRoute(path: '/audit/:auditId', builder: (_, state) => Text('replay ${state.pathParameters['auditId']}')),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    final moved = followNavigation(inner, [_message(const NavigateAction(scene: NavScene.audit, auditId: 31))]);
    await tester.pumpAndSettle();

    expect(moved, isTrue);
    expect(find.text('replay 31'), findsOneWidget);
  });

  testWidgets('an audit action without an id goes nowhere', (tester) async {
    late BuildContext inner;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) {
            inner = context;
            return const Text('home');
          },
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(followNavigation(inner, [_message(const NavigateAction(scene: NavScene.audit))]), isFalse);
  });
}
