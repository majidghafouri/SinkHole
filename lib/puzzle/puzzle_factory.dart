import 'dart:math' as math;

import '../core/difficulty.dart';
import '../core/game_random.dart';
import '../model/puzzle.dart';
import 'grid_generator.dart';
import 'make24_generator.dart';
import 'memory_generator.dart';
import 'odd_one_generator.dart';
import 'pattern_generator.dart';
import 'puzzle_fingerprint.dart';
import 'sequence_generator.dart';

/// Chooses which puzzle template to show next.
///
/// Two jobs. The first is rotation: templates come from a weighted bag that
/// changes shape as the run deepens, and the previous kind is excluded so the
/// player never gets the same puzzle type twice in a row.
///
/// The second is freshness. A run accumulates the fingerprints of everything it
/// has already shown, and the factory re-rolls until it finds something new. If a
/// template's content space is genuinely exhausted, it falls through to a
/// different template rather than repeating, so a long run degrades into
/// "more varied but slightly easier" instead of "the same puzzle again".
class PuzzleFactory {
  PuzzleFactory()
    : _sequence = const SequenceGenerator(),
      _pattern = const PatternGenerator(),
      _make24 = const Make24Generator(),
      _grid = const GridGenerator(),
      _memory = const MemoryGenerator(),
      _oddOne = const OddOneGenerator();

  final SequenceGenerator _sequence;
  final PatternGenerator _pattern;
  final Make24Generator _make24;
  final GridGenerator _grid;
  final MemoryGenerator _memory;
  final OddOneGenerator _oddOne;

  /// How many times to re-roll a template before giving up on it and moving to
  /// another one.
  static const int _attemptsPerKind = 10;

  /// The opening three puzzles are scripted so they teach the timer, tapping,
  /// and the crack penalty by doing rather than through a tutorial screen.
  static const _introScript = <PuzzleKind>[
    PuzzleKind.sequence,
    PuzzleKind.pattern,
    PuzzleKind.oddOne,
  ];

  /// Weights per kind at shallow depth, before anything is unlocked.
  static const _earlyWeights = <PuzzleKind, int>{
    PuzzleKind.sequence: 3,
    PuzzleKind.pattern: 3,
    PuzzleKind.oddOne: 2,
  };

  /// Weights once every template is available.
  static const _lateWeights = <PuzzleKind, int>{
    PuzzleKind.sequence: 3,
    PuzzleKind.pattern: 3,
    PuzzleKind.oddOne: 2,
    PuzzleKind.make24: 3,
    PuzzleKind.gridLogic: 2,
    PuzzleKind.memory: 3,
  };

  /// A puzzle type unlocks at this depth.
  static const _unlockDepth = <PuzzleKind, int>{
    PuzzleKind.sequence: 1,
    PuzzleKind.pattern: 1,
    PuzzleKind.oddOne: 1,
    PuzzleKind.make24: 4,
    PuzzleKind.memory: 5,
    PuzzleKind.gridLogic: 6,
  };

  /// Builds the puzzle for [depth], avoiding [lastKind] and anything whose
  /// fingerprint is in [seen].
  Puzzle build(
    GameRandom rng,
    int depth, {
    PuzzleKind? lastKind,
    bool boss = false,
    Set<String> seen = const <String>{},
    double skillOffset = 0,
  }) {
    final d = Difficulty(depth, skillOffset: skillOffset);
    // Ranked best-first, so if the freshest template is out of ideas the
    // fallback order is sensible rather than arbitrary.
    final order = _rankKinds(rng, d, lastKind, boss);

    Puzzle? firstResult;
    for (var rank = 0; rank < order.length; rank++) {
      final kind = order[rank];
      for (var attempt = 0; attempt < _attemptsPerKind; attempt++) {
        final puzzle = _build(rng, d, kind);
        final key = puzzleFingerprint(puzzle);
        if (!seen.contains(key)) return puzzle;
        firstResult ??= puzzle;
      }
    }

    // Every template's space is exhausted at this depth. Returning the
    // shallowest-ranked result is better than failing, and the run is far deeper
    // than any content pool at this point.
    return firstResult ?? _build(rng, d, order.first);
  }

  /// Picks a template for [depth]. A boss round deliberately reaches into the
  /// hardest unlocked types, so it feels like an escalation.
  PuzzleKind pickKind(
    GameRandom rng,
    int depth, {
    PuzzleKind? lastKind,
    bool boss = false,
  }) => _rankKinds(rng, Difficulty(depth), lastKind, boss).first;

  /// Templates ordered by preference, heaviest weight first.
  List<PuzzleKind> _rankKinds(
    GameRandom rng,
    Difficulty d,
    PuzzleKind? lastKind,
    bool boss,
  ) {
    if (!boss && d.depth <= _introScript.length) {
      return <PuzzleKind>[_introScript[d.depth - 1]];
    }

    final pool = <PuzzleKind>[];
    final weights = <int>[];
    final source = d.unlockRamp >= 1 ? _lateWeights : _earlyWeights;
    source.forEach((kind, weight) {
      if (d.depth < (_unlockDepth[kind] ?? 1)) return;
      pool.add(kind);
      if (boss) {
        // A boss is a multi-step slog, so it is built from the slower types.
        final favoured =
            kind == PuzzleKind.make24 ||
            kind == PuzzleKind.memory ||
            kind == PuzzleKind.gridLogic;
        weights.add(favoured ? weight + 2 : weight);
      } else {
        weights.add(weight);
      }
    });

    if (pool.isEmpty) return <PuzzleKind>[lastKind ?? PuzzleKind.sequence];

    // Avoid a repeat of the previous kind when anything else is available.
    if (pool.length > 1 && lastKind != null) {
      final previous = pool.indexOf(lastKind);
      if (previous >= 0) {
        pool.removeAt(previous);
        weights.removeAt(previous);
      }
    }

    final ranked = <PuzzleKind>[];
    while (pool.isNotEmpty) {
      final pick = rng.weightedIndex(weights);
      ranked.add(pool[pick]);
      pool.removeAt(pick);
      weights.removeAt(pick);
    }
    return ranked;
  }

  Puzzle _build(GameRandom rng, Difficulty d, PuzzleKind kind) => switch (kind) {
    PuzzleKind.sequence => _sequence.generate(rng, d),
    PuzzleKind.pattern => _pattern.generate(rng, d),
    PuzzleKind.make24 => _make24.generate(rng, d),
    PuzzleKind.gridLogic => _grid.generate(rng, d),
    PuzzleKind.memory => _memory.generate(rng, d),
    PuzzleKind.oddOne => _oddOne.generate(rng, d),
  };

  /// Every kind the player has unlocked at [depth], for the run summary.
  static List<PuzzleKind> unlockedAt(int depth) => PuzzleKind.values
      .where((k) => depth >= (_unlockDepth[k] ?? 1))
      .toList(growable: false);

  /// Estimated number of distinct puzzles the templates have between them, used
  /// by the tests that guard against the pool drying up.
  static int approximateContentSpace(int depth) {
    final d = Difficulty(depth);
    final size = d.gridSize;
    // Latin squares: order 3 has 12, order 4 has 576.
    final latinSquares = size == 3 ? 12 : 576;
    // Blanks multiply the layouts, and a 3x3 or 4x4 board can be blanked in
    // any one of its cells.
    final gridSpace = latinSquares * size * size;
    final patternSpace = math.max(1, d.patternCycleLength - 1) * 2;
    return gridSpace + 5000 + patternSpace;
  }
}
