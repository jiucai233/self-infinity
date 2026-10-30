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
      'Modified for this app: the expression sheet is downscaled to 256 px cells '
      'and re-encoded as WebP. Not endorsed by YunYueSama or DeepSeek.\n\n$text',
    );
  });
}

/// 大肥鱼, the one companion every agent is (`assets/dafeiyu/`): a chibi
/// whale-girl maid drawn from two sheets.
///
/// * [agent] is kept for the label and for a later 3D model; every agent is
///   drawn as the same character.
/// * [mood] picks her expression; [state] what she is doing: a hand on her
///   chin while thinking, talking while speaking, a tilted head while
///   listening.
/// * [wave] waves a few times.
/// * [holdOrb] holds her hands together in front of her chest; [OrbAvatar]
///   puts the crystal ball there ([orbHandAt]).
/// * [animate] turns the movement off (the picture is then one still frame).
///   It defaults to [animationsEnabled], which tests switch off.
///
/// The sheets are decoded once and shared; until they are, the box is empty.
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
  });

  /// Global switch for the movement; `false` in widget tests.
  static bool animationsEnabled = true;

  /// Decodes the sheets (once). Tests await it so she is drawn at once.
  static Future<void> precache() => _Sheets.load();

  /// Where the hands of a [holdOrb] figure are, in the avatar's own
  /// coordinates (the box is `size * aspect` wide and `size` high).
  static Offset orbHandAt(String agent, double size) {
    final k = unit(agent, size);
    return Offset(size * aspect / 2, 0) + _orbHand * k;
  }

  /// Scale from figure units to logical pixels: the box is 100 x 140 units.
  static double unit(String agent, double size) => size / 140;

  /// Width / height of the avatar's box. Her hair and tail reach a little past
  /// its sides.
  static const double aspect = 100 / 140;

  /// The hands of the ball-holding pose, from the box's top centre, in units.
  static final Offset _orbHand = _Sheet.expressions.toUnits(122, 168);

  final String agent;
  final AvatarMood mood;
  final AvatarState state;
  final bool wave;
  final bool holdOrb;

  /// Height of the figure; it is 5/7 of that wide.
  final double size;
  final bool? animate;

  @override
  State<Avatar> createState() => _AvatarState();
}

/// One of the two sheets and where the figure sits in its cells.
class _Sheet {
  const _Sheet({
    required this.asset,
    required this.cellWidth,
    required this.cellHeight,
    required this.columns,
    required this.centerX,
    required this.top,
    required this.bottom,
  });

  final String asset;
  final double cellWidth;
  final double cellHeight;
  final int columns;

  /// The figure's middle, the top of her hair and her soles, in cell pixels.
  /// Both sheets are cropped so she is the same size in either.
  final double centerX;
  final double top;
  final double bottom;

  double get height => bottom - top;

  /// 4 x 4 still expressions, 256 px cells.
  static const expressions = _Sheet(
    asset: 'assets/dafeiyu/expressions.webp',
    cellWidth: 256,
    cellHeight: 256,
    columns: 4,
    centerX: 128,
    top: 36,
    bottom: 238,
  );

  /// The animated pet sheet: 8 columns x 9 rows of 192 x 208 cells.
  static const sprites = _Sheet(
    asset: 'assets/dafeiyu/spritesheet.webp',
    cellWidth: 192,
    cellHeight: 208,
    columns: 8,
    centerX: 95,
    top: 37,
    bottom: 195,
  );

  ui.Image? get image => identical(this, expressions) ? _Sheets.expressions : _Sheets.sprites;

  /// Cell pixel ([x], [y]) of [cell] as figure units from the box's top centre.
  Offset toUnits(double x, double y) => Offset(x - centerX, y - top) * (140 / height);
}

/// The decoded sheets, shared by every avatar.
abstract final class _Sheets {
  static ui.Image? expressions;
  static ui.Image? sprites;
  static final ValueNotifier<bool> ready = ValueNotifier(false);
  static Future<void>? _loading;

  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final images = await Future.wait([
        _decode(_Sheet.expressions.asset),
        _decode(_Sheet.sprites.asset),
      ]);
      expressions = images[0];
      sprites = images[1];
      ready.value = true;
    } on Object catch (e) {
      // The box stays empty; nothing else depends on her picture.
      debugPrint('大肥鱼: the sheets did not load ($e)');
    }
  }

  static Future<ui.Image> _decode(String asset) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }
}

/// One picture: a cell of a sheet.
class _Frame {
  const _Frame(this.sheet, this.index);

  final _Sheet sheet;

  /// Row-major cell index.
  final int index;

  // Cells of the expression sheet.
  static const neutral = _Frame(_Sheet.expressions, 0);
  static const curious = _Frame(_Sheet.expressions, 1);
  static const sideGlance = _Frame(_Sheet.expressions, 3);
  static const holding = _Frame(_Sheet.expressions, 6);
  static const eyesClosed = _Frame(_Sheet.expressions, 7);
  static const thinking = _Frame(_Sheet.expressions, 8);
  static const pouting = _Frame(_Sheet.expressions, 10);

  // A smile with closed lips, from the talking row.
  static const smile = _Frame(_Sheet.sprites, 8 * 8 + 1);

  Rect get source => Rect.fromLTWH(
    (index % sheet.columns) * sheet.cellWidth,
    (index ~/ sheet.columns) * sheet.cellHeight,
    sheet.cellWidth,
    sheet.cellHeight,
  );

  @override
  bool operator ==(Object other) =>
      other is _Frame && identical(other.sheet, sheet) && other.index == index;

  @override
  int get hashCode => Object.hash(sheet.asset, index);
}

/// A row of the pet sheet played as a loop.
class _Clip {
  const _Clip(this.row, this.frames, this.frameMs);

  final int row;
  final int frames;
  final int frameMs;

  Duration get duration => Duration(milliseconds: frames * frameMs);

  _Frame at(int i) => _Frame(_Sheet.sprites, row * 8 + i % frames);

  static const idle = _Clip(0, 6, 260); // blinks
  static const wave = _Clip(3, 4, 160);
  static const listening = _Clip(5, 8, 240); // looks around, tilts her head
  static const thinking = _Clip(7, 6, 220); // a hand on her chin
  static const talking = _Clip(8, 6, 170);
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
  static const int _waveCycles = 3;
  late final AnimationController _controller = AnimationController(vsync: this);

  /// The frame of the playing clip; repaints only when it changes.
  final ValueNotifier<int> _tick = ValueNotifier(0);

  bool get _animate => widget.animate ?? Avatar.animationsEnabled;

  /// What plays while moving, or null for a still picture.
  _Clip? get _clip {
    if (!_animate || widget.holdOrb) return null;
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
    _tick.value = (_controller.value * cycles * clip.frames).floor();
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
    if (widget.holdOrb) return _Frame.holding;
    return switch (widget.state) {
      AvatarState.thinking => _Frame.thinking,
      AvatarState.listening => _Frame.curious,
      AvatarState.speaking => _Clip.talking.at(2), // mouth open
      AvatarState.idle => widget.wave ? _Clip.wave.at(1) : _moodFrame(widget.mood),
    };
  }

  /// The picture at [tick] of the playing clip.
  _Frame _frameAt(int tick) {
    final clip = _clip;
    if (clip == null) return _still;
    final waving = widget.state == AvatarState.idle && widget.wave;
    // A wave that has run its cycles settles on the mood's picture.
    if (waving && !_controller.isAnimating) return _moodFrame(widget.mood);
    return clip.at(tick);
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
    final sheet = frame.sheet;
    final image = sheet.image;
    if (image == null) return;
    final s = size.height / sheet.height;
    final dst = Rect.fromLTWH(
      size.width / 2 - sheet.centerX * s,
      -sheet.top * s,
      sheet.cellWidth * s,
      sheet.cellHeight * s,
    );
    canvas.drawImageRect(
      image,
      frame.source,
      dst,
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
    final sheet = frame.sheet;
    final image = sheet.image;
    if (image == null) return;
    // The head in the expression sheet: 112 px around (128, 106); the same
    // part of the figure in the other sheet.
    final k = sheet.height / _Sheet.expressions.height;
    final side = 112 * k;
    final cell = frame.source;
    final src = Rect.fromCenter(
      center: cell.topLeft + Offset(sheet.centerX, sheet.top + (106 - _Sheet.expressions.top) * k),
      width: side,
      height: side,
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
