import 'kind_stat.dart';
import 'puzzle.dart';

/// What ended a run, used to word the result screen.
enum FallReason { timeout, cracks, quit }

extension FallReasonInfo on FallReason {
  String get headline => switch (this) {
    FallReason.timeout => 'THE FLOOR GAVE WAY',
    FallReason.cracks => 'TOO MANY CRACKS',
    FallReason.quit => 'YOU CLIMBED BACK OUT',
  };

  /// The comic sub-line on the result card.
  String get quip => switch (this) {
    FallReason.timeout => 'Bloop squishes. The floor was not sorry.',
    FallReason.cracks => 'Three cracks. Bloop is more hole than blob.',
    FallReason.quit => 'Bloop climbs back up the ladder, unimpressed.',
  };
}

/// One puzzle attempt, kept for the end-of-run stats.
class SolveRecord {
  const SolveRecord({
    required this.kind,
    required this.depth,
    required this.correct,
    required this.seconds,
    required this.wasBoss,
  });

  final PuzzleKind kind;
  final int depth;
  final bool correct;
  final double seconds;

  /// True when this attempt was one step of a boss round.
  final bool wasBoss;
}

/// The immutable summary of a finished run.
class RunResult {
  const RunResult({
    required this.depth,
    required this.bestStreak,
    required this.reason,
    required this.records,
    required this.daily,
    required this.worldIndex,
    required this.elapsedSeconds,
    required this.powerUpsUsed,
  });

  /// Deepest depth reached. This is the score.
  final int depth;

  /// Longest consecutive-correct streak during the run.
  final int bestStreak;

  final FallReason reason;
  final List<SolveRecord> records;

  /// Whether this was the daily seeded challenge.
  final bool daily;

  /// Which world theme the run ended in.
  final int worldIndex;

  /// Wall-clock length of the run.
  final double elapsedSeconds;

  final int powerUpsUsed;

  int get correctAnswers => records.where((r) => r.correct).length;

  int get wrongAnswers => records.length - correctAnswers;

  int get accuracy =>
      records.isEmpty ? 0 : (correctAnswers / records.length * 100).round();

  /// Per-type breakdown, fastest average solve first.
  List<KindStat> get kindStats => KindStat.fromRecords(
    records.map((r) => (kind: r.kind, correct: r.correct, seconds: r.seconds)),
  );

  /// The player's fastest puzzle type this run, if any were cleared.
  KindStat? get fastestKind {
    final stats = kindStats.where((s) => s.solved > 0).toList()..sort();
    return stats.isEmpty ? null : stats.first;
  }

  /// The puzzle type the player cleared most often this run.
  KindStat? get topKind {
    KindStat? best;
    for (final stat in kindStats) {
      if (best == null || stat.solved > best.solved) best = stat;
    }
    return best;
  }
}
