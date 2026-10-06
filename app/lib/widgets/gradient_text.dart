import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Text filled with the Gemini gradient (`docs/DESIGN.md` principle 4): the
/// greeting of the home scene, `Cleared!`. Only for "magic" moments.
class GradientText extends StatelessWidget {
  const GradientText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.center,
    this.colors = AppColors.magic,
  });

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => LinearGradient(colors: colors).createShader(rect),
      child: Text(
        text,
        textAlign: textAlign,
        // The fill replaces the color; white keeps the glyphs fully opaque.
        style: (style ?? Theme.of(context).textTheme.displaySmall)?.copyWith(
          color: AppColors.onAccent,
        ),
      ),
    );
  }
}
