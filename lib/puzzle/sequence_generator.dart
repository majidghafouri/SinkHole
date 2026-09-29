import '../core/difficulty.dart';
import '../core/game_random.dart';
import '../model/puzzle.dart';
import '../model/token.dart';
import 'sequence_rules.dart';

/// Builds "what comes next?" number sequences.
///
/// Two things keep these honest. First, a series is only used when exactly one
/// rule can explain it, so the player is never left guessing between two
/// plausible patterns. Second, every wrong option is rejected because it is a
/// number the shown rule could not produce, not because it "looks wrong".
class SequenceGenerator {
  const SequenceGenerator();

  Puzzle generate(GameRandom rng, Difficulty d) {
    final length = d.sequenceLength;
    final pool = d.isTutorial
        ? SequenceRule.values.where((r) => r.isBeginnerFriendly).toList(growable: false)
        : SequenceRule.values;

    for (var attempt = 0; attempt < 40; attempt++) {
      final rule = rng.pick(pool);
      final terms = rule.generate(rng, length);
      if (terms == null) continue;

      final visible = terms.sublist(0, length);
      // A series two different rules both fit has no single right answer.
      if (!isUnambiguous(visible)) continue;
      if (matchingRules(visible).single != rule) continue;

      final answer = terms[length];
      final distractors = _distractors(rng, visible, answer);
      if (distractors == null) continue;

      final options = rng.shuffled(<Token>[
        Token.value('$answer'),
        for (final wrong in distractors) Token.value('$wrong'),
      ]);

      return Puzzle(
        kind: PuzzleKind.sequence,
        depth: d.depth,
        body: TokenRowBody(<Token>[
          for (final t in visible) Token.value('$t'),
        ], chips: false),
        options: options,
        solutionIndex: options.indexWhere((t) => t.text == '$answer'),
      );
    }

    return _fallback(d, length);
  }

  /// Terminates on a hand-checked series, so `generate` can never fail.
  Puzzle _fallback(Difficulty d, int length) {
    final visible = <int>[2];
    for (var i = 1; i < length; i++) {
      visible.add(2 + i * 2);
    }
    final answer = 2 + length * 2;
    final options = <Token>[
      Token.value('${answer + 2}'),
      Token.value('$answer'),
      Token.value('${answer - 1}'),
      Token.value('${answer + 5}'),
    ];
    return Puzzle(
      kind: PuzzleKind.sequence,
      depth: d.depth,
      body: TokenRowBody(<Token>[
        for (final t in visible) Token.value('$t'),
      ], chips: false),
      options: options,
      solutionIndex: options.indexWhere((t) => t.text == '$answer'),
    );
  }

  /// Picks three wrong options that no reading of the series can produce.
  List<int>? _distractors(GameRandom rng, List<int> visible, int answer) {
    final banned = <int>{...visible, answer};
    final last = visible.last;
    final step = answer - last;

    final candidates = <int>[
      answer + 1,
      answer - 1,
      answer + 2,
      answer - 2,
      answer + 3,
      answer - 3,
      last + step * 2, // one step further than the real answer
      last + step + 1,
      last - step,
      last * 2,
      answer * 2,
      answer ~/ 2,
      answer - step,
    ];

    final pool = candidates
        .where((c) => !banned.contains(c) && c > -999 && c < 100000)
        .toSet()
        .toList();
    if (pool.length < 3) return null;
    rng.shuffle(pool);
    return pool.take(3).toList(growable: false);
  }
}
