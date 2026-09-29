import '../core/difficulty.dart';
import '../core/game_random.dart';
import '../model/puzzle.dart';
import '../model/token.dart';

/// Builds "memorize a flash, then recall where a symbol was" puzzles.
///
/// The card flashes a 3x3 grid for [Difficulty.memoryFlashMs] milliseconds, then
/// hides it and asks which cell held a particular symbol. The three wrong
/// options are other *occupied* cells rather than empty ones, so the player has
/// to recall the symbol's position instead of just noticing which cells were lit.
class MemoryGenerator {
  const MemoryGenerator();

  /// Shapes used for the flash. Every symbol is drawn in the same color so the
  /// question stays unambiguous, and so the card never exceeds four colors.
  static const _shapes = <ShapeKind>[
    ShapeKind.star,
    ShapeKind.heart,
    ShapeKind.bolt,
    ShapeKind.drop,
    ShapeKind.moon,
    ShapeKind.diamond,
  ];

  static const int _flashColor = 0;

  Puzzle generate(GameRandom rng, Difficulty d) {
    for (var attempt = 0; attempt < 24; attempt++) {
      final count = d.memorySymbols < 4 ? 4 : d.memorySymbols;
      final shapes = rng.sample(_shapes, count);
      final litCells = rng.sample(<int>[for (var i = 0; i < 9; i++) i], count);

      final grid = List<Token>.filled(9, const Token.empty());
      for (var i = 0; i < count; i++) {
        grid[litCells[i]] = Token.glyph(shapes[i], color: _flashColor);
      }

      final target = rng.nextInt(count);
      final answerCell = litCells[target];
      // Decoys are other lit cells, so a "which cell was empty" guess fails.
      final decoys = litCells.where((c) => c != answerCell).take(3).toList();
      if (decoys.length < 3) continue;

      final optionCells = rng.shuffled(<int>[answerCell, ...decoys]);
      return Puzzle(
        kind: PuzzleKind.memory,
        depth: d.depth,
        body: TokenGridBody(
          grid,
          flashMs: d.memoryFlashMs,
          revealLabel: Token.glyph(shapes[target], color: _flashColor),
        ),
        options: <Token>[for (final c in optionCells) Token.value(cellLabels[c])],
        solutionIndex: optionCells.indexOf(answerCell),
      );
    }

    return _fallback(d);
  }

  /// Terminates on a fixed layout so `generate` can never fail.
  Puzzle _fallback(Difficulty d) {
    // Corners and edge midpoints lit, centre dark. The star was at A.
    final litCells = <int>[0, 2, 4, 6, 8];
    final shapes = _shapes.take(litCells.length).toList();
    final grid = List<Token>.filled(9, const Token.empty());
    for (var i = 0; i < litCells.length; i++) {
      grid[litCells[i]] = Token.glyph(shapes[i], color: _flashColor);
    }
    final optionCells = <int>[0, 2, 4, 6];
    return Puzzle(
      kind: PuzzleKind.memory,
      depth: d.depth,
      body: TokenGridBody(
        grid,
        flashMs: d.memoryFlashMs,
        revealLabel: Token.glyph(shapes.first, color: _flashColor),
      ),
      options: <Token>[for (final c in optionCells) Token.value(cellLabels[c])],
      solutionIndex: 0,
    );
  }
}
