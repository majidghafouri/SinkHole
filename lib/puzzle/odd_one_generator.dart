import '../core/difficulty.dart';
import '../core/game_random.dart';
import '../model/puzzle.dart';
import '../model/token.dart';

/// Builds "spot the one that does not belong" puzzles.
///
/// Three of the four options are identical and exactly one differs. The ramp
/// controls *how* it differs:
///
///  * early on the odd one changes two properties at once, so it is unmissable
///    while the player is still learning the mechanic;
///  * later it changes a single, subtler property - size, rotation, or a
///    neighboring color - which is a real spot-the-difference.
///
/// Changing exactly the right number of properties is what keeps it fair: there
/// is always one correct answer, and always a real reason behind it.
class OddOneGenerator {
  const OddOneGenerator();

  /// Shapes where a rotation is actually visible. Symmetric shapes would make a
  /// rotation difference impossible to see, so they are excluded.
  static const _rotatable = <ShapeKind>{
    ShapeKind.triangle,
    ShapeKind.arrow,
    ShapeKind.drop,
    ShapeKind.moon,
    ShapeKind.bolt,
  };

  static const _shapes = <ShapeKind>[
    ShapeKind.circle,
    ShapeKind.square,
    ShapeKind.triangle,
    ShapeKind.star,
    ShapeKind.diamond,
    ShapeKind.hexagon,
    ShapeKind.heart,
    ShapeKind.cross,
    ShapeKind.arrow,
    ShapeKind.bolt,
    ShapeKind.drop,
  ];

  Puzzle generate(GameRandom rng, Difficulty d) {
    final dimensions = d.oddOneDifferences;
    for (var attempt = 0; attempt < 24; attempt++) {
      final base = Token.glyph(rng.pick(_shapes), color: rng.nextInt(3));
      final odd = _mutate(rng, base, dimensions);
      if (odd == null || odd == base) continue;

      final options = rng.shuffled(<Token>[base, base, base, odd]);
      return Puzzle(
        kind: PuzzleKind.oddOne,
        depth: d.depth,
        // The board mirrors the options: the player reads the row, then taps the
        // odd chip down in the thumb zone.
        body: TokenRowBody(options, chips: false),
        options: options,
        solutionIndex: options.indexOf(odd),
      );
    }

    return _fallback(d);
  }

  /// Terminates on a fixed set so `generate` can never fail.
  Puzzle _fallback(Difficulty d) {
    const normal = Token.glyph(ShapeKind.circle, color: 0);
    final odd = d.oddOneDifferences >= 2
        ? const Token.glyph(ShapeKind.square, color: 1)
        : const Token.glyph(ShapeKind.circle, color: 0, scale: 0.74);
    final options = <Token>[normal, odd, normal, normal];
    return Puzzle(
      kind: PuzzleKind.oddOne,
      depth: d.depth,
      body: TokenRowBody(options, chips: false),
      options: options,
      solutionIndex: options.indexOf(odd),
    );
  }

  /// Builds the odd one out by changing [dimensions] properties of [base].
  Token? _mutate(GameRandom rng, Token base, int dimensions) {
    final changes = _chooseChanges(rng, base.shape!, dimensions);
    if (changes == null) return null;

    var next = base;
    for (final change in changes) {
      switch (change) {
        case _Change.shape:
          final alternatives = _shapes
              .where((s) => s != base.shape)
              .toList(growable: false);
          if (alternatives.isEmpty) return null;
          next = Token.glyph(
            rng.pick(alternatives),
            color: next.color,
            scale: next.scale,
            rotation: next.rotation,
          );
        case _Change.color:
          // A neighbouring index keeps the hue family, which is subtler than a
          // jump straight across the palette. Either neighbour is allowed, so
          // the same base colour can be contrasted two ways.
          next = next.copyWith(color: (next.color + (rng.chance(0.5) ? 1 : 2)) % 3);
        case _Change.scale:
          // Four steps rather than two: a barely-there nudge and an obvious one,
          // so the same shape pair can appear as a near miss or a clear oddity.
          next = next.copyWith(scale: rng.pick(const <double>[0.68, 0.78, 1.28, 1.42]));
        case _Change.rotation:
          next = next.copyWith(
            rotation: rng.pick(const <double>[0.45, 0.8, -0.45, -0.8]),
          );
      }
    }
    return next;
  }

  /// Decides which properties to change so the odd one reads as either obvious
  /// or subtle, matching the current depth.
  List<_Change>? _chooseChanges(GameRandom rng, ShapeKind shape, int dimensions) {
    if (dimensions >= 2) {
      // A shape swap is always readable, so pair it with either a color change
      // or, for a rotatable shape, a size change. Both are unmistakable.
      if (_rotatable.contains(shape) && rng.chance(0.4)) {
        return const <_Change>[_Change.shape, _Change.scale];
      }
      return const <_Change>[_Change.shape, _Change.color];
    }

    final single = <_Change>[
      _Change.scale,
      _Change.color,
      if (_rotatable.contains(shape)) _Change.rotation,
    ];
    return <_Change>[rng.pick(single)];
  }
}

enum _Change { shape, color, scale, rotation }
