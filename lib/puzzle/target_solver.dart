/// Exact rational arithmetic for the `make 24` generator.
///
/// Fractions keep the search exact: floating point would let a genuinely
/// unsolvable set look solvable (or the reverse) after a division.
class Frac implements Comparable<Frac> {
  const Frac(this.numerator, [this.denominator = 1]) : assert(denominator != 0);

  final int numerator;
  final int denominator;

  static const Frac one = Frac(1);

  double get value => numerator / denominator;

  bool get isInteger => numerator % denominator == 0;

  int get asInteger => numerator ~/ denominator;

  Frac operator +(Frac other) => Frac(
    numerator * other.denominator + other.numerator * denominator,
    denominator * other.denominator,
  );

  Frac operator -(Frac other) => Frac(
    numerator * other.denominator - other.numerator * denominator,
    denominator * other.denominator,
  );

  Frac operator *(Frac other) =>
      Frac(numerator * other.numerator, denominator * other.denominator);

  Frac operator /(Frac other) {
    if (other.numerator == 0) {
      throw ArgumentError('division by zero');
    }
    return Frac(numerator * other.denominator, denominator * other.numerator);
  }

  Frac get negated => Frac(-numerator, denominator);

  Frac get reduced {
    if (denominator == 0) return this;
    var n = numerator;
    var d = denominator;
    if (d < 0) {
      n = -n;
      d = -d;
    }
    var a = n.abs();
    var b = d;
    while (b != 0) {
      final t = a % b;
      a = b;
      b = t;
    }
    if (a == 0) return const Frac(0, 1);
    return Frac(n ~/ a, d ~/ a);
  }

  @override
  int compareTo(Frac other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) =>
      other is Frac && other.numerator == numerator && other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() => denominator == 1 ? '$numerator' : '$numerator/$denominator';
}

/// Solves "reach the target from these numbers" puzzles.
class TargetSolver {
  const TargetSolver._();

  /// Bounded memo for [reachable]. The search is pure and the number sets are
  /// small, so the same set recurs constantly: rejection sampling at shallow
  /// depths redraws from a range of only six, and the generator asks about the
  /// same sets over and over. Without this, a single make 24 puzzle at depth one
  /// costs about a second.
  ///
  /// Bounded because a long run eventually outgrows any fixed budget, and a run
  /// should not hold every set it has ever tried.
  static final Map<String, Set<double>> _cache = {};
  static const _cacheLimit = 4096;

  static String _key(List<int> numbers, bool allowDivision) {
    // Sorted, because the value set cannot depend on the order the numbers were
    // drawn in, and the caller may permute them freely.
    final sorted = List<int>.of(numbers)..sort();
    return '${allowDivision ? 'd' : 'n'}:${sorted.join(',')}';
  }

  /// Every value obtainable by combining [numbers] exactly once each with
  /// `+ - * /` and parentheses. Doubles are only used for the *set* membership
  /// check, never for the search itself.
  static Set<double> reachable(List<int> numbers, {bool allowDivision = true}) {
    final key = _key(numbers, allowDivision);
    final cached = _cache[key];
    if (cached != null) return cached;

    final results = <double>{};
    for (final result in _solve(
      numbers.map((n) => Frac(n)).toList(),
      allowDivision: allowDivision,
    )) {
      if (result.denominator == 0) continue;
      final v = result.value;
      if (v.isNaN || v.isInfinite) continue;
      if (v.abs() > 1e7) continue;
      results.add(v);
    }

    if (_cache.length >= _cacheLimit) _cache.clear();
    _cache[key] = results;
    return results;
  }

  /// Whether [numbers] can combine to exactly [target].
  static bool canReach(List<int> numbers, int target, {bool allowDivision = true}) {
    // The target is one of the values, so membership is exact rather than a
    // near-epsilon test. A small number set can reach so many nearby values
    // that an epsilon comparison starts accepting values it should not.
    final key = _key(numbers, allowDivision);
    final results = _cache[key] ?? reachable(numbers, allowDivision: allowDivision);
    return results.any((v) => v == target.toDouble() || (v - target).abs() < 1e-9);
  }

  /// Whether a solution exists that needs at least one division.
  static bool needsDivision(List<int> numbers, int target) {
    if (!canReach(numbers, target)) return false;
    return !canReach(numbers, target, allowDivision: false);
  }

  /// Drops the memo. Only tests should need this, when they are measuring the
  /// cold cost of a search.
  static void clearCache() => _cache.clear();

  static List<Frac> _solve(List<Frac> items, {required bool allowDivision}) {
    if (items.length == 1) return items;
    final out = <Frac>[];
    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        final rest = List<Frac>.of(items)
          ..removeAt(j)
          ..removeAt(i);
        final a = items[i];
        final b = items[j];
        final combos = <Frac>[a + b, a - b, b - a, a * b];
        if (allowDivision) {
          if (b.numerator != 0) combos.add(a / b);
          if (a.numerator != 0) combos.add(b / a);
        }
        for (final combo in combos) {
          out.addAll(
            _solve(<Frac>[...rest, combo.reduced], allowDivision: allowDivision),
          );
        }
      }
    }
    return out;
  }
}
