import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api/api.dart';
import '../../api/models.dart';
import '../../widgets/error_view.dart';

/// The fields of the character sheet that can be edited in place.
enum ProfileField { identity, vision, antiVision, rules }

/// The character sheet of the left panel (endpoints 25 and 26): loads the
/// [Profile] once and saves one field at a time (`PUT /profile` with only that
/// field, so the others on the server are kept).
///
/// The `save…` methods return `null` when the server accepted the change and
/// the English text to show when it did not.
class ProfileController extends ChangeNotifier {
  ProfileController({required this.api}) {
    unawaited(load());
  }

  final SelfInfinityApi api;

  Profile _profile = const Profile();
  bool _loaded = false;
  bool _disposed = false;

  Profile get profile => _profile;

  /// Whether the first load finished (successfully or not).
  bool get loaded => _loaded;

  /// Loads the profile. A failure leaves the sheet empty (editing still works:
  /// a save only sends the field that changed).
  Future<void> load() async {
    try {
      _profile = await api.getProfile();
    } on Object {
      // keep the empty sheet
    }
    _loaded = true;
    _notify();
  }

  /// Saves one text field.
  Future<String?> saveText(ProfileField field, String value) {
    assert(field != ProfileField.rules);
    return _save(
      () => api.updateProfile(
        identity: field == ProfileField.identity ? value : null,
        vision: field == ProfileField.vision ? value : null,
        antiVision: field == ProfileField.antiVision ? value : null,
      ),
    );
  }

  /// Marks the first-run tutorial as done (or, with `false`, to be shown
  /// again).
  Future<String?> setOnboarded(bool done) => _save(() => api.updateProfile(onboarded: done));

  /// Saves the whole list of rules.
  Future<String?> saveRules(List<String> rules) => _save(() => api.updateProfile(rules: rules));

  Future<String?> _save(Future<Profile> Function() call) async {
    try {
      _profile = await call();
      _notify();
      return null;
    } on Object catch (e) {
      return ErrorView.messageFor(e);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
