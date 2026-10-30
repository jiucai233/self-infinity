import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import 'left_panel.dart';
import 'stage_scaffold.dart';

/// `/me`, the phone's Me tab: the left panel “My character” (character sheet,
/// stats, daily quests, today, ◎ settings) as a page of its own. Wide screens
/// show that panel next to every scene, so there this page goes home.
class MeScene extends StatelessWidget {
  const MeScene({super.key});

  @override
  Widget build(BuildContext context) {
    if (AppLayout.isWide(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(AppRoutes.home);
      });
      return const ColoredBox(color: AppColors.canvas);
    }
    return StageScaffold(title: context.l10n.myCharacter, stage: const LeftPanel());
  }
}
