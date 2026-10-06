/// All routes of the app (`docs/ux-chat.md`).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/audit/audit_scene.dart';
import '../features/chat/home_scene.dart';
import '../features/map/map_scene.dart';
import '../features/skill/skill_scene.dart';
import '../widgets/widgets.dart';

/// Path helpers, so that no screen has to spell a route by hand.
///
/// | Path | Screen | Scene |
/// |---|---|---|
/// | `/` | `HomeScene` | 1 entering, becomes 5 chat after the first message |
/// | `/map` | `MapScene` | 2 skill graph |
/// | `/skill/:id` | `SkillScene` | 4 node overview |
/// | `/skill/:id/audit` | `AuditScene` | 4-1 audit |
///
/// Every scene is reached with `context.go(...)`; there are no other pages.
abstract final class AppRoutes {
  static const String home = '/';
  static const String map = '/map';

  /// `/skill/<skillId>`.
  static String skill(int skillId) => '/skill/$skillId';

  /// `/skill/<skillId>/audit`.
  static String audit(int skillId) => '/skill/$skillId/audit';
}

/// How deep a scene is: going to a deeper one (home -> map -> node -> audit)
/// slides up into place, going back slides down (`docs/ux-chat.md` 5.6).
int _depthOf(Uri uri) {
  final segments = uri.pathSegments;
  if (segments.isEmpty) return 0;
  if (segments.first == 'map') return 1;
  return segments.length >= 3 ? 3 : 2;
}

/// How long a scene change takes (instant while [Avatar.animationsEnabled] is
/// off, as in widget tests).
const Duration kSceneTransition = Duration(milliseconds: 220);

/// A scene appears with a fade and a slight slide (about 220 ms); [forward] is
/// false when it was reached by going back, then it slides the other way.
Page<void> _scenePage(GoRouterState state, Widget child, {required bool forward}) {
  final slide = Tween<Offset>(
    begin: Offset(0, forward ? 0.02 : -0.02),
    end: Offset.zero,
  ).chain(CurveTween(curve: Curves.easeOutCubic));
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: Avatar.animationsEnabled ? kSceneTransition : Duration.zero,
    reverseTransitionDuration: Avatar.animationsEnabled ? kSceneTransition : Duration.zero,
    transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: SlideTransition(position: animation.drive(slide), child: child),
    ),
  );
}

/// Builds the router. [initialLocation] overrides the start page (tests, deep
/// links).
GoRouter createRouter({String? initialLocation}) {
  var lastDepth = _depthOf(Uri.parse(initialLocation ?? AppRoutes.home));
  Page<void> page(GoRouterState state, Widget child) {
    final depth = _depthOf(state.uri);
    final forward = depth >= lastDepth;
    lastDepth = depth;
    return _scenePage(state, child, forward: forward);
  }

  return GoRouter(
    initialLocation: initialLocation ?? AppRoutes.home,
    errorBuilder: (context, state) => NotFoundScreen(location: state.uri.toString()),
    routes: [
      GoRoute(
        path: AppRoutes.home,
        pageBuilder: (context, state) => page(state, const HomeScene()),
      ),
      GoRoute(
        path: AppRoutes.map,
        pageBuilder: (context, state) => page(state, const MapScene()),
      ),
      GoRoute(
        path: '/skill/:skillId',
        pageBuilder: (context, state) {
          final skillId = int.tryParse(state.pathParameters['skillId'] ?? '');
          if (skillId == null) {
            return page(state, NotFoundScreen(location: state.uri.toString()));
          }
          return page(state, SkillScene(key: ValueKey('skill-$skillId'), skillId: skillId));
        },
      ),
      GoRoute(
        path: '/skill/:skillId/audit',
        pageBuilder: (context, state) {
          final skillId = int.tryParse(state.pathParameters['skillId'] ?? '');
          if (skillId == null) {
            return page(state, NotFoundScreen(location: state.uri.toString()));
          }
          return page(state, AuditScene(key: ValueKey('audit-$skillId'), skillId: skillId));
        },
      ),
    ],
  );
}

/// Shown for an unknown route or an invalid path parameter.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key, required this.location});

  /// The location that could not be shown.
  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Self-Infinity')),
      body: EmptyView(
        message: 'Page not found',
        action: PrimaryButton(
          label: 'Go home',
          onPressed: () => GoRouter.of(context).go(AppRoutes.home),
        ),
      ),
    );
  }
}
