import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'avatar_atlas.dart';

/// How the avatar looks (`docs/ux-chat.md` Section 3).
enum AvatarMood { smile, neutral, stern, angry, happy }

/// What the avatar is doing.
enum AvatarState { idle, listening, thinking, speaking }

/// A short reaction that overrides her picture while it lasts.
enum AvatarReaction {
  /// She turns to what is beside her (her crystal ball), beaming.
  lookAside,

  /// Delighted, eyes sparkling.
  surprised,
}

/// The agent's mood when nothing else is said.
AvatarMood defaultMoodOf(String agent) => switch (agent) {
  'front_desk' || 'recommender' || 'checkin_converter' => AvatarMood.smile,
  'auditor' || 'challenger' => AvatarMood.stern,
  _ => AvatarMood.neutral,
};

/// The app's own companion, the one character every agent is
/// (`art/infinity/*.gif`, packed by `tool/build_avatar.py` into
/// `assets/infinity/infinity.webp`): a chibi fairy with cat ears, headphones
/// and the infinity sign.
///
/// Where each animation is used:
///
/// | | |
/// | --- | --- |
/// | idle ([AvatarMood.neutral], [AvatarMood.smile]), [AvatarState.listening] | standing, blinking (`idle`) |
/// | [AvatarMood.stern] / [AvatarMood.angry], [AvatarState.speaking] | fists up, fired up (`cheer`) |
/// | [AvatarMood.happy] (a passed audit) | a check mark and +100 XP (`success`) |
/// | [wave] | waving hello (`wave`) |
/// | [AvatarState.thinking] | reading her book (`study`) |
/// | idle for [Avatar.sleepAfter] | asleep on a cloud (`sleep`) |
///
/// * [agent] is kept for the label; every agent is drawn as the same
///   character.
/// * [wave] waves once, then she rests on her mood's picture.
/// * [holdOrb] holds up her check mark in both hands.
/// * [reaction], when set, shows that still picture instead (no movement).
/// * [animate] turns the movement off (the picture is then one still frame).
///   It defaults to [animationsEnabled], which tests switch off.
///
/// The atlas is decoded once and shared; until it is, the box is empty.
class Avatar extends StatefulWidget {
  const Avatar({
    super.key,
    required this.agent,
    this.mood = AvatarMood.neutral,
    this.state = AvatarState.idle,
    this.wave = false,
    this.holdOrb = false,
    this.size = 160,
    this.animate,
    this.reaction,
  });

  /// Global switch for the movement; `false` in widget tests.
  static bool animationsEnabled = true;

  /// How long she stays idle (calm mood, nothing changing) before she falls
  /// asleep. Any change to what she is shown doing wakes her.
  static Duration sleepAfter = const Duration(seconds: 90);

  /// Decodes the atlas (once). Tests await it so she is drawn at once.
  static Future<void> precache() => _Sheets.load();

  /// One loop of her idle blink; things that move with her use it.
  static Duration get idleLoop => Duration(milliseconds: _durationMs(idleClip));

  /// Where a crystal ball floats beside her: at chest height, just past her
  /// hair on her left (the viewer's right), in the avatar's own coordinates
  /// (the box is `size * aspect` wide and `size` high). [OrbAvatar] centres
  /// its ball here.
  static Offset orbHandAt(String agent, double size) {
    final k = unit(agent, size);
    return Offset(size * aspect / 2, 0) + _orbFloat * k;
  }

  /// Scale from figure units to logical pixels: the box is 100 x 140 units.
  static double unit(String agent, double size) => size / 140;

  /// Width / height of the avatar's box. Her hair and wings reach a little
  /// past its sides.
  static const double aspect = 100 / 140;

  /// The floating ball's centre, from the box's top centre, in units.
  static const Offset _orbFloat = Offset(76, 58);

  final String agent;
  final AvatarMood mood;
  final AvatarState state;
  final bool wave;
  final bool holdOrb;

  /// Height of the figure; it is 5/7 of that wide.
  final double size;
  final bool? animate;
  final AvatarReaction? reaction;

  @override
  State<Avatar> createState() => _AvatarState();
}

/// The decoded atlas, shared by every avatar.
abstract final class _Sheets {
  static ui.Image? atlas;
  static final ValueNotifier<bool> ready = ValueNotifier(false);
  static Future<void>? _loading;

  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final data = await rootBundle.load(atlasAsset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();
      atlas = frame.image;
      ready.value = true;
    } on Object catch (e) {
      // The box stays empty; nothing else depends on her picture.
      debugPrint('Avatar: the atlas did not load ($e)');
    }
  }
}

/// One picture: a frame of a clip.
@immutable
class _Pic {
  const _Pic(this.clip, this.index);

  /// The kept frame of [clip] that shows frame [original] of its GIF.
  factory _Pic.at(AtlasClip clip, int original) {
    var index = 0;
    for (var i = 0; i < clip.frames.length; i++) {
      if (clip.frames[i].original <= original) index = i;
    }
    return _Pic(clip, index);
  }

  final AtlasClip clip;
  final int index;

  AtlasFrame get frame => clip.frames[index];

  @override
  bool operator ==(Object other) =>
      other is _Pic && identical(other.clip, clip) && other.index == index;

  @override
  int get hashCode => Object.hash(identityHashCode(clip), index);
}

int _durationMs(AtlasClip clip) => clip.frames.fold(0, (sum, f) => sum + f.ms);

/// The frame of [clip] shown [ms] into its loop.
int _indexAt(AtlasClip clip, int ms) {
  var t = ms % _durationMs(clip);
  for (var i = 0; i < clip.frames.length; i++) {
    t -= clip.frames[i].ms;
    if (t < 0) return i;
  }
  return clip.frames.length - 1;
}

/// The animation of [mood] while she is idle.
AtlasClip _moodClip(AvatarMood mood) => switch (mood) {
  AvatarMood.neutral || AvatarMood.smile => idleClip,
  AvatarMood.stern || AvatarMood.angry => cheerClip,
  AvatarMood.happy => successClip,
};

/// The still picture of [mood].
_Pic _moodPic(AvatarMood mood) => switch (mood) {
  AvatarMood.neutral => const _Pic(idleClip, 0),
  // Standing, the frame after the long open-eyed one: a softer smile.
  AvatarMood.smile => _Pic.at(idleClip, 3),
  AvatarMood.stern => const _Pic(cheerClip, 0),
  // Eyes squeezed shut, fists clenched.
  AvatarMood.angry => _Pic.at(cheerClip, 32),
  // The pose she holds longest: check mark up, +100 XP.
  AvatarMood.happy => _Pic.at(successClip, 12),
};

class _AvatarState extends State<Avatar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  /// The frame of the playing clip; rebuilds only when it changes.
  final ValueNotifier<int> _tick = ValueNotifier(0);

  /// The clip the controller is timed for.
  AtlasClip? _playing;

  Timer? _sleepTimer;
  bool _sleeping = false;

  bool get _animate => widget.animate ?? Avatar.animationsEnabled;

  bool get _waving => widget.state == AvatarState.idle && widget.wave;

  /// Calm and idle: she may doze off.
  bool get _canSleep =>
      _animate &&
      widget.state == AvatarState.idle &&
      !widget.wave &&
      !widget.holdOrb &&
      widget.reaction == null &&
      (widget.mood == AvatarMood.neutral || widget.mood == AvatarMood.smile);

  /// What plays while moving, or null for a still picture.
  AtlasClip? get _clip {
    if (!_animate || widget.holdOrb || widget.reaction != null) return null;
    if (_sleeping) return sleepClip;
    return switch (widget.state) {
      AvatarState.speaking => cheerClip,
      AvatarState.thinking => studyClip,
      AvatarState.listening => idleClip,
      AvatarState.idle => widget.wave ? waveClip : _moodClip(widget.mood),
    };
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTick);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() {});
    });
    if (!_Sheets.ready.value) {
      _Sheets.ready.addListener(_onReady);
      unawaited(_Sheets.load());
    }
    _sync(null);
  }

  void _onReady() {
    if (mounted) setState(() {});
  }

  void _onTick() {
    final clip = _playing;
    if (clip == null) return;
    final ms = (_controller.value * _controller.duration!.inMilliseconds).floor();
    _tick.value = _indexAt(clip, ms);
  }

  @override
  void didUpdateWidget(Avatar old) {
    super.didUpdateWidget(old);
    final changed =
        old.mood != widget.mood ||
        old.state != widget.state ||
        old.wave != widget.wave ||
        old.holdOrb != widget.holdOrb ||
        old.reaction != widget.reaction ||
        old.animate != widget.animate;
    if (changed) _sleeping = false;
    _sync(old, restartSleep: changed);
  }

  void _sync(Avatar? old, {bool restartSleep = true}) {
    _syncSleep(restart: restartSleep || old == null);
    final clip = _clip;
    if (clip == null) {
      _playing = null;
      _controller.stop();
      return;
    }
    final loop = Duration(milliseconds: _durationMs(clip));
    if (_waving && !_sleeping) {
      // A finished wave is not started again by a rebuild.
      if (old == null || !old.wave || old.state != AvatarState.idle) {
        _playing = clip;
        _tick.value = 0;
        _controller
          ..duration = loop
          ..forward(from: 0);
      }
    } else if (!_controller.isAnimating || !identical(_playing, clip)) {
      _playing = clip;
      _tick.value = 0;
      _controller
        ..duration = loop
        ..repeat();
    }
  }

  void _syncSleep({required bool restart}) {
    if (!_canSleep) {
      _sleepTimer?.cancel();
      _sleepTimer = null;
      _sleeping = false;
      return;
    }
    if (_sleeping || (!restart && _sleepTimer != null)) return;
    _sleepTimer?.cancel();
    _sleepTimer = Timer(Avatar.sleepAfter, () {
      if (!mounted || !_canSleep) return;
      setState(() => _sleeping = true);
      _sync(widget, restartSleep: false);
    });
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _Sheets.ready.removeListener(_onReady);
    _controller.dispose();
    _tick.dispose();
    super.dispose();
  }

  /// The picture when nothing moves.
  _Pic get _still {
    switch (widget.reaction) {
      case AvatarReaction.lookAside:
        return const _Pic(waveClip, 0);
      case AvatarReaction.surprised:
        return const _Pic(successClip, 0);
      case null:
    }
    if (widget.holdOrb) return const _Pic(successClip, 0);
    return switch (widget.state) {
      AvatarState.thinking => const _Pic(studyClip, 0),
      // Eyes closed, listening through her headphones.
      AvatarState.listening => _Pic.at(idleClip, 2),
      AvatarState.speaking => const _Pic(cheerClip, 0),
      AvatarState.idle => widget.wave ? _Pic.at(waveClip, 8) : _moodPic(widget.mood),
    };
  }

  /// The picture of the playing clip ([tick] is its current frame).
  _Pic _picAt(int tick) {
    final clip = _clip;
    if (clip == null) return _still;
    // A wave that has run settles on the mood's picture.
    if (_waving && !_sleeping && !_controller.isAnimating) return _moodPic(widget.mood);
    // Before the first tick of a new clip the old frame may still be there.
    return _Pic(clip, identical(_playing, clip) && tick < clip.frames.length ? tick : 0);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.agent} avatar',
      child: SizedBox(
        width: widget.size * Avatar.aspect,
        height: widget.size,
        child: ValueListenableBuilder<int>(
          valueListenable: _tick,
          builder: (context, tick, _) => CustomPaint(painter: _FigurePainter(_picAt(tick))),
        ),
      ),
    );
  }
}

/// Draws one picture as large as fits, centred, standing on the box's
/// bottom. Half-length pictures may reach a little past the sides (her hair
/// and wings), as the full figure's do.
class _FigurePainter extends CustomPainter {
  _FigurePainter(this.pic) : super(repaint: _Sheets.ready);

  final _Pic pic;

  static const double _overhang = 1.25;

  @override
  void paint(Canvas canvas, Size size) {
    final image = _Sheets.atlas;
    if (image == null) return;
    final clip = pic.clip;
    final s = math.min(size.width * _overhang / clip.width, size.height / clip.height);
    final w = clip.width * s;
    final h = clip.height * s;
    canvas.drawImageRect(
      image,
      pic.frame.source,
      Rect.fromLTWH((size.width - w) / 2, size.height - h, w, h),
      // Mipmapped sampling keeps her line art crisp when drawn small (the
      // audit header, the badges).
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_FigurePainter old) => old.pic != pic;
}

/// Her head in a round, light-grey badge — the portrait next to a message in
/// the chat panel (`docs/DESIGN.md` Section 4). Always still.
class AvatarHead extends StatefulWidget {
  const AvatarHead({super.key, required this.agent, this.size = 28, this.mood});

  final String agent;

  /// Diameter of the badge.
  final double size;

  /// Defaults to [defaultMoodOf] the agent.
  final AvatarMood? mood;

  @override
  State<AvatarHead> createState() => _AvatarHeadState();
}

class _AvatarHeadState extends State<AvatarHead> {
  @override
  void initState() {
    super.initState();
    if (!_Sheets.ready.value) unawaited(_Sheets.load());
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.agent} avatar',
      child: SizedBox.square(
        dimension: widget.size,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: AppColors.surfaceHigh, shape: BoxShape.circle),
          child: ClipOval(
            child: CustomPaint(
              painter: _HeadPainter(_moodPic(widget.mood ?? defaultMoodOf(widget.agent))),
            ),
          ),
        ),
      ),
    );
  }
}

/// A close-up of the head of [pic].
class _HeadPainter extends CustomPainter {
  _HeadPainter(this.pic) : super(repaint: _Sheets.ready);

  final _Pic pic;

  @override
  void paint(Canvas canvas, Size size) {
    final image = _Sheets.atlas;
    if (image == null) return;
    canvas.drawImageRect(
      image,
      pic.clip.head.shift(pic.frame.source.topLeft),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_HeadPainter old) => old.pic != pic;
}
