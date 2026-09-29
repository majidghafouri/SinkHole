import 'dart:math' as math;

/// Deterministic, seedable random source.
///
/// A run is fully described by its seed, so a daily challenge can hand the same
/// puzzles to every player and a replay can reproduce a run exactly.
class GameRandom {
  GameRandom(int seed) : _state = (seed & 0xFFFFFFFF) | 1;

  int _state;

  /// Mulberry32: small, fast, and good enough for puzzle generation.
  int _nextInt32() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _state;
    t = _imul(t ^ (t >>> 15), t | 1);
    t = (t + _imul(t ^ (t >>> 7), t | 61)) & 0xFFFFFFFF;
    return (t ^ (t >>> 14)) & 0xFFFFFFFF;
  }

  static int _imul(int a, int b) {
    final lo = (a & 0xFFFF) * (b & 0xFFFF);
    final hi = (a >> 16) * (b & 0xFFFF);
    return (lo + ((hi & 0xFFFF) << 16)) & 0xFFFFFFFF;
  }

  /// Uniform double in `[0, 1)`.
  double nextDouble() => _nextInt32() / 4294967296.0;

  /// Uniform integer in `[0, max)`. Returns 0 when [max] is not positive.
  int nextInt(int max) {
    if (max <= 0) return 0;
    return _nextInt32() % max;
  }

  /// Uniform integer in the inclusive range `[min, max]`.
  int range(int min, int max) {
    if (max <= min) return min;
    return min + nextInt(max - min + 1);
  }

  /// Random element of [items].
  T pick<T>(List<T> items) => items[nextInt(items.length)];

  /// True with probability [p].
  bool chance(double p) => nextDouble() < p;

  /// Returns a uniformly random element, or null when [items] is empty.
  T? pickOrNull<T>(List<T> items) => items.isEmpty ? null : items[nextInt(items.length)];

  /// Picks using integer [weights]. Returns -1 when the list is empty or all
  /// weights are non-positive.
  int weightedIndex(List<int> weights) {
    var total = 0;
    for (final w in weights) {
      if (w > 0) total += w;
    }
    if (total <= 0) return -1;
    var roll = nextInt(total);
    for (var i = 0; i < weights.length; i++) {
      final w = weights[i];
      if (w <= 0) continue;
      if (roll < w) return i;
      roll -= w;
    }
    return weights.length - 1;
  }

  /// In-place Fisher-Yates shuffle.
  void shuffle<T>(List<T> items) {
    for (var i = items.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = items[i];
      items[i] = items[j];
      items[j] = tmp;
    }
  }

  /// Returns a shuffled copy of [items].
  List<T> shuffled<T>(List<T> items) {
    final copy = List<T>.of(items);
    shuffle(copy);
    return copy;
  }

  /// Picks [count] distinct elements from [items], or fewer if the pool is small.
  List<T> sample<T>(List<T> items, int count) {
    return shuffled(items).take(count).toList(growable: false);
  }

  /// Returns a seed derived from this generator, for spawning sub-streams.
  int fork() => _nextInt32();
}

/// Builds the seed used by the daily seeded challenge.
int dailySeedFor(DateTime day) {
  final y = day.year;
  final m = day.month;
  final d = day.day;
  // FNV-1a over "YYYY-MM-DD" so neighbouring days land far apart.
  var hash = 0x811C9DC5;
  for (final c
      in 'sinkhole-$y-${m.toString().padLeft(2, '0')}-'
              '${d.toString().padLeft(2, '0')}'
          .codeUnits) {
    hash ^= c;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// Stable key for a calendar day, used for the daily leaderboard.
String dailyKeyFor(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Local midnight for the day containing [now].
DateTime startOfDay(DateTime now) => DateTime(now.year, now.month, now.day);

int clampInt(int value, int min, int max) =>
    value < min ? min : (value > max ? max : value);

double clampDouble(double value, double min, double max) =>
    value < min ? min : (value > max ? max : value);

/// Linear interpolation.
double lerpDouble(double a, double b, double t) => a + (b - a) * t;

extension IterableShuffleExt<T> on Iterable<T> {
  List<T> toShuffledList(math.Random random) {
    final copy = toList();
    for (var i = copy.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final tmp = copy[i];
      copy[i] = copy[j];
      copy[j] = tmp;
    }
    return copy;
  }
}
