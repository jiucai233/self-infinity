import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'live2d_figure.dart';

/// The model page, `web/live2d/index.html`, in an iframe of its own.
Live2DHost? createLive2DHost(Live2DHostConfig config) => _FrameHost(config);

class _FrameHost implements Live2DHost {
  _FrameHost(this.config) {
    final query = <String, String>{
      'id': _id,
      'framing': config.framing,
      if (config.follow) 'follow': '1',
    };
    final src = Uri(path: 'live2d/index.html', queryParameters: query).toString();
    ui_web.platformViewRegistry.registerViewFactory(_id, (int viewId) {
      final frame = web.HTMLIFrameElement()
        ..src = src
        ..title = '大肥鱼'
        ..tabIndex = -1
        ..setAttribute('aria-hidden', 'true')
        ..setAttribute('allowtransparency', 'true');
      frame.style
        ..border = '0'
        ..width = '100%'
        ..height = '100%'
        ..background = 'transparent'
        ..pointerEvents = config.follow ? 'auto' : 'none';
      return _frame = frame;
    });
    web.window.addEventListener('message', _listener);
    // The page gives up after 25 s; this catches a page that never ran.
    _timeout = Timer(const Duration(seconds: 30), () {
      if (!_ready) _fail('timeout');
    });
  }

  static int _count = 0;

  final Live2DHostConfig config;
  final String _id = 'self-infinity-live2d-${_count++}';
  late final JSFunction _listener = _onMessage.toJS;
  web.HTMLIFrameElement? _frame;
  Timer? _timeout;
  bool _ready = false;
  bool _done = false;

  @override
  late final Widget view = HtmlElementView(viewType: _id);

  void _onMessage(web.Event event) {
    if (_done) return;
    final data = (event as web.MessageEvent).data.dartify();
    if (data is! Map || data['source'] != 'self-infinity-live2d' || data['id'] != _id) return;
    switch (data['type']) {
      case 'ready':
        _ready = true;
        _timeout?.cancel();
        config.onReady();
      case 'error':
        _fail('${data['reason'] ?? 'error'}');
    }
  }

  void _fail(String reason) {
    if (_done) return;
    _timeout?.cancel();
    config.onError(reason);
  }

  @override
  void send(Map<String, Object?> message) {
    _frame?.contentWindow?.postMessage(message.jsify(), '*'.toJS);
  }

  @override
  void dispose() {
    _done = true;
    _timeout?.cancel();
    web.window.removeEventListener('message', _listener);
  }
}
