import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';

import '../theme/tokens.dart';

/// The line-art pieces of the life tree (`assets/ink/*.svg`): a blossom, an
/// open bud, a closed bud and a leaf, drawn by hand and pasted onto the
/// branches by [InkTree].
///
/// The SVGs are deliberately simple: `<path>` elements with a `d`, an optional
/// `transform="rotate(a cx cy)"` and a `data-role` naming how to paint them —
/// so their colors come from the design tokens, not from the files:
///
/// | role | paint |
/// |---|---|
/// | `line` | ink stroke |
/// | `hair` | thin ink stroke |
/// | `dim` | thin [AppColors.textTertiary] stroke |
/// | `paper` | [AppColors.background] fill (hides the lines behind it) |
/// | `petal` | pale [AppColors.ember] fill |
/// | `accent` | [AppColors.ember] fill |
/// | `tint` | pale fill in the tint color of the call |
///
/// The root `<svg>` names the anchor (`data-anchor="x y"`, in its 0–100
/// viewBox): the point that sits on the branch.
class InkSprite {
  InkSprite(this.anchor, this.parts);

  final Offset anchor;
  final List<({Set<String> roles, Path path})> parts;

  static final RegExp _path = RegExp(r'<path\b([^>]*)/>');
  static final RegExp _anchor = RegExp(r'data-anchor="([-\d.]+) ([-\d.]+)"');
  static final RegExp _rotate = RegExp(r'rotate\(([-\d.]+) ([-\d.]+) ([-\d.]+)\)');

  static String? _attr(String attrs, String name) =>
      RegExp('$name="([^"]*)"').firstMatch(attrs)?.group(1);

  /// Reads the subset of SVG described above.
  static InkSprite parse(String svg) {
    final a = _anchor.firstMatch(svg);
    final anchor = a == null
        ? const Offset(50, 50)
        : Offset(double.parse(a.group(1)!), double.parse(a.group(2)!));
    final parts = <({Set<String> roles, Path path})>[];
    for (final m in _path.allMatches(svg)) {
      final attrs = m.group(1)!;
      final d = _attr(attrs, 'd');
      if (d == null) continue;
      var path = parseSvgPathData(d);
      final r = _rotate.firstMatch(_attr(attrs, 'transform') ?? '');
      if (r != null) {
        final angle = double.parse(r.group(1)!) * math.pi / 180;
        final cx = double.parse(r.group(2)!);
        final cy = double.parse(r.group(3)!);
        final m4 = Matrix4.identity()
          ..translateByDouble(cx, cy, 0, 1)
          ..rotateZ(angle)
          ..translateByDouble(-cx, -cy, 0, 1);
        path = path.transform(m4.storage);
      }
      final roles = (_attr(attrs, 'data-role') ?? 'line').split(' ').toSet();
      parts.add((roles: roles, path: path));
    }
    return InkSprite(anchor, parts);
  }

  /// Paints the sprite with its anchor at [at], turned by [angle] (radians,
  /// 0 = pointing up), [size] px tall. Strokes keep [line] px whatever the size.
  void paint(
    Canvas canvas,
    Offset at, {
    required double size,
    double angle = 0,
    double line = 1.2,
    Color tint = AppColors.textPrimary,
    Color ink = AppColors.textPrimary,
  }) {
    final scale = size / 100;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    canvas.scale(scale);
    canvas.translate(-anchor.dx, -anchor.dy);
    Paint stroke(Color color, double px) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = px / scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final part in parts) {
      final r = part.roles;
      if (r.contains('paper')) canvas.drawPath(part.path, Paint()..color = AppColors.background);
      if (r.contains('petal')) {
        canvas.drawPath(part.path, Paint()..color = AppColors.ember.withValues(alpha: 0.28));
      }
      if (r.contains('tint')) {
        canvas.drawPath(part.path, Paint()..color = AppColors.background);
        canvas.drawPath(part.path, Paint()..color = tint.withValues(alpha: 0.16));
      }
      if (r.contains('accent')) canvas.drawPath(part.path, Paint()..color = AppColors.ember);
      if (r.contains('line')) {
        canvas.drawPath(part.path, stroke(r.contains('tint') ? tint : ink, line));
      }
      if (r.contains('hair')) {
        canvas.drawPath(part.path, stroke(ink.withValues(alpha: 0.7), line * 0.6));
      }
      if (r.contains('dim')) canvas.drawPath(part.path, stroke(AppColors.textTertiary, line * 0.9));
    }
    canvas.restore();
  }
}

/// All the pieces, loaded once from the asset bundle.
class InkSprites {
  InkSprites({required this.blossom, required this.bud, required this.closed, required this.leaf});

  final InkSprite blossom;
  final InkSprite bud;
  final InkSprite closed;
  final InkSprite leaf;

  static Future<InkSprites>? _loading;

  /// The sprites; the first call loads them, later calls share the result.
  static Future<InkSprites> load([AssetBundle? bundle]) => _loading ??= _load(bundle ?? rootBundle);

  static Future<InkSprites> _load(AssetBundle bundle) async {
    Future<InkSprite> one(String name) async =>
        InkSprite.parse(await bundle.loadString('assets/ink/$name.svg'));
    return InkSprites(
      blossom: await one('blossom'),
      bud: await one('bud'),
      closed: await one('closed'),
      leaf: await one('leaf'),
    );
  }
}
