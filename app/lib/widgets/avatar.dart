import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// How the avatar looks (`docs/ux-chat.md` Section 3).
enum AvatarMood { smile, neutral, stern, angry, happy }

/// What the avatar is doing.
enum AvatarState { idle, listening, thinking, speaking }

/// A short reaction that overrides her picture while it lasts.
enum AvatarReaction {
  /// She turns to look at something beside her (her left, the viewer's
  /// right, where [OrbAvatar]'s ball floats).
  lookAside,

  /// Hands to her face, eyes wide.
  surprised,
}

/// The agent's mood when nothing else is said.
AvatarMood defaultMoodOf(String agent) => switch (agent) {
  'front_desk' || 'recommender' || 'checkin_converter' => AvatarMood.smile,
  'auditor' || 'challenger' => AvatarMood.stern,
  _ => AvatarMood.neutral,
};

/// The author's credit for 大肥鱼, which her license asks to be shown with the
/// repository (`assets/dafeiyu/README.md`).
const String dafeiyuCredit =
    '大肥鱼 · YunYueSama · https://github.com/YunYueSama/codex-deepseek-pet';

/// Puts 大肥鱼's license on Flutter's license page.
void registerDafeiyuLicense() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/dafeiyu/LICENSE.txt');
    yield LicenseEntryWithLineBreaks(
      const ['大肥鱼 (character art)'],
      '作者：YunYueSama\n'
      '仓库：https://github.com/YunYueSama/codex-deepseek-pet\n\n'
      'Modified for this app: 29 frames of the 512 px expression, action, idle '
      'and wave sheets are cut out, rescaled to one figure height, packed into '
      'one atlas and re-encoded as WebP. Not endorsed by YunYueSama or DeepSeek.\n\n$text',
    );
  });
}

/// 大肥鱼, the one companion every agent is (`assets/dafeiyu/`): a chibi
/// whale-girl maid drawn from one sprite atlas.
///
/// * [agent] is kept for the label and for a later 3D model; every agent is
///   drawn as the same character.
/// * [mood] picks her expression; [state] what she is doing: a hand on her
///   chin while thinking, talking while speaking, a tilted head while
///   listening.
/// * [wave] waves a few times.
/// * [holdOrb] holds her own little whale ball in both hands.
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

  /// Decodes the atlas (once). Tests await it so she is drawn at once.
  static Future<void> precache() => _Sheets.load();

  /// One loop of her idle blink; things that move with her use it.
  static Duration get idleLoop => _Clip.idle.duration;

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

  /// Width / height of the avatar's box. Her hair and tail reach a little past
  /// its sides.
  static const double aspect = 100 / 140;

  /// The floating ball's centre, from the box's top centre, in units: her
  /// hair reaches 47 units right of her middle at chest height.
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

/// The atlas (`assets/dafeiyu/dafeiyu.webp`) and where the figure sits in
/// its cells: 8 columns of 352 x 432 px cells, every frame scaled so a
/// standing figure is equally tall and her soles on the same line.
abstract final class _Sheet {
  static const String asset = 'assets/dafeiyu/dafeiyu.webp';
  static const double cellWidth = 352;
  static const double cellHeight = 432;
  static const int columns = 8;

  /// The figure's middle, the top of her hair and her soles, in cell pixels.
  static const double centerX = 176;
  static const double top = 24;
  static const double bottom = 428;
  static const double height = bottom - top;

  /// Her head, for the badge: a square of [headSide] around [headCenter].
  static const Offset headCenter = Offset(centerX, bottom - 264);
  static const double headSide = 224;
}

/// The decoded atlas, shared by every avatar.
abstract final class _Sheets {
  static ui.Image? atlas;
  static final ValueNotifier<bool> ready = ValueNotifier(false);
  static Future<void>? _loading;

  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final data = await rootBundle.load(_Sheet.asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();
      atlas = frame.image;
      ready.value = true;
    } on Object catch (e) {
      // The box stays empty; nothing else depends on her picture.
      debugPrint('大肥鱼: the atlas did not load ($e)');
    }
  }
}

/// One picture: a cell of the atlas (the order of
/// `assets/dafeiyu/README.md`).
extension type const _Frame(int index) {
  static const neutral = _Frame(0);
  static const curious = _Frame(1);
  static const sideGlance = _Frame(2);
  static const holding = _Frame(3);
  static const eyesClosed = _Frame(4);
  static const thinking = _Frame(5);
  static const pouting = _Frame(6);
  static const surprised = _Frame(7);
  static const lookAside = _Frame(8);
  static const smile = _Frame(9);
  static const talkOpen = _Frame(10);
  static const talkSmile = _Frame(11);
  static const thinkA = _Frame(12);
  static const thinkB = _Frame(13);
  static const idleOpen = _Frame(14);
  static const idleClosed = _Frame(15);
  static const listen0 = _Frame(16);
  static const listen1 = _Frame(17);
  static const listen2 = _Frame(18);
  static const listen3 = _Frame(19);
  static const wave0 = 20; // the first of nine wave frames

  Rect get source => Rect.fromLTWH(
    (index % _Sheet.columns) * _Sheet.cellWidth,
    (index ~/ _Sheet.columns) * _Sheet.cellHeight,
    _Sheet.cellWidth,
    _Sheet.cellHeight,
  );
}

/// Frames played as a loop, each held [frameMs].
class _Clip {
  const _Clip(this.frames, this.frameMs);

  final List<_Frame> frames;
  final int frameMs;

  int get length => frames.length;

  Duration get duration => Duration(milliseconds: length * frameMs);

  _Frame at(int i) => frames[i % length];

  /// Eyes open for three seconds, one blink.
  static const idle = _Clip([
    ...[
      _Frame.idleOpen, _Frame.idleOpen, _Frame.idleOpen, _Frame.idleOpen, _Frame.idleOpen,
      _Frame.idleOpen, _Frame.idleOpen, _Frame.idleOpen, _Frame.idleOpen, _Frame.idleOpen,
      _Frame.idleOpen, _Frame.idleOpen, _Frame.idleOpen, _Frame.idleOpen, _Frame.idleOpen,
      _Frame.idleOpen, _Frame.idleOpen, _Frame.idleOpen, _Frame.idleOpen, _Frame.idleOpen,
      _Frame.idleOpen, _Frame.idleOpen, _Frame.idleOpen,
    ],
    _Frame.idleClosed,
  ], 130);

  static const wave = _Clip([
    _Frame(_Frame.wave0), _Frame(_Frame.wave0 + 1), _Frame(_Frame.wave0 + 2),
    _Frame(_Frame.wave0 + 3), _Frame(_Frame.wave0 + 4), _Frame(_Frame.wave0 + 5),
    _Frame(_Frame.wave0 + 6), _Frame(_Frame.wave0 + 7), _Frame(_Frame.wave0 + 8),
  ], 140);

  /// Looks around, tilts her head.
  static const listening = _Clip([
    _Frame.listen0, _Frame.listen1, _Frame.listen1, _Frame.listen0,
    _Frame.listen3, _Frame.listen3, _Frame.listen0, _Frame.listen2,
  ], 300);

  /// A finger on her chin.
  static const thinking = _Clip([
    _Frame.thinkA, _Frame.thinkA, _Frame.thinkB, _Frame.thinkB, _Frame.thinkB, _Frame.thinkA,
  ], 300);

  static const talking = _Clip([
    _Frame.talkOpen, _Frame.smile, _Frame.talkOpen, _Frame.talkSmile,
  ], 200);
}

/// The still picture of [mood].
_Frame _moodFrame(AvatarMood mood) => switch (mood) {
  AvatarMood.smile => _Frame.smile,
  AvatarMood.neutral => _Frame.neutral,
  AvatarMood.stern => _Frame.sideGlance,
  AvatarMood.angry => _Frame.pouting,
  AvatarMood.happy => _Frame.eyesClosed,
};

class _AvatarState extends State<Avatar> with SingleTickerProviderStateMixin {
  static const int _waveCycles = 2;
  late final AnimationController _controller = AnimationController(vsync: this);

  /// The step of the playing clip; rebuilds only when it changes.
  final ValueNotifier<int> _tick = ValueNotifier(0);

  bool get _animate => widget.animate ?? Avatar.animationsEnabled;

  /// What plays while moving, or null for a still picture.
  _Clip? get _clip {
    if (!_animate || widget.holdOrb || widget.reaction != null) return null;
    return switch (widget.state) {
      AvatarState.speaking => _Clip.talking,
      AvatarState.thinking => _Clip.thinking,
      AvatarState.listening => _Clip.listening,
      AvatarState.idle => widget.wave ? _Clip.wave : _Clip.idle,
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
    final clip = _clip;
    if (clip == null) return;
    final cycles = _controller.duration!.inMicroseconds / clip.duration.inMicroseconds;
    final step = (_controller.value * cycles * clip.length).floor();
    // The step as the cell it shows, so a held frame does not rebuild.
    _tick.value = clip.at(step).index;
  }

  @override
  void didUpdateWidget(Avatar old) {
    super.didUpdateWidget(old);
    _sync(old);
  }

  void _sync(Avatar? old) {
    final clip = _clip;
    if (clip == null) {
      _controller.stop();
      return;
    }
    final waving = widget.state == AvatarState.idle && widget.wave;
    if (waving) {
      // A finished wave is not started again by a rebuild.
      if (old == null || !old.wave || old.state != AvatarState.idle) {
        _controller
          ..duration = clip.duration * _waveCycles
          ..forward(from: 0);
      }
    } else if (!_controller.isAnimating || old?.state != widget.state || old?.wave != widget.wave) {
      _controller
        ..duration = clip.duration
        ..repeat();
    }
  }

  @override
  void dispose() {
    _Sheets.ready.removeListener(_onReady);
    _controller.dispose();
    _tick.dispose();
    super.dispose();
  }

  /// The picture when nothing moves.
  _Frame get _still {
    switch (widget.reaction) {
      case AvatarReaction.lookAside:
        return _Frame.lookAside;
      case AvatarReaction.surprised:
        return _Frame.surprised;
      case null:
    }
    if (widget.holdOrb) return _Frame.holding;
    return switch (widget.state) {
      AvatarState.thinking => _Frame.thinking,
      AvatarState.listening => _Frame.curious,
      AvatarState.speaking => _Frame.talkOpen,
      AvatarState.idle => widget.wave ? _Clip.wave.at(2) : _moodFrame(widget.mood),
    };
  }

  /// The picture of the playing clip ([tick] is its current cell).
  _Frame _frameAt(int tick) {
    final clip = _clip;
    if (clip == null) return _still;
    final waving = widget.state == AvatarState.idle && widget.wave;
    // A wave that has run its cycles settles on the mood's picture.
    if (waving && !_controller.isAnimating) return _moodFrame(widget.mood);
    // Before the first tick of a new clip the old cell may still be there.
    return clip.frames.contains(_Frame(tick)) ? _Frame(tick) : clip.at(0);
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
          builder: (context, tick, _) => CustomPaint(
            painter: _FigurePainter(_frameAt(tick)),
          ),
        ),
      ),
    );
  }
}

/// Draws one frame scaled so her hair-top to soles fill the box height.
class _FigurePainter extends CustomPainter {
  _FigurePainter(this.frame) : super(repaint: _Sheets.ready);

  final _Frame frame;

  @override
  void paint(Canvas canvas, Size size) {
    final image = _Sheets.atlas;
    if (image == null) return;
    final s = size.height / _Sheet.height;
    final dst = Rect.fromLTWH(
      size.width / 2 - _Sheet.centerX * s,
      -_Sheet.top * s,
      _Sheet.cellWidth * s,
      _Sheet.cellHeight * s,
    );
    canvas.drawImageRect(
      image,
      frame.source,
      dst,
      // Mipmapped sampling keeps her line art crisp when the cell is drawn
      // much smaller than its 432 px (the audit header, the badges).
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_FigurePainter old) => old.frame != frame;
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
              painter: _HeadPainter(_moodFrame(widget.mood ?? defaultMoodOf(widget.agent))),
            ),
          ),
        ),
      ),
    );
  }
}

/// A close-up of the head of [frame].
class _HeadPainter extends CustomPainter {
  _HeadPainter(this.frame) : super(repaint: _Sheets.ready);

  final _Frame frame;

  @override
  void paint(Canvas canvas, Size size) {
    final image = _Sheets.atlas;
    if (image == null) return;
    final src = Rect.fromCenter(
      center: frame.source.topLeft + _Sheet.headCenter,
      width: _Sheet.headSide,
      height: _Sheet.headSide,
    );
    canvas.drawImageRect(
      image,
      src,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_HeadPainter old) => old.frame != frame;
}
