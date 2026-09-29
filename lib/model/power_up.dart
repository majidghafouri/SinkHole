import 'package:flutter/material.dart';

/// Power-ups are earned by playing well, never bought.
enum PowerUp {
  /// Halts the drain for five seconds.
  freeze,

  /// Swaps in a brand new puzzle. No reward, no crack, streak preserved.
  skip,

  /// Removes one wrong option, or replays a memory flash.
  hint,

  /// Eats a single mistake instead of letting it become a crack.
  shield,
}

extension PowerUpInfo on PowerUp {
  String get label => switch (this) {
    PowerUp.freeze => 'Freeze',
    PowerUp.skip => 'Skip',
    PowerUp.hint => 'Hint',
    PowerUp.shield => 'Shield',
  };

  /// Icon-based instructions: the brief keeps all puzzle copy under four words.
  String get hintText => switch (this) {
    PowerUp.freeze => 'Timer holds 5s',
    PowerUp.skip => 'New puzzle',
    PowerUp.hint => 'Narrow it down',
    PowerUp.shield => 'Eats a mistake',
  };

  /// The tray glyph. Real icon constants rather than raw code points, so the
  /// tree-shaker keeps the glyph and the constructor stays const.
  IconData get icon => switch (this) {
    PowerUp.freeze => Icons.ac_unit_rounded,
    PowerUp.skip => Icons.skip_next_rounded,
    PowerUp.hint => Icons.lightbulb_rounded,
    PowerUp.shield => Icons.shield_rounded,
  };

  /// How long [PowerUp.freeze] holds the timer, in seconds.
  static const double freezeSeconds = 5.0;

  /// Time cost of [PowerUp.skip], in seconds.
  static const double skipCostSeconds = 1.0;
}
