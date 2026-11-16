import '../upload/file_picker_service.dart';

/// A [FilePickerService] for tests: no dialog, returns what was queued.
///
/// ```dart
/// final picker = FakeFilePicker()..next = PickedFile(name: 'course.md', bytes: utf8.encode('# Math'));
/// ```
class FakeFilePicker implements FilePickerService {
  /// What the next [pick] returns; null = the dialog was cancelled.
  PickedFile? next;

  /// How often [pick] was called.
  int calls = 0;

  /// The extensions the last [pick] asked for.
  List<String>? lastExtensions;

  @override
  Future<PickedFile?> pick({List<String> extensions = kUploadExtensions}) async {
    calls++;
    lastExtensions = extensions;
    final file = next;
    next = null;
    return file;
  }
}
