/// The front page's three.js robot (`web/landing3d/`): on the web, an iframe
/// with the scene; elsewhere there is none ([hasRobot3d] is false) and the
/// page plays the film instead.
library;

export 'landing_robot_stub.dart' if (dart.library.js_interop) 'landing_robot_web.dart';
