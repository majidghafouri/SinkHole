import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/world_palette.dart';

/// The floor timer: a thick, glossy bar that drains.
///
/// The bar is the most important piece of feedback in the game, so it earns
/// three things beyond just draining:
///
///  * it changes colour in three bands and pulses when it is nearly gone,
///  * the right-hand end is a visibly different *reserve*, because that is
///    where banked seconds live. Drawing it as its own region is what makes a
///    fresh puzzle read as "full" instead of "already half gone", and
///  * it cracks across the face in the last seconds, so the danger is felt
///    before it is read.
class FloorTimerBar extends StatelessWidget {
  const FloorTimerBar({
    required this.world,
    required this.fraction,
    required this.budgetFraction,
    required this.allowanceFraction,
    required this.frozen,
    required this.freezeFraction,
    required this.panic,
    required this.pulse,
    super.key,
  });

  final WorldPalette world;

  /// Fill against the full track, which is the puzzle's allowance plus the
  /// buffer it can carry.
  final double fraction;

  /// Where the allowance ends and the reserve begins, as a fraction of the
  /// track. A full allowance reaches exactly this mark.
  final double budgetFraction;

  /// How much of the player's own allowance is left, ignoring banked seconds.
  ///
  /// The colour bands are driven by this rather than by [fraction], because a
  /// fresh puzzle only fills about three fifths of the track once the reserve is
  /// counted, and a bar that starts amber makes every run feel half over.
  final double allowanceFraction;

  final bool frozen;

  /// 1 at the moment a freeze starts, 0 when it wears off.
  final double freezeFraction;

  final bool panic;

  /// A free-running 0..1 driver, so the bar can breathe without a controller.
  final double pulse;

  static const double height = 28;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: CustomPaint(
              painter: _BarPainter(
                world: world,
                fraction: fraction,
                budgetFraction: budgetFraction,
                allowanceFraction: allowanceFraction,
                frozen: frozen,
                freezeFraction: freezeFraction,
                panic: panic,
                pulse: panic ? math.sin(pulse * 2 * math.pi) : 0,
              ),
            ),
          ),
          // A soft glow beneath the bar, strongest when time is short.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height / 2),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: _tint.withValues(
                        alpha: panic ? 0.3 + 0.35 * (pulse + 1) / 2 : 0.2,
                      ),
                      blurRadius: panic ? 22 : 12,
                      spreadRadius: panic ? 2 : 0,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color get _tint => _tintFor(allowanceFraction, world, frozen);
}

/// Green to yellow to red, keyed on the player's own remaining allowance.
Color _tintFor(double allowance, WorldPalette world, bool frozen) {
  if (frozen) return const Color(0xFF7DD3FC);
  if (allowance > 0.55) return world.accents[0];
  if (allowance > 0.28) return const Color(0xFFFFC53D);
  return const Color(0xFFFF5470);
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.world,
    required this.fraction,
    required this.budgetFraction,
    required this.allowanceFraction,
    required this.frozen,
    required this.freezeFraction,
    required this.panic,
    required this.pulse,
  });

  final WorldPalette world;
  final double fraction;
  final double budgetFraction;
  final double allowanceFraction;
  final bool frozen;
  final double freezeFraction;
  final bool panic;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, radius);
    final markX = size.width * budgetFraction.clamp(0.0, 1.0);

    // Track.
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF1B1230));

    // The reserve, drawn behind the fill: darker and hatched, so banked time
    // never reads as part of this puzzle's own allowance.
    if (markX < size.width - 1) {
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(
        Rect.fromLTRB(markX, 0, size.width, size.height),
        Paint()..color = const Color(0xFF241A3F),
      );
      canvas.restore();
    }

    final fillWidth = size.width * fraction.clamp(0.0, 1.0);
    if (fillWidth > 2) {
      final fillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, fillWidth, size.height),
        radius,
      );
      final tint = _tint;

      canvas.save();
      canvas.clipRRect(fillRect);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, fillWidth, size.height),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color.lerp(tint, Colors.white, 0.35)!,
              tint,
              Color.lerp(tint, const Color(0xFF1B1230), 0.25)!,
            ],
          ).createShader(Rect.fromLTWH(0, 0, fillWidth, size.height)),
      );
      // Glossy top highlight.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(3, 2.5, math.max(0, fillWidth - 6), size.height * 0.32),
          const Radius.circular(6),
        ),
        Paint()..color = const Color(0x44FFFFFF),
      );

      // Banked seconds sit inside the reserve region and get a brighter,
      // hatched treatment so they are visibly a bonus rather than slack.
      if (fillWidth > markX + 1) {
        final reserve = Rect.fromLTWH(markX, 0, fillWidth - markX, size.height);
        canvas.drawRect(reserve, Paint()..color = Colors.white.withValues(alpha: 0.22));
        _hatch(canvas, reserve, size.height * 0.34);
      }
      canvas.restore();
    }

    // The divider between allowance and reserve. This is the line that makes a
    // full allowance legible as "full".
    if (markX > 2 && markX < size.width - 2) {
      canvas.drawLine(
        Offset(markX, 4),
        Offset(markX, size.height - 4),
        Paint()
          ..color = const Color(0xFF1B1230)
          ..strokeWidth = 3,
      );
    }

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF1B1230)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    if (frozen) {
      _paintFrost(canvas, size, radius);
      return;
    }
    if (panic) _paintCracks(canvas, size, allowanceFraction);
  }

  /// Diagonal stripes over the banked region.
  void _hatch(Canvas canvas, Rect rect, double gap) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 2;
    for (var x = rect.left - rect.height; x < rect.right; x += gap * 2) {
      canvas.drawLine(Offset(x, rect.bottom), Offset(x + rect.height, rect.top), paint);
    }
  }

  Color get _tint => _tintFor(allowanceFraction, world, frozen);

  /// Ice crystals creeping in from the edges as the freeze runs down.
  void _paintFrost(Canvas canvas, Size size, Radius radius) {
    final remaining = freezeFraction.clamp(0.0, 1.0);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25 + 0.35 * remaining)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final inset = size.width * (1 - remaining) * 0.5;
    for (var i = 0; i < 7; i++) {
      final t = i / 6;
      final x = inset + (size.width - inset * 2) * t;
      final y =
          size.height / 2 + math.sin(t * math.pi * 3 + pulse * 4) * size.height * 0.2;
      canvas.drawLine(
        Offset(x, y - size.height * 0.32),
        Offset(x, y + size.height * 0.32),
        paint,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(inset, 0, size.width - inset * 2, size.height),
        radius,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  /// Jagged fractures that creep in as the bar empties, so the last seconds
  /// are felt before they are read.
  void _paintCracks(Canvas canvas, Size size, double fraction) {
    final intensity = ((1 - fraction) / 0.3).clamp(0.0, 1.0);
    if (intensity <= 0) return;
    final paint = Paint()
      ..color = const Color(0xFF3A0E1C).withValues(alpha: 0.5 * intensity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // The shake makes the cracks jump as the bar pulses.
    final jitter = pulse * 1.6;
    const seeds = <List<Offset>>[
      <Offset>[Offset(0.86, 0.05), Offset(0.78, 0.42), Offset(0.9, 0.95)],
      <Offset>[Offset(0.55, 0.0), Offset(0.62, 0.5), Offset(0.52, 1.0)],
      <Offset>[Offset(0.3, 0.1), Offset(0.36, 0.55), Offset(0.28, 0.9)],
    ];
    for (final seed in seeds) {
      final path = Path()..moveTo(seed[0].dx * size.width, seed[0].dy * size.height);
      for (final point in seed.skip(1)) {
        path.lineTo(point.dx * size.width + jitter, point.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.fraction != fraction ||
      old.budgetFraction != budgetFraction ||
      old.allowanceFraction != allowanceFraction ||
      old.frozen != frozen ||
      old.freezeFraction != freezeFraction ||
      old.panic != panic ||
      old.pulse != pulse ||
      old.world != world;
}
