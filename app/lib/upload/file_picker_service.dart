/// Picking a file behind one interface, so that screens and tests never touch
/// the `file_picker` plugin directly.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// A file the user chose.
@immutable
class PickedFile {
  const PickedFile({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
}

/// The extensions the upload accepts (`docs/api-contract.md` endpoint 24).
const List<String> kUploadExtensions = ['pdf', 'txt', 'md'];

/// The largest file the upload accepts.
const int kUploadMaxBytes = 4 * 1024 * 1024;

/// Opens the system file dialog.
abstract class FilePickerService {
  /// Lets the user pick one `.pdf` / `.txt` / `.md` file. Returns null when
  /// the dialog is cancelled or the file cannot be read. Never throws.
  Future<PickedFile?> pick();
}

/// [FilePickerService] over the `file_picker` plugin.
class PlatformFilePickerService implements FilePickerService {
  @override
  Future<PickedFile?> pick() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: kUploadExtensions,
      );
      if (file == null) return null;
      return PickedFile(name: file.name, bytes: await file.readAsBytes());
    } on Object catch (e) {
      debugPrint('PlatformFilePickerService: could not pick a file ($e)');
      return null;
    }
  }
}
