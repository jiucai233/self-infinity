import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Starts a download of [bytes] as [filename].
Future<bool> saveFile(Uint8List bytes, {required String filename, required String mimeType}) async {
  try {
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
    final url = web.URL.createObjectURL(blob);
    final link = web.HTMLAnchorElement()
      ..href = url
      ..download = filename
      ..style.display = 'none';
    web.document.body?.append(link);
    link.click();
    link.remove();
    web.URL.revokeObjectURL(url);
    return true;
  } on Object {
    return false;
  }
}
