import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Whether this platform has the three.js robot.
const bool hasRobot3d = true;

/// The robot scene, `web/landing3d/index.html`, in an iframe that never takes
/// the pointer (the page keeps the scrolling). The page tells it how far it
/// has scrolled; it tells the page where the orb is.
class Robot3d extends StatefulWidget {
  const Robot3d({
    super.key,
    required this.progress,
    required this.onOrb,
    required this.onReady,
    required this.onFailed,
  });

  /// How far the page is, in screens: 0 the hero, 5 the end.
  final double progress;

  /// Where the orb is drawn: its centre and radius, in logical pixels.
  final void Function(Offset center, double radius) onOrb;

  /// The robot is on screen.
  final VoidCallback onReady;

  /// No WebGL, or the scene did not load in time.
  final VoidCallback onFailed;

  @override
  State<Robot3d> createState() => _Robot3dState();
}

class _Robot3dState extends State<Robot3d> {
  static int _views = 0;
  final String _viewType = 'self-infinity-robot-${_views++}';
  web.HTMLIFrameElement? _frame;
  late final JSFunction _listener = _onMessage.toJS;
  Timer? _timeout;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int id) {
      final frame = web.HTMLIFrameElement()
        ..src = 'landing3d/index.html'
        ..title = 'robot'
        ..tabIndex = -1
        ..setAttribute('aria-hidden', 'true');
      frame.style
        ..border = '0'
        ..width = '100%'
        ..height = '100%'
        ..pointerEvents = 'none';
      return _frame = frame;
    });
    web.window.addEventListener('message', _listener);
    _timeout = Timer(const Duration(seconds: 20), () {
      if (!_ready) widget.onFailed();
    });
  }

  void _onMessage(web.Event event) {
    final data = (event as web.MessageEvent).data.dartify();
    if (data is! Map || data['source'] != 'self-infinity-robot') return;
    switch (data['type']) {
      case 'ready':
        _ready = true;
        _timeout?.cancel();
        _send();
        widget.onReady();
      case 'unsupported':
        _timeout?.cancel();
        widget.onFailed();
      case 'orb':
        widget.onOrb(
          Offset((data['x'] as num).toDouble(), (data['y'] as num).toDouble()),
          (data['r'] as num).toDouble(),
        );
    }
  }

  void _send() {
    _frame?.contentWindow?.postMessage(
      {'source': 'self-infinity-page', 'p': widget.progress}.jsify(),
      '*'.toJS,
    );
  }

  @override
  void didUpdateWidget(Robot3d old) {
    super.didUpdateWidget(old);
    if (old.progress != widget.progress) _send();
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
