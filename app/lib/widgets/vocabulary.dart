/// UI vocabulary (localized) and the colors that go with each enum value, so that
/// every screen says and colors the same thing the same way.
library;

import 'package:flutter/material.dart';

import '../api/graph_utils.dart';
import '../api/models.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';

/// The condition bar of the left panel: how full it is and what color.
extension ConditionFlagUi on ConditionFlag {
  /// normal fills the bar, low half, unknown nothing.
  double get fill => switch (this) {
    ConditionFlag.normal => 1,
    ConditionFlag.low => 0.5,
    ConditionFlag.unknown => 0,
  };

  /// Low is red; the others use the plain bar color.
  Color get color => switch (this) {
    ConditionFlag.low => AppColors.danger,
    _ => AppColors.primary,
  };

  /// `Good` · `Low` · `No record` (shown as `Condition: Good`).
  String label(AppLocalizations l) => switch (this) {
    ConditionFlag.normal => l.conditionGood,
    ConditionFlag.low => l.conditionLow,
    ConditionFlag.unknown => l.conditionNoRecord,
  };
}

/// Display names of the agents (the label in the history lists).
String agentLabel(AppLocalizations l, String? agent) => switch (agent) {
  'front_desk' => l.agentGuide,
  'narrator' => l.agentNarrator,
  'recommender' => l.agentRecommender,
  'planner' => l.agentPlanner,
  'clarifier' => l.agentClarifier,
  'syllabus_finder' => l.agentSyllabusFinder,
  'material_finder' => l.agentMaterialFinder,
  'auditor' => l.agentAuditor,
  'challenger' => l.agentChallenger,
  'recorder' => l.agentRecorder,
  'linker' => l.agentLinker,
  'checkin_converter' => l.agentCheckIn,
  null => l.you,
  _ => agent,
};

/// `Passed` · `Failed` · `In progress` for an audit in the history list.
extension AuditStatusUi on AuditStatus {
  String label(AppLocalizations l) => switch (this) {
    AuditStatus.passed => l.auditPassed,
    AuditStatus.failed => l.auditFailed,
    AuditStatus.active => l.auditInProgress,
  };

  Color get color => switch (this) {
    AuditStatus.passed => AppColors.success,
    AuditStatus.failed => AppColors.danger,
    AuditStatus.active => AppColors.textSecondary,
  };

  /// The soft background of the status chip.
  Color get fill => switch (this) {
    AuditStatus.passed => AppColors.successSoft,
    AuditStatus.failed => AppColors.dangerSoft,
    AuditStatus.active => AppColors.surfaceHigh,
  };
}

/// Formats a number without useless trailing zeros: `6.0` → `6`,
/// `5.30` → `5.3`, `1.2100` → `1.21`.
String formatNumber(num value, {int maxFractionDigits = 2}) {
  final fixed = value.toStringAsFixed(maxFractionDigits);
  if (!fixed.contains('.')) return fixed;
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// How the UI names a course: the title of its root node (`High School Math`, as in
/// “High School Math” is ready), else the course's own title.
String courseNameOf(CourseMap map) {
  final roots = rootNodes(map.nodes, map.edges);
  return roots.isEmpty ? map.course.title : roots.first.title;
}
