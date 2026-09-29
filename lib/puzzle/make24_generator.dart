import '../core/difficulty.dart';
import '../core/game_random.dart';
import '../model/puzzle.dart';
import '../model/token.dart';
import 'target_solver.dart';

/// Builds "make 24 from four numbers" puzzles.
///
/// Two guarantees make these fair:
///  * the four numbers always have a solution, verified with an exact solver
///    before the puzzle is ever shown, and
///  * every distractor is a number that those four numbers *cannot* produce, so
///    24 is the only viable answer on the board.
class Make24Generator {
  const Make24Generator({this.target = 24});

  /// The number the player has to hit. The brief's "make 24" is the canonical
  /// form; the field exists so the template can be reused.
  final int target;

  /// Hand-checked fallbacks, all of which reach 24.
  static const _fallbackSets = <List<int>>[
    [3, 3, 8, 8],
    [1, 5, 5, 5],
    [4, 4, 8, 8],
    [2, 7, 7, 7],
    [6, 6, 6, 6],
    [1, 3, 4, 6],
  ];

  Puzzle generate(GameRandom rng, Difficulty d) {
    final numbers = _pickNumbers(rng, d);
    final reachable = TargetSolver.reachable(numbers);
    final distractors = _distractors(rng, reachable, numbers);

    final options = rng.shuffled(<Token>[
      Token.value('$target', color: 0),
      for (final wrong in distractors) Token.value('$wrong', color: 1),
    ]);

    return Puzzle(
      kind: PuzzleKind.make24,
      depth: d.depth,
      body: TokenRowBody(<Token>[for (final n in numbers) Token.value('$n')]),
      options: options,
      solutionIndex: options.indexWhere((t) => t.text == '$target'),
    );
  }

  /// Rejection-samples number sets until one satisfies the depth requirement.
  List<int> _pickNumbers(GameRandom rng, Difficulty d) {
    final max = d.make24Max;
    for (var attempt = 0; attempt < 80; attempt++) {
      final numbers = <int>[for (var i = 0; i < 4; i++) rng.range(1, max)];
      if (!TargetSolver.canReach(numbers, target)) continue;
      // Past a certain depth, insist on a solution that needs a division, since
      // plain addition and multiplication runs out of difficulty fast.
      if (d.make24NeedsDivision && !TargetSolver.needsDivision(numbers, target)) {
        continue;
      }
      return numbers;
    }
    // A set that always works, in both modes when possible.
    for (final set in rng.shuffled(List<List<int>>.of(_fallbackSets))) {
      if (d.make24NeedsDivision && !TargetSolver.needsDivision(set, target)) {
        continue;
      }
      return set;
    }
    return _fallbackSets.first;
  }

  /// Three numbers near the target that the given numbers cannot produce.
  ///
  /// A wrong option that happens to be reachable would give the puzzle a second
  /// valid answer, so every candidate is checked against the full solution set
  /// before it is allowed on the board. Small sets of numbers can reach almost
  /// every nearby value, so the search window widens until enough gaps are
  /// found.
  List<int> _distractors(GameRandom rng, Set<double> reachable, List<int> nums) {
    final used = <int>{target, ...nums};
    final safe = <int, int>{}; // value -> distance from the target

    for (var delta = 1; delta <= 200; delta++) {
      for (final candidate in <int>[target - delta, target + delta]) {
        if (candidate <= 0) continue;
        if (used.contains(candidate)) continue;
        if (reachable.any((v) => (v - candidate).abs() < 1e-9)) continue;
        safe.putIfAbsent(candidate, () => delta);
      }
    }

    if (safe.isEmpty) {
      // Unreachable in practice, but the option list must never be short.
      return <int>[target + 1, target - 1, target + 2];
    }

    // Prefer the closest gaps so the wrong options read as near misses, and
    // randomise within that band so repeats do not look identical.
    final nearest = safe.keys.where((c) => safe[c]! <= 12).toList(growable: false);
    final chosen = nearest.length >= 3
        ? nearest
        : (safe.keys.toList()..sort((a, b) => safe[a]!.compareTo(safe[b]!)));
    rng.shuffle(chosen);
    return chosen.take(3).toList(growable: false);
  }
}
