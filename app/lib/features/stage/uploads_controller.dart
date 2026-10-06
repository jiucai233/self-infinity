import 'package:flutter/foundation.dart';

import '../../api/api.dart';
import '../../api/api_exception.dart';
import '../../api/models.dart';
import '../../upload/file_picker_service.dart';

/// The files attached to the next chat message (the ⊕ button of scenes 1 and
/// 5): pick → upload → a chip above the input until the message is sent.
class UploadsController extends ChangeNotifier {
  UploadsController({required this.api, required this.picker});

  final SelfInfinityApi api;
  final FilePickerService picker;

  /// At most this many files go with one message.
  static const int maxFiles = 3;

  static const String badFileText = 'Only PDF, TXT or MD files up to 4 MB.';

  final List<UploadedFile> _files = [];
  String? _uploadingName;
  bool _disposed = false;

  /// The uploaded files, in the order they were added.
  List<UploadedFile> get files => List.unmodifiable(_files);

  /// The ids to send as `upload_ids`.
  List<int> get ids => [for (final f in _files) f.id];

  /// The name of the file that is being uploaded right now, or null.
  String? get uploadingName => _uploadingName;

  bool get busy => _uploadingName != null;

  /// Opens the file dialog and uploads the chosen file. Returns a short
  /// message when something went wrong (for a snackbar), else null.
  Future<String?> pick() async {
    if (busy) return null;
    if (_files.length >= maxFiles) return 'You can attach up to $maxFiles files.';
    final file = await picker.pick();
    if (file == null || _disposed) return null;
    final name = file.name.toLowerCase();
    final okType = kUploadExtensions.any((e) => name.endsWith('.$e'));
    if (!okType || file.bytes.length > kUploadMaxBytes) return badFileText;
    _uploadingName = file.name;
    notifyListeners();
    try {
      final uploaded = await api.uploadFile(filename: file.name, bytes: file.bytes);
      if (_disposed) return null;
      _files.add(uploaded);
      return null;
    } on ApiException catch (e) {
      return e.userMessage;
    } on Object {
      return ApiException.unknownText;
    } finally {
      _uploadingName = null;
      if (!_disposed) notifyListeners();
    }
  }

  /// Takes a file off the next message.
  void remove(int id) {
    if (_files.any((f) => f.id == id)) {
      _files.removeWhere((f) => f.id == id);
      notifyListeners();
    }
  }

  /// The message was sent: the chips go away.
  void clear() {
    if (_files.isEmpty) return;
    _files.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
