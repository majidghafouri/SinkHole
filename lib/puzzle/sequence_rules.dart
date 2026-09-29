import '../core/game_random.dart';

/// The number-series rules the sequence template can use.
///
/// The rule definitions live here rather than inside the generator because
/// both the generator and its tests need to reason about them. Keeping one
/// implementation is what makes the "this series is unambiguous" guarantee in
/// [matchingRules] meaningful.
enum SequenceRule { add, addGrowing, subtract, multiply, alternate, fibonacci, squares }

extension SequenceRuleInfo on SequenceRule {
  String get label => name;

  /// Whether the rule is simple enough for the opening puzzles, which teach the
  /// timer and the crack penalty by doing rather than through a tutorial.
  bool get isBeginnerFriendly =>
      this == SequenceRule.add || this == SequenceRule.addGrowing;

  /// Builds `length + 1` terms: [length] to show plus the answer.
  ///
  /// Returns null when the rule would produce a series that is too large or
  /// too negative to look good on a card.
  List<int>? generate(GameRandom rng, int length) {
    List<int> terms;
    switch (this) {
      case SequenceRule.add:
        final start = rng.range(2, 30);
        final step = rng.range(2, 11);
        terms = _series(length, (i) => start + step * i);
      case SequenceRule.addGrowing:
        final start = rng.range(1, 12);
        final step = rng.range(1, 4);
        // Differences grow: step, 2*step, 3*step, ...
        terms = _series(length, (i) => start + step * (i * (i + 1) ~/ 2));
      case SequenceRule.subtract:
        final start = rng.range(70, 180);
        final step = rng.range(4, 13);
        terms = _series(length, (i) => start - step * i);
      case SequenceRule.multiply:
        final start = rng.range(1, 5);
        final factor = rng.range(2, 4);
        terms = _series(length, (i) => start * _pow(factor, i));
      case SequenceRule.alternate:
        final start = rng.range(3, 20);
        final up = rng.range(5, 15);
        final down = rng.range(1, 3);
        // Alternating +up, -down, +up, -down, ...
        terms = _series(length, (i) {
          final ups = (i + 1) ~/ 2;
          final downs = i ~/ 2;
          return start + up * ups - down * downs;
        });
      case SequenceRule.fibonacci:
        final a = rng.range(1, 7);
        final b = rng.range(a, a + 8);
        terms = <int>[a, b];
        for (var k = 2; k <= length; k++) {
          terms.add(terms[k - 1] + terms[k - 2]);
        }
      case SequenceRule.squares:
        final start = rng.range(1, 4);
        final gap = rng.range(0, 5);
        terms = _series(length, (i) => _pow(start + gap + i, 2));
    }

    final last = terms.last;
    if (last < -999 || last > 4000) return null;
    return terms;
  }

  /// Whether [terms] is an unbroken run of this rule.
  bool matches(List<int> terms) {
    if (terms.length < 3) return false;
    switch (this) {
      case SequenceRule.add:
        return _isConstantStep(terms, ascending: true);
      case SequenceRule.subtract:
        return _isConstantStep(terms, ascending: false);
      case SequenceRule.addGrowing:
        return _isGrowingStep(terms);
      case SequenceRule.multiply:
        return _isConstantRatio(terms);
      case SequenceRule.alternate:
        return _isAlternating(terms);
      case SequenceRule.fibonacci:
        return _isFibonacci(terms);
      case SequenceRule.squares:
        return _isSquares(terms);
    }
  }

  /// The term that follows [terms] under this rule.
  int predict(List<int> terms) {
    final last = terms.last;
    switch (this) {
      case SequenceRule.add:
        return last + (terms[1] - terms[0]);
      case SequenceRule.subtract:
        return last + (terms[1] - terms[0]);
      case SequenceRule.addGrowing:
        final step = terms[1] - terms[0];
        return last + step * terms.length;
      case SequenceRule.multiply:
        return last * (terms[1] ~/ terms[0]);
      case SequenceRule.alternate:
        // The sign of the last step tells us which way the next one goes, and
        // the magnitude of the most recent step in that direction gives its
        // size.
        final lastStep = last - terms[terms.length - 2];
        if (lastStep > 0) {
          return last - _lastStepOfSize(terms, negative: true);
        }
        return last + _lastStepOfSize(terms, negative: false);
      case SequenceRule.fibonacci:
        return terms[terms.length - 1] + terms[terms.length - 2];
      case SequenceRule.squares:
        final root = _integerSqrt(last) + 1;
        return root * root;
    }
  }
}

/// Every rule that could have produced [terms].
///
/// A series where two rules both fit is a broken puzzle: the player has no way
/// to know which one is in play, so any two would be a defensible answer. The
/// sequence generator rejects those outright.
List<SequenceRule> matchingRules(List<int> terms) =>
    SequenceRule.values.where((rule) => rule.matches(terms)).toList(growable: false);

/// Whether exactly one rule explains [terms].
bool isUnambiguous(List<int> terms) => matchingRules(terms).length == 1;

// ------------------------------------------------------------------ helpers

List<int> _series(int length, int Function(int i) f) => List<int>.generate(length + 1, f);

/// Magnitude of the most recent step in one direction. Only meaningful for an
/// alternating series, where steps alternate between two fixed magnitudes.
int _lastStepOfSize(List<int> terms, {required bool negative}) {
  for (var i = terms.length - 1; i >= 1; i--) {
    final delta = terms[i] - terms[i - 1];
    if (negative ? delta < 0 : delta > 0) return delta.abs();
  }
  return 0;
}

int _pow(int base, int exp) {
  var result = 1;
  for (var i = 0; i < exp; i++) {
    result *= base;
  }
  return result;
}

bool _isConstantStep(List<int> terms, {required bool ascending}) {
  if (terms.length < 3) return false;
  final step = terms[1] - terms[0];
  if (ascending && step <= 0) return false;
  if (!ascending && step >= 0) return false;
  for (var i = 2; i < terms.length; i++) {
    if (terms[i] - terms[i - 1] != step) return false;
  }
  return true;
}

bool _isGrowingStep(List<int> terms) {
  if (terms.length < 4) return false;
  final steps = <int>[for (var i = 1; i < terms.length; i++) terms[i] - terms[i - 1]];
  final first = steps.first;
  if (first <= 0) return false;
  for (var i = 0; i < steps.length; i++) {
    if (steps[i] != first * (i + 1)) return false;
  }
  return true;
}

bool _isConstantRatio(List<int> terms) {
  if (terms.length < 3 || terms.first <= 0) return false;
  final ratio = terms[1] ~/ terms.first;
  if (ratio < 2) return false;
  if (terms[1] % terms.first != 0) return false;
  for (var i = 2; i < terms.length; i++) {
    if (terms[i] != terms[i - 1] * ratio) return false;
  }
  return true;
}

bool _isAlternating(List<int> terms) {
  if (terms.length < 4) return false;
  final ups = <int>[];
  final downs = <int>[];
  for (var i = 1; i < terms.length; i++) {
    final delta = terms[i] - terms[i - 1];
    (i.isOdd ? ups : downs).add(delta);
  }
  if (ups.isEmpty || downs.isEmpty) return false;
  if (ups.toSet().length != 1 || downs.toSet().length != 1) return false;
  return ups.first > 0 && downs.first < 0;
}

bool _isFibonacci(List<int> terms) {
  if (terms.length < 4) return false;
  for (var i = 2; i < terms.length; i++) {
    if (terms[i] != terms[i - 1] + terms[i - 2]) return false;
  }
  return true;
}

bool _isSquares(List<int> terms) {
  if (terms.length < 3) return false;
  var previous = -1;
  for (final v in terms) {
    if (v < 0) return false;
    final root = _integerSqrt(v);
    if (root * root != v) return false;
    if (previous >= 0 && root <= previous) return false;
    previous = root;
  }
  return true;
}

int _integerSqrt(int v) {
  if (v < 2) return v;
  var x = v;
  var y = (x + 1) ~/ 2;
  while (y < x) {
    x = y;
    y = (x + v ~/ x) ~/ 2;
  }
  return x;
}
