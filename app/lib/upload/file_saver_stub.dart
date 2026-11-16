import 'dart:typed_data';

/// No download outside the browser.
Future<bool> saveFile(Uint8List bytes, {required String filename, required String mimeType}) async => false;
