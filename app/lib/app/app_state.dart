/// App-wide state that is not server data: a refresh signal.
library;

import 'package:flutter/foundation.dart';

/// The one global store (everything else lives in screens).
///
/// Provided above the router: `context.read<AppState>()` /
/// `context.watch<AppState>()`.
///
/// It holds only [dataRevision]: a screen that loaded server data reloads when
/// the revision changes (an audit finished, a course was made, a check-in was
/// saved). Nothing is persisted on the device.
class AppState extends ChangeNotifier {
  int _dataRevision = 0;

  /// Increases whenever [markDataChanged] is called.
  ///
  /// ```dart
  /// int? _revision;
  ///
  /// @override
  /// void didChangeDependencies() {
  ///   super.didChangeDependencies();
  ///   final revision = context.watch<AppState>().dataRevision;
  ///   if (_revision != null && _revision != revision) _reload();
  ///   _revision = revision;
  /// }
  /// ```
  int get dataRevision => _dataRevision;

  /// Announces that server data changed (an audit finished, a course was
  /// created, a check-in was saved, ...). Call it after such a mutation.
  void markDataChanged() {
    _dataRevision++;
    notifyListeners();
  }
}
