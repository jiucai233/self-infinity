/// Live voice in the browser (contract #35): a WebRTC session with OpenAI's
/// Realtime API whose handshake goes through our server, and speech streamed
/// as it is made. `live_io_web.dart` in the browser, nothing elsewhere
/// (`live_io_stub.dart`: the phones keep their own speech).
library;

export 'live_link.dart';
export 'live_io_stub.dart' if (dart.library.js_interop) 'live_io_web.dart';
