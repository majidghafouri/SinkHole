import 'package:flutter/material.dart';

import '../../model/token.dart';
import '../theme/app_theme.dart';
import '../theme/world_palette.dart';

/// Draws one [Token]: a number, a shape, a blank to fill, or an unlit cell.
///
/// Colour and shape always travel together, which is what makes the puzzles
/// readable without relying on hue alone.
class TokenView extends StatelessWidget {
  const TokenView({
    required this.token,
    required this.world,
    this.size = 34,
    this.color,
    this.opacity = 1.0,
    super.key,
  });

  final Token token;
  final WorldPalette world;

  /// Nominal glyph size in logical pixels.
  final double size;
  final Color? color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    if (token.isEmpty) return SizedBox.square(dimension: size);
    if (token.isBlank) {
      return Icon(
        Icons.help_rounded,
        size: size * 1.05,
        color: (color ?? world.muted).withValues(alpha: opacity * 0.9),
      );
    }

    final tint = color ?? world.accents[token.color % world.accents.length];

    if (token.isGlyph) {
      return Transform.rotate(
        angle: token.rotation,
        child: Icon(
          _iconFor(token.shape!),
          size: size * token.scale,
          color: tint.withValues(alpha: opacity),
        ),
      );
    }

    return Text(
      token.text ?? '',
      style: SinkType.rounded(
        SinkType.numeral.copyWith(
          color: tint.withValues(alpha: opacity),
          fontSize: size * 0.78,
        ),
      ),
    );
  }

  /// Filled Material glyphs keep one visual language across the whole set and
  /// cost no assets.
  static IconData _iconFor(ShapeKind shape) => switch (shape) {
    ShapeKind.circle => Icons.circle,
    ShapeKind.square => Icons.square_rounded,
    ShapeKind.triangle => Icons.change_history_rounded,
    ShapeKind.star => Icons.star_rounded,
    ShapeKind.diamond => Icons.diamond_rounded,
    ShapeKind.hexagon => Icons.hexagon_rounded,
    ShapeKind.heart => Icons.favorite_rounded,
    ShapeKind.cross => Icons.add_rounded,
    ShapeKind.moon => Icons.nightlight_round,
    ShapeKind.arrow => Icons.arrow_upward_rounded,
    ShapeKind.bolt => Icons.bolt_rounded,
    ShapeKind.drop => Icons.water_drop_rounded,
  };
}
