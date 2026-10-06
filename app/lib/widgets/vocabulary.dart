/// English UI vocabulary and the colors that go with each enum value, so that
/// every screen says and colors the same thing the same way.
library;

import 'package:flutter/material.dart';

import '../api/graph_utils.dart';
import '../api/models.dart';
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
  String get label => switch (this) {
    ConditionFlag.normal => 'Good',
    ConditionFlag.low => 'Low',
    ConditionFlag.unknown => 'No record',
  };
}

/// Display names of the agents (the label in the history lists).
String agentLabel(String? agent) => switch (agent) {
  'front_desk' => 'Guide',
  'narrator' => 'Narrator',
  'recommender' => 'Recommender',
  'planner' => 'Planner',
  'clarifier' => 'Clarifier',
  'syllabus_finder' => 'Syllabus Finder',
  'material_finder' => 'Material Finder',
  'auditor' => 'Auditor',
  'challenger' => 'Challenger',
  'recorder' => 'Recorder',
  'linker' => 'Linker',
  'checkin_converter' => 'Check-in',
  null => 'You',
  _ => agent,
};

/// `Passed` · `Failed` · `In progress` for an audit in the history list.
extension AuditStatusUi on AuditStatus {
  String get label => switch (this) {
    AuditStatus.passed => 'Passed',
    AuditStatus.failed => 'Failed',
    AuditStatus.active => 'In progress',
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
