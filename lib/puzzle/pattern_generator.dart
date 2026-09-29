import 'dart:math' as math;

import '../core/difficulty.dart';
import '../core/game_random.dart';
import '../model/puzzle.dart';
import '../model/token.dart';

/// Builds repeating shape/color patterns with one beat missing.
///
/// The options are built so that exactly one is correct *and* the three wrong
/// answers each break a different part of the rule: one has the right shape
/// with the wrong color, one the right color with the wrong shape, and one is
/// wrong in both. That forces the player to check both dimensions instead of
/// pattern-matching on one of them.
class PatternGenerator {
  const PatternGenerator();

  /// Colors available for a pattern cycle. Kept to three so a cycle of length
  /// three uses all of them, and so we never exceed the four-colors-on-screen
  /// rule from the design brief.
  static const _cycleColors = <int>[0, 1, 2];

  /// Shapes that read clearly at a glance, ordered so consecutive cycle entries
  /// never look like the same shape.
  static const _shapes = <ShapeKind>[
    ShapeKind.circle,
    ShapeKind.square,
    ShapeKind.triangle,
    ShapeKind.star,
    ShapeKind.diamond,
    ShapeKind.heart,
  ];
  Puzzle generate(GameRandom rng, Difficulty d) {
    final maxCycle = d.patternCycleLength;
    const cycles = Difficulty.patternCycles;

    for (var attempt = 0; attempt < 24; attempt++) {
      final cycleLength = rng.range(2, maxCycle);

      final cycle = <Token>[];
      final shapes = rng.sample(_shapes, cycleLength);
      // A four-beat cycle reuses a color rather than introducing a fifth hue,
      // which keeps the card inside the four-colors-on-screen rule. The shapes
      // are all distinct, so every beat stays individually identifiable and the
      // period is still unambiguous.
      final baseColors = rng.sample(
        _cycleColors,
        math.min(cycleLength, _cycleColors.length),
      );
      for (var i = 0; i < cycleLength; i++) {
        cycle.add(Token.glyph(shapes[i], color: baseColors[i % baseColors.length]));
      }

      // Show the full repeats, then a blank.
      final shown = <Token>[];
      for (var c = 0; c < cycles; c++) {
        shown.addAll(cycle);
      }
      final answer = cycle[shown.length % cycleLength];

      final options = _buildOptions(rng, answer);
      if (options.isEmpty) continue;

      return Puzzle(
        kind: PuzzleKind.pattern,
        depth: d.depth,
        body: TokenRowBody(<Token>[...shown, Token.blank()]),
        options: options,
        solutionIndex: options.indexOf(answer),
      );
    }

    return _fallback(d);
  }

  /// Terminates on a fixed two-beat pattern so `generate` can never fail.
  Puzzle _fallback(Difficulty d) {
    const cycle = <Token>[
      Token.glyph(ShapeKind.circle, color: 0),
      Token.glyph(ShapeKind.star, color: 1),
    ];
    // Always two cycles, so the repeat is visible.
    final shown = <Token>[...cycle, ...cycle];
    final answer = cycle[shown.length % 2];
    final options = <Token>[
      answer,
      const Token.glyph(ShapeKind.circle, color: 1),
      const Token.glyph(ShapeKind.square, color: 1),
      const Token.glyph(ShapeKind.square, color: 0),
    ];
    return Puzzle(
      kind: PuzzleKind.pattern,
      depth: d.depth,
      body: TokenRowBody(<Token>[...shown, Token.blank()]),
      options: options,
      solutionIndex: options.indexOf(answer),
    );
  }

  /// Builds the four options, or null if the palette cannot supply three
  /// distinct wrong answers.
  List<Token> _buildOptions(GameRandom rng, Token answer) {
    final shape = answer.shape!;
    final color = answer.color;

    final otherShapes = _shapes.where((s) => s != shape).toList();
    if (otherShapes.length < 2) {
      return const <Token>[];
    }
    final shapeA = rng.pick(otherShapes);
    final shapeB = rng.pick(otherShapes.where((s) => s != shapeA).toList());
    // The two neighboring indices keep the hues in the same family, so the
    // wrong-color option reads as a near miss rather than an outlier.
    final wrongColorA = (color + 1) % 3;
    final wrongColorB = (color + 2) % 3;

    return rng.shuffled(<Token>[
      answer,
      Token.glyph(shape, color: wrongColorA), // right shape, wrong color
      Token.glyph(shapeA, color: color), // right color, wrong shape
      Token.glyph(shapeB, color: wrongColorB), // wrong in both
    ]);
  }
}
