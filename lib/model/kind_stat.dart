import 'puzzle.dart';

/// Per-puzzle-type performance, used by the result and stats screens.
class KindStat implements Comparable<KindStat> {
  const KindStat({
    required this.kind,
    required this.solved,
    required this.attempts,
    required this.averageSeconds,
  });

  final PuzzleKind kind;

  /// How many of this type the player cleared.
  final int solved;

  /// How many of this type were shown, cleared or not.
  final int attempts;

  /// Mean solve time over the cleared ones. Zero when none were cleared.
  final double averageSeconds;

  int get accuracy => attempts == 0 ? 0 : (solved / attempts * 100).round();

  /// Sorts fastest-average first, with at least one solve required.
  @override
  int compareTo(KindStat other) => averageSeconds.compareTo(other.averageSeconds);

  /// Collapses a run's records into one entry per puzzle type.
  static List<KindStat> fromRecords(
    Iterable<({PuzzleKind kind, bool correct, double seconds})> records,
  ) {
    final attempts = <PuzzleKind, int>{};
    final solved = <PuzzleKind, int>{};
    final totalSeconds = <PuzzleKind, double>{};

    for (final r in records) {
      attempts[r.kind] = (attempts[r.kind] ?? 0) + 1;
      if (r.correct) {
        solved[r.kind] = (solved[r.kind] ?? 0) + 1;
        totalSeconds[r.kind] = (totalSeconds[r.kind] ?? 0) + r.seconds;
      }
    }

    return attempts.keys
        .map((kind) {
          final n = solved[kind] ?? 0;
          return KindStat(
            kind: kind,
            solved: n,
            attempts: attempts[kind] ?? 0,
            averageSeconds: n == 0 ? 0 : totalSeconds[kind]! / n,
          );
        })
        .toList(growable: false);
  }
}
