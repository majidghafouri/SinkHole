import '../core/difficulty.dart';

/// A rolling read on how the player is coping, used to nudge the difficulty
/// curve.
///
/// The brief asks for content that matches the player's level, and depth alone
/// cannot do that: two players at depth 20 can be having very different runs.
/// This watches recent attempts and moves the curve within a narrow band.
///
/// Two deliberate limits keep it from becoming a rubber band that removes all
/// tension:
///
///  * it is capped at [Difficulty.maxSkillOffset], roughly a fifth of a level
///    band, so it re-tunes the content rather than rewriting the run;
///  * it is a moving average rather than a running total, so one lucky answer
///    does not carry and the read decays back toward the baseline on its own.
class SkillReadout {
  /// A solved puzzle with this much of its allowance left counts as cruising.
  static const double _fastSolve = 0.55;

  /// Weight of one attempt in the running average.
  static const double _alpha = 0.22;

  /// Smoothed score of recent attempts, from -1 (struggling) to +1 (cruising).
  ///
  /// An exponential moving average, so a single lucky answer carries very
  /// little and the read settles over roughly the last five attempts.
  double _average = 0;

  /// Where the curve is pushed, in ramp units.
  double get offset => (_average * Difficulty.maxSkillOffset).clamp(
    -Difficulty.maxSkillOffset,
    Difficulty.maxSkillOffset,
  );

  /// How many attempts have been fed in, used to hold off early judgement.
  int get samples => _samples;
  int _samples = 0;

  /// Folds in one finished attempt.
  ///
  /// [secondsLeftFraction] is how much of the puzzle's own allowance was still
  /// on the bar when it was answered, so a fast clear and a last-gasp clear are
  /// told apart. [correct] is false for a wrong answer, a timeout, or a crack.
  void record({required bool correct, required double secondsLeftFraction}) {
    final speed = (secondsLeftFraction - _fastSolve) / (1 - _fastSolve);
    final score = correct ? speed.clamp(-1.0, 1.0) : -1.0;
    _samples++;
    _average += _alpha * (score - _average);
  }

  /// Called when the run ends, so the next run starts from the baseline rather
  /// than inheriting the last run's momentum.
  void reset() {
    _average = 0;
    _samples = 0;
  }
}
