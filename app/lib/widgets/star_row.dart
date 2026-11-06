import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/tokens.dart';

/// What an audit earned, as three stars: [stars] filled (0–3, clamped), the
/// rest empty. The result the user sees instead of passed / failed; the row's
/// own key is `stars-<n>`.
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.stars, this.size = 18});

  final int stars;

  /// Width of one star.
  final double size;

  static const int slots = 3;

  @override
  Widget build(BuildContext context) {
    final filled = stars.clamp(0, slots);
    return Semantics(
      label: context.l10n.starsLabel(filled),
      excludeSemantics: true,
      child: Row(
        key: Key('stars-$filled'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < slots; i++)
            Icon(
              i < filled ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: i < filled ? AppColors.ember : AppColors.outlineStrong,
            ),
        ],
      ),
    );
  }
}
