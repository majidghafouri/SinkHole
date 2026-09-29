import 'package:sinkhole/model/puzzle.dart';

/// A single entry on the daily leaderboard.
///
/// Local-only for now: the run seed is shared, so comparing depths against your
/// own past attempts on the same day already produces the ghost-run tension the
/// brief is after. The shape is a row so a real backend can be dropped in
/// without touching the UI.
class DailyEntry {
  const DailyEntry({required this.depth, required this.at, required this.wasNewBest});

  final int depth;
  final DateTime at;
  final bool wasNewBest;

  Map<String, dynamic> toJson() => {'depth': depth, 'at': at.toIso8601String()};

  static DailyEntry fromJson(Map<dynamic, dynamic> json) => DailyEntry(
    depth: (json['depth'] as num?)?.toInt() ?? 0,
    at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
    wasNewBest: false,
  );
}

/// A recorded run that can be replayed as a "ghost" while the player descends.
///
/// Rather than a full replay of inputs, this stores the per-depth outcome. That
/// is enough to place the ghost marker on the floor and flash it at the depths
/// where the ghost cracked, which is the part players actually notice.
class GhostRun {
  const GhostRun({
    required this.depth,
    required this.crackDepths,
    required this.records,
    required this.at,
  });

  /// The depth the ghost fell at. The marker sits here during a later run.
  final int depth;

  /// Depths where this run took a crack.
  final List<int> crackDepths;

  final List<({PuzzleKind kind, int depth, bool correct, double seconds})> records;

  final DateTime at;

  int get correctAnswers => records.where((r) => r.correct).length;

  Map<String, dynamic> toJson() => {
    'depth': depth,
    'at': at.toIso8601String(),
    'cracks': crackDepths,
    'records': records
        .map(
          (r) => {'k': r.kind.name, 'd': r.depth, 'c': r.correct ? 1 : 0, 's': r.seconds},
        )
        .toList(),
  };

  static GhostRun fromJson(Map<dynamic, dynamic> json) {
    final rawRecords = (json['records'] as List?) ?? const <Object>[];
    return GhostRun(
      depth: (json['depth'] as num?)?.toInt() ?? 0,
      crackDepths: ((json['cracks'] as List?) ?? const <Object>[])
          .map((e) => (e as num).toInt())
          .toList(growable: false),
      at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
      records: rawRecords
          .map((e) {
            final m = e as Map<dynamic, dynamic>;
            return (
              kind: PuzzleKind.values.firstWhere(
                (k) => k.name == m['k'],
                orElse: () => PuzzleKind.sequence,
              ),
              depth: (m['d'] as num?)?.toInt() ?? 0,
              correct: (m['c'] as num?)?.toInt() == 1,
              seconds: (m['s'] as num?)?.toDouble() ?? 0,
            );
          })
          .toList(growable: false),
    );
  }
}
