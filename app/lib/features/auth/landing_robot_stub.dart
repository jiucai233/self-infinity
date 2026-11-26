import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Whether this platform may have the robot. Off the web it is the three.js
/// scene recorded frame by frame for a phone (`assets/landing/phone/`, made by
/// `tool/record_robot_frames.js`); a screen that is not a portrait phone, or
/// a missing track, falls back to the film ([Robot3d.onFailed]).
const bool hasRobot3d = true;

/// The recorded robot: one frame per step of the scroll, filling the screen
/// as the web's scene does, and where the orb is in each.
class Robot3d extends StatefulWidget {
  const Robot3d({
    super.key,
    required this.progress,
    required this.onOrb,
    required this.onReady,
    required this.onFailed,
  });

  static const String folder = 'assets/landing/phone';

  /// How far the page is, in screens: 0 the hero, 5 the end.
  final double progress;

  /// Where the orb is drawn: its centre and radius, in logical pixels.
  final void Function(Offset center, double radius) onOrb;
  final VoidCallback onReady;
  final VoidCallback onFailed;

  @override
  State<Robot3d> createState() => _Robot3dState();
}

class _Track {
  const _Track(this.frames, this.aspect, this.step, this.orb);
  final int frames;
  final double aspect;
  final double step;
  final List<List<double>?> orb;
}

class _Robot3dState extends State<Robot3d> {
  _Track? _track;
  bool _failed = false;
  bool _ready = false;
  bool _precached = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final json = jsonDecode(
        await rootBundle.loadString('${Robot3d.folder}/track.json', cache: false),
      ) as Map<String, dynamic>;
      final track = _Track(
        json['frames'] as int,
        (json['aspect'] as num).toDouble(),
        (json['step'] as num).toDouble(),
        [
          for (final o in json['orb'] as List<dynamic>)
            o == null ? null : [for (final v in o as List<dynamic>) (v as num).toDouble()],
        ],
      );
      if (mounted) setState(() => _track = track);
    } on Object {
      _fail();
    }
  }

  void _fail() {
    if (_failed) return;
    _failed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFailed();
    });
  }

  String _frame(int i) => '${Robot3d.folder}/robot_${i.toString().padLeft(3, '0')}.webp';

  /// Decodes the first frame, says ready, then the rest in the background.
  Future<void> _precache(_Track track) async {
    if (_precached) return;
    _precached = true;
    await precacheImage(AssetImage(_frame(0)), context);
    if (!mounted) return;
    setState(() => _ready = true);
    widget.onReady();
    for (var i = 1; i < track.frames && mounted; i++) {
      await precacheImage(AssetImage(_frame(i)), context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = _track;
    if (_failed || track == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        // Recorded for a portrait phone; anything wider plays the film instead.
        if (w / h > 0.75) {
          _fail();
          return const SizedBox.shrink();
        }
        if (!_precached) _precache(track);
        final f = (widget.progress.clamp(0.0, 5.0) / track.step).clamp(0.0, track.frames - 1.0);
        // Cover: the frame fills the screen, centred.
        final fh = h > w / track.aspect ? h : w / track.aspect;
        final fw = fh * track.aspect;
        final left = (w - fw) / 2;
        final top = (h - fh) / 2;
        final orb = _orbAt(track, f);
        if (orb != null && _ready) {
          final center = Offset(left + orb[0] * fw, top + orb[1] * fh);
          final radius = orb[2] * fh;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onOrb(center, radius);
          });
        }
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: left,
              top: top,
              width: fw,
              height: fh,
              child: Image.asset(
                _frame(f.round()),
                key: const Key('landing-robot'),
                fit: BoxFit.fill,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ],
        );
      },
    );
  }

  /// The orb at fractional frame [f], between its two nearest frames.
  List<double>? _orbAt(_Track track, double f) {
    final i = f.floor().clamp(0, track.frames - 1);
    final j = (i + 1).clamp(0, track.frames - 1);
    final a = track.orb[i];
    final b = track.orb[j] ?? a;
    if (a == null || b == null) return a ?? b;
    final t = f - i;
    return [for (var k = 0; k < 3; k++) a[k] + (b[k] - a[k]) * t];
  }
}
