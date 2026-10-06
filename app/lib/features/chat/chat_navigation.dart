import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../app/router.dart';

/// Carries out the first `navigate` action among the assistant [messages] of a
/// chat answer (`docs/api-contract.md` Section 5): switch to the skill graph or
/// to a node's overview.
///
/// Returns whether the scene was switched.
bool followNavigation(BuildContext context, Iterable<ChatMessage> messages) {
  for (final m in messages) {
    final action = m.action;
    if (action is! NavigateAction) continue;
    switch (action.scene) {
      case NavScene.map:
        context.go(AppRoutes.map);
        return true;
      case NavScene.skill:
        final id = action.skillId;
        if (id == null) continue;
        context.go(AppRoutes.skill(id));
        return true;
    }
  }
  return false;
}
