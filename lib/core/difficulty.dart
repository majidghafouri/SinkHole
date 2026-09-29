import 'game_random.dart';

/// The difficulty of a single puzzle: where the player is, plus how they are
/// actually doing.
///
/// Depth sets the baseline. [skillOffset] is a small nudge derived from recent
/// play, so a player who is cruising gets content slightly past the curve and a
/// player who is struggling gets content slightly inside it. It is deliberately
/// capped: the curve must still be the spine of the game, not something a run can
/// talk its way out of.
class Difficulty {
  const Difficulty(this.depth, {this.skillOffset = 0});

  /// 1-based depth the player is about to attempt.
  final int depth;

  /// How far to push the curve, in ramp units. Clamped to about a fifth of a
  /// level band either way.
  final double skillOffset;

  /// Largest nudge the adaptive layer may apply.
  static const double maxSkillOffset = 0.12;

  /// A "level" is a band of five depths; difficulty steps up once per level.
  int get level => (depth - 1) ~/ 5;

  /// 0 at the surface, ramping to 1 around depth 46 and staying there.
  double get ramp => clampDouble((depth - 1) / 45.0 + skillOffset, 0.0, 1.0);

  /// Secondary ramp used to bring the harder templates online. It reaches 1 at
  /// depth 13, well before the main ramp does, so the variety arrives early
  /// while the difficulty keeps climbing.
  double get unlockRamp => clampDouble((depth - 1) / 12.0, 0.0, 1.0);

  /// Base seconds for a new puzzle. Shinks a little with every level.
  double get baseSeconds => clampDouble(12.0 - 0.4 * level, 5.0, 12.0);

  /// How many steps of a sequence are shown (longer is harder).
  int get sequenceLength => 4 + (ramp * 3).round();

  /// Length of one beat of a repeating pattern.
  ///
  /// Always paired with [patternCycles] repeats on screen, because a cycle that
  /// has only been shown once gives the player nothing to recognise and no way
  /// to tell the answer from a guess.
  int get patternCycleLength => ramp < 0.12 ? 2 : (ramp < 0.6 ? 3 : 4);

  /// How many times a pattern's cycle is shown before the blank.
  static const int patternCycles = 2;

  /// Side length of the grid-logic board.
  ///
  /// This is the main lever on content volume as well as difficulty: a 3x3
  /// Latin square has only twelve possible layouts, a 4x4 has 576.
  int get gridSize => ramp < 0.35 ? 3 : 4;

  /// How many cells are hidden in the grid puzzle. Never more than one per row
  /// or column, and they always share a value, so the answer stays unique.
  int get gridBlanks => gridSize == 3 ? (ramp < 0.4 ? 1 : 2) : (ramp < 0.7 ? 2 : 3);

  /// Whether the grid uses the harder column multiplier.
  bool get gridUsesMultiplier => ramp > 0.45;

  /// Largest number allowed in a `make 24` style puzzle.
  int get make24Max => ramp < 0.3 ? 6 : (ramp < 0.7 ? 9 : 13);

  /// Whether `make 24` should try to force a division-based solution.
  bool get make24NeedsDivision => ramp > 0.5;

  /// How many symbols flash for the memory puzzle.
  int get memorySymbols => ramp < 0.25 ? 4 : (ramp < 0.7 ? 5 : 6);

  /// How long the memory flash stays on screen, in milliseconds.
  int get memoryFlashMs => (2000 - 800 * ramp).round().clamp(1100, 2000);

  /// Side length of the memory board. Stays at three: the recall difficulty comes
  /// from how many symbols flash, and the content space is already ample.
  static const int memorySize = 3;

  /// How many dimensions the odd-one-out differs by. 1 is a genuine
  /// spot-the-difference; 2 or more is obvious.
  int get oddOneDifferences => ramp < 0.3 ? 2 : 1;

  /// True while the first puzzles are still teaching the mechanics by doing.
  bool get isTutorial => depth <= 3;

  /// Depth at which each world theme becomes active.
  static const List<int> themeStops = <int>[1, 11, 26, 51];

  /// Index into the world palette list for a given depth.
  static int worldIndexFor(int depth) {
    var index = 0;
    for (var i = 0; i < themeStops.length; i++) {
      if (depth >= themeStops[i]) index = i;
    }
    return index;
  }

  /// The label of the level band a depth belongs to, e.g. `LEVEL 3`.
  int get levelLabel => level + 1;
}

/// Builds the run seed. Daily runs are shared by everyone; free runs are not.
int seedForRun({required bool daily, required DateTime now}) {
  if (daily) return dailySeedFor(now);
  // Mix the wall clock in so two quick restarts do not replay the same puzzles.
  final entropy = DateTime.now().microsecondsSinceEpoch;
  return (dailySeedFor(now) ^ (entropy & 0xFFFFFF)) & 0x7FFFFFFF;
}

/// Formats seconds for the compact `+2.4s` reward popup.
String formatSeconds(double seconds) {
  if (seconds >= 10) return '+${seconds.round()}s';
  final text = seconds.toStringAsFixed(1);
  return '+${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}s';
}
