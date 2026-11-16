/// Handing the user a file to keep (the workout export): a download in the
/// browser; elsewhere [saveFile] answers false and the screen says so.
library;

export 'file_saver_stub.dart' if (dart.library.js_interop) 'file_saver_web.dart';
