import 'package:flutter/material.dart';

import 'world_palette.dart';

/// The game's type scale.
///
/// The brief asks for a rounded, bold, friendly face. Rather than ship or
/// download a font, the stack below prefers a rounded face the OS already has
/// and falls back to the platform default at a heavy weight, which keeps the
/// chunky feel with zero download cost and no network dependency at runtime.
abstract final class SinkType {
  /// Rounded faces, best first, for the platforms we ship to.
  static const List<String> fontStack = <String>[
    'SF Pro Rounded',
    'Arial Rounded MT Bold',
    'Quicksand',
    'Nunito',
    'Varela Round',
  ];

  /// The big animated depth counter.
  static const TextStyle display = TextStyle(
    fontWeight: FontWeight.w900,
    fontSize: 40,
    height: 1.0,
    letterSpacing: -1.5,
  );

  /// Screen and card headers.
  static const TextStyle title = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 22,
    height: 1.1,
    letterSpacing: -0.4,
  );

  /// The prompt printed on the puzzle card. Kept short and loud.
  static const TextStyle prompt = TextStyle(
    fontWeight: FontWeight.w900,
    fontSize: 17,
    height: 1.1,
    letterSpacing: 1.6,
  );

  /// Numbers inside puzzle cards and grid cells.
  static const TextStyle numeral = TextStyle(
    fontWeight: FontWeight.w900,
    fontSize: 26,
    height: 1.0,
    letterSpacing: -0.5,
  );

  /// Answer button labels.
  static const TextStyle button = TextStyle(
    fontWeight: FontWeight.w900,
    fontSize: 26,
    height: 1.0,
    letterSpacing: -0.5,
  );

  /// Small supporting text.
  static const TextStyle label = TextStyle(
    fontWeight: FontWeight.w700,
    fontSize: 12,
    height: 1.2,
    letterSpacing: 0.6,
  );

  /// Tiny captions, e.g. under the timer bar.
  static const TextStyle caption = TextStyle(
    fontWeight: FontWeight.w700,
    fontSize: 10,
    height: 1.2,
    letterSpacing: 0.8,
  );

  /// Applies the rounded stack to a style from the scale.
  static TextStyle rounded(TextStyle style) =>
      style.copyWith(fontFamilyFallback: fontStack);
}

/// Shared radii, so every chunky shape in the game matches.
abstract final class SinkShape {
  /// Buttons and cards.
  static const double radius = 22;

  /// Chips and small tiles.
  static const double chipRadius = 16;

  /// The power-up tray and other pills.
  static const double pillRadius = 999;

  /// The thick outline used across the UI.
  static const double outline = 3;
}

/// The Material theme, derived from the active world.
ThemeData buildTheme(WorldPalette world) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamilyFallback: SinkType.fontStack,
  );

  return base.copyWith(
    scaffoldBackgroundColor: world.skyBottom,
    colorScheme: base.colorScheme.copyWith(
      primary: world.accents.first,
      secondary: world.accents[1],
      surface: world.skyTop,
      onSurface: Colors.white,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
      fontFamilyFallback: SinkType.fontStack,
    ),
    splashFactory: InkSparkle.splashFactory,
  );
}

/// Makes the active world's palette available to the whole subtree.
///
/// A plain inherited widget rather than a [ThemeExtension] because the palette
/// is not a Material concern: it drives custom painters, gradients and the
/// floor, none of which read from [ThemeData].
class WorldScope extends InheritedWidget {
  const WorldScope({required this.world, required super.child, super.key});

  final WorldPalette world;

  static WorldPalette of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<WorldScope>();
    assert(scope != null, 'No WorldScope found in the widget tree');
    return scope!.world;
  }

  /// Reads the palette without subscribing, for callbacks and painters.
  static WorldPalette read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<WorldScope>();
    assert(scope != null, 'No WorldScope found in the widget tree');
    return scope!.world;
  }

  @override
  bool updateShouldNotify(WorldScope oldWidget) => oldWidget.world != world;
}
