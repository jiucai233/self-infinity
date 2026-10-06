import 'package:flutter/foundation.dart';

/// Which side panels are folded into a thin rail (`docs/DESIGN.md` Section 3,
/// panels) and which sections of the left panel are folded. Kept in memory for the session, so the choice survives a scene
/// change; nothing is persisted.
class PanelLayout extends ChangeNotifier {
  bool _leftCollapsed = false;
  bool _rightCollapsed = false;

  /// The left panel (My character) is a rail.
  bool get leftCollapsed => _leftCollapsed;

  /// The chat / history panel is a rail.
  bool get rightCollapsed => _rightCollapsed;

  final Set<String> _foldedSections = {};

  /// Whether the section [id] of the left panel is folded (all start open).
  bool isSectionFolded(String id) => _foldedSections.contains(id);

  void toggleSection(String id) {
    if (!_foldedSections.remove(id)) _foldedSections.add(id);
    notifyListeners();
  }

  set leftCollapsed(bool value) {
    if (value == _leftCollapsed) return;
    _leftCollapsed = value;
    notifyListeners();
  }

  set rightCollapsed(bool value) {
    if (value == _rightCollapsed) return;
    _rightCollapsed = value;
    notifyListeners();
  }
}
