import 'package:flutter/material.dart';

/// One world's colour system.
///
/// The design brief is specific: a dark, calm background with bright, saturated
/// buttons on top, and never more than four accent colours on screen. Holding
/// to that is why [accents] is a four-entry list and every widget pulls from it
/// rather than inventing its own hue.
@immutable
class WorldPalette {
  const WorldPalette({
    required this.name,
    required this.tagline,
    required this.skyTop,
    required this.skyBottom,
    required this.floor,
    required this.floorEdge,
    required this.accents,
    required this.cardSurface,
    required this.onCard,
    required this.ink,
    required this.muted,
    required this.shadow,
    required this.glow,
  });

  final String name;
  final String tagline;

  /// The deep background the whole screen sits on.
  final Color skyTop;
  final Color skyBottom;

  /// The crumbling floor Bloop stands on.
  final Color floor;
  final Color floorEdge;

  /// The only four saturated colours allowed on screen. Puzzles index into
  /// this, so a shape is never drawn in a fifth hue.
  final List<Color> accents;

  /// The puzzle card, kept light so answers always pop off it.
  final Color cardSurface;
  final Color onCard;

  /// The dark colour used for outlines and drawn detail, such as Bloop's
  /// outline, pupils and mouth. Distinct from [onCard], which is the text
  /// colour on a light card.
  final Color ink;

  /// Secondary text and empty slots.
  final Color muted;

  final Color shadow;

  /// Used for the panic vignette and boss framing.
  final Color glow;

  /// The three large colours used by the answer buttons, cycled by index.
  Color buttonFill(int index) => accents[index % accents.length];

  /// Text placed on top of [cardSurface], which is always a light colour.
  Color get accentInk => const Color(0xFF1B1230);

  /// Answer buttons need text that stays readable on top of any accent.
  Color onButton(int index) =>
      ThemeData.estimateBrightnessForColor(accents[index % accents.length]) ==
          Brightness.dark
      ? Colors.white
      : const Color(0xFF1B1230);
}

/// The four worlds from the design brief, unlocked by depth.
class Worlds {
  const Worlds._();

  static const List<WorldPalette> all = <WorldPalette>[
    WorldPalette(
      name: 'Candy Meadow',
      tagline: 'Sweet and shallow',
      skyTop: Color(0xFF2A1E4F),
      skyBottom: Color(0xFF4B3B7A),
      floor: Color(0xFF6FE3C4),
      floorEdge: Color(0xFF3FC3A3),
      accents: <Color>[
        Color(0xFF6FE3C4), // mint
        Color(0xFF6EC6FF), // sky blue
        Color(0xFFFFD166), // sunny yellow
        Color(0xFFFF9EC4), // bubblegum
      ],
      ink: Color(0xFF2A1E4F),
      cardSurface: Color(0xFFFDFBFF),
      onCard: Color(0xFF241A3F),
      muted: Color(0xFFB9AEDA),
      shadow: Color(0x33000000),
      glow: Color(0xFFFF6B9D),
    ),
    WorldPalette(
      name: 'Sunset Canyon',
      tagline: 'Warm and steep',
      skyTop: Color(0xFF3B1436),
      skyBottom: Color(0xFF7A2350),
      floor: Color(0xFFFF8A6B),
      floorEdge: Color(0xFFD9543F),
      accents: <Color>[
        Color(0xFFFF8A6B), // coral
        Color(0xFFFFB347), // orange
        Color(0xFFFF5FA2), // magenta
        Color(0xFFFFE29A), // sand
      ],
      ink: Color(0xFF3A1420),
      cardSurface: Color(0xFFFFF7F2),
      onCard: Color(0xFF3A1420),
      muted: Color(0xFFD9A3B4),
      shadow: Color(0x33000000),
      glow: Color(0xFFFF4F6D),
    ),
    WorldPalette(
      name: 'Crystal Cave',
      tagline: 'Bright in the dark',
      skyTop: Color(0xFF170B33),
      skyBottom: Color(0xFF3B1170),
      floor: Color(0xFFB98BFF),
      floorEdge: Color(0xFF7B4FD1),
      accents: <Color>[
        Color(0xFFB98BFF), // violet
        Color(0xFF5BE9F5), // cyan
        Color(0xFFFF6FD8), // hot pink
        Color(0xFFD8C7FF), // crystal
      ],
      ink: Color(0xFF1E0F3D),
      cardSurface: Color(0xFFFBF7FF),
      onCard: Color(0xFF1E0F3D),
      muted: Color(0xFFA99BD0),
      shadow: Color(0x40000000),
      glow: Color(0xFF7DF9FF),
    ),
    WorldPalette(
      name: 'Neon Abyss',
      tagline: 'No floor in sight',
      skyTop: Color(0xFF080A1F),
      skyBottom: Color(0xFF141C4A),
      floor: Color(0xFF2C3570),
      floorEdge: Color(0xFF1B2247),
      accents: <Color>[
        Color(0xFFB6FF3D), // lime
        Color(0xFF3DDCFF), // electric blue
        Color(0xFFFF4FD8), // hot magenta
        Color(0xFFFFE14D), // signal yellow
      ],
      ink: Color(0xFF0A0E28),
      cardSurface: Color(0xFFF4F7FF),
      onCard: Color(0xFF0A0E28),
      muted: Color(0xFF8590C4),
      shadow: Color(0x59000000),
      glow: Color(0xFFB6FF3D),
    ),
  ];

  static WorldPalette forDepth(int depth) =>
      all[_indexForDepth(depth).clamp(0, all.length - 1)];

  static WorldPalette forIndex(int index) => all[index.clamp(0, all.length - 1)];

  static int _indexForDepth(int depth) {
    const stops = <int>[1, 11, 26, 51];
    var result = 0;
    for (var i = 0; i < stops.length; i++) {
      if (depth >= stops[i]) result = i;
    }
    return result;
  }

  /// The depth at which each world begins, for the home screen's progress map.
  static const List<int> unlockDepths = <int>[1, 11, 26, 51];

  /// How far the player has to go to unlock the next world, or null at the end.
  static int? nextUnlockDepth(int bestDepth) {
    for (final stop in unlockDepths) {
      if (bestDepth < stop) return stop;
    }
    return null;
  }

  /// Streak flame colours, in the order the brief describes: yellow, then
  /// orange, blue, and finally rainbow.
  ///
  /// Every tier returns at least two stops, because they feed a gradient.
  static List<Color> streakFlame(int streak) => switch (streak) {
    < 3 => const <Color>[Color(0xFFFFE14D), Color(0xFFFFB03D)],
    < 6 => const <Color>[Color(0xFFFFC53D), Color(0xFFFF7A3D)],
    < 10 => const <Color>[Color(0xFF4FC3FF), Color(0xFF2E7BFF)],
    < 15 => const <Color>[Color(0xFFB6FF3D), Color(0xFF3DDCFF)],
    _ => const <Color>[
      Color(0xFFFF4FD8),
      Color(0xFF3DDCFF),
      Color(0xFFB6FF3D),
      Color(0xFFFFE14D),
    ],
  };
}
