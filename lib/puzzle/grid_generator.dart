import '../core/difficulty.dart';
import '../core/game_random.dart';
import '../model/puzzle.dart';
import '../model/token.dart';

/// Builds a "fill the gap" puzzle on a Latin square.
///
/// Every row and every column contains each value exactly once. That is what
/// makes the puzzle solvable *and* uniquely solvable: a row with two known
/// values forces the third, and four known force the fifth.
///
/// The board size is the interesting part. A 3x3 Latin square has exactly
/// twelve possible layouts no matter how it is generated, so a 3x3-only game
/// runs out of new puzzles quickly. A 4x4 has 576, so the deeper half of a run
/// uses a bigger board, which grows the content space by orders of magnitude and
/// also means the card looks different rather than just holding different
/// numbers.
///
/// Deeper puzzles hide more than one cell. To keep a single unambiguous answer,
/// every hidden cell sits in its own row and its own column and they all carry
/// the same value, so one number legitimately fills all of them.
class GridGenerator {
  const GridGenerator();

  Puzzle generate(GameRandom rng, Difficulty d) {
    final size = d.gridSize;

    for (var attempt = 0; attempt < 32; attempt++) {
      // A column multiplier that is coprime with the size still maps columns
      // onto a permutation of the base row, so uniqueness holds. It just looks
      // less regular and takes longer to spot.
      final mult = d.gridUsesMultiplier
          ? rng.pick(size.isEven ? const <int>[1, 3] : const <int>[1, 2])
          : 1;
      final base = rng.shuffled(<int>[for (var i = 1; i <= size; i++) i]);
      final shifts = rng.shuffled(<int>[for (var i = 0; i < size; i++) i]);

      final values = <String>[];
      for (var r = 0; r < size; r++) {
        for (var c = 0; c < size; c++) {
          values.add('${base[(c * mult + shifts[r]) % size]}');
        }
      }

      final blanks = _pickBlanks(rng, values, size, d.gridBlanks);
      if (blanks == null) continue;
      final answer = values[blanks.first];

      final cells = <Token>[
        for (var i = 0; i < values.length; i++)
          blanks.contains(i) ? Token.blank() : Token.value(values[i]),
      ];

      final options = _buildOptions(rng, values, size);
      return Puzzle(
        kind: PuzzleKind.gridLogic,
        depth: d.depth,
        body: TokenGridBody(cells, rows: size, cols: size),
        options: options,
        solutionIndex: options.indexWhere((t) => t.text == answer),
      );
    }

    return _fallback(d);
  }

  /// Terminates on a hand-checked square so `generate` can never fail.
  Puzzle _fallback(Difficulty d) {
    //  2 3 1
    //  3 1 2
    //  1 2 3
    // Both blanks hold the value 1.
    final values = <String>['2', '3', '1', '3', '1', '2', '1', '2', '3'];
    final blanks = d.gridBlanks >= 2 ? <int>[2, 4] : <int>[2];
    final cells = <Token>[
      for (var i = 0; i < 9; i++)
        blanks.contains(i) ? Token.blank() : Token.value(values[i]),
    ];
    return Puzzle(
      kind: PuzzleKind.gridLogic,
      depth: d.depth,
      body: TokenGridBody(cells),
      options: const <Token>[Token.value('1'), Token.value('2'), Token.value('3')],
      solutionIndex: 0,
    );
  }

  /// Picks hidden cells that all share one value, in distinct rows and columns.
  ///
  /// Distinct rows is what keeps each hidden cell forced by its own row, and the
  /// shared value is what keeps exactly one option correct.
  List<int>? _pickBlanks(GameRandom rng, List<String> values, int size, int count) {
    final cells = values.length;
    if (count <= 1) return <int>[rng.nextInt(cells)];

    // Collect every maximal set of same-valued cells that sits in distinct rows
    // and distinct columns, then take one at random.
    final byValue = <String, List<int>>{};
    for (var i = 0; i < cells; i++) {
      byValue.putIfAbsent(values[i], () => <int>[]).add(i);
    }

    final groups = <List<int>>[];
    for (final group in byValue.values) {
      groups.addAll(_distinctRowAndColumnSets(group, size, count));
    }
    if (groups.isEmpty) return null;
    return rng.pick(groups);
  }

  /// All size-`want` subsets of [candidates] with no two in the same row or
  /// column. Kept simple because the candidate sets are small.
  List<List<int>> _distinctRowAndColumnSets(List<int> candidates, int size, int want) {
    final out = <List<int>>[];
    if (want == 2) {
      for (var a = 0; a < candidates.length; a++) {
        for (var b = a + 1; b < candidates.length; b++) {
          final i = candidates[a];
          final j = candidates[b];
          if (i ~/ size == j ~/ size) continue;
          if (i % size == j % size) continue;
          out.add(<int>[i, j]);
        }
      }
      return out;
    }

    // Three or more: build up one cell at a time.
    void walk(List<int> chosen, int from) {
      if (chosen.length == want) {
        out.add(List<int>.of(chosen));
        return;
      }
      for (var k = from; k < candidates.length; k++) {
        final cell = candidates[k];
        if (chosen.any((c) => c ~/ size == cell ~/ size)) continue;
        if (chosen.any((c) => c % size == cell % size)) continue;
        chosen.add(cell);
        walk(chosen, k + 1);
        chosen.removeLast();
      }
    }

    walk(<int>[], 0);
    return out;
  }

  /// The options: every value the grid actually uses.
  ///
  /// Nothing outside the puzzle's own value set is offered, so the answer is
  /// forced by the row constraint alone. A "impossible" extra option would look
  /// arbitrary, since nothing on the card would rule it out.
  List<Token> _buildOptions(GameRandom rng, List<String> values, int size) {
    final inPlay = values.toSet();
    if (inPlay.length != size) {
      // A Latin square always shows all of its values; this only guards against
      // the option list ever coming up short.
      return <Token>[for (var i = 1; i <= size; i++) Token.value('$i')];
    }
    return rng.shuffled(<Token>[for (final v in inPlay) Token.value(v)]);
  }
}
