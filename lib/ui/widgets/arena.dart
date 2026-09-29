import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/world_palette.dart';

/// The crumbling floor Bloop stands on, seen from above at a slight tilt.
///
/// Tiles crack and drop away as the run gets deeper, which is the visual
/// argument for "the floor is failing" that a flat background cannot make.
class CrumblingFloor extends StatefulWidget {
  const CrumblingFloor({
    required this.world,
    required this.progress,
    required this.shake,
    this.collapse = 0,
    super.key,
  });

  final WorldPalette world;

  /// 0 at the surface, 1 in the abyss. More of the floor is missing as this
  /// rises.
  final double progress;

  /// A free-running driver used for the panic shake and the tile wobble.
  final double shake;

  /// 0 to 1 through the fall, when the whole floor drops out.
  final double collapse;

  @override
  State<CrumblingFloor> createState() => _CrumblingFloorState();
}

class _CrumblingFloorState extends State<CrumblingFloor> {
  /// Fixed per-tile randomness, so the same tiles are always the weak ones.
  final List<double> _wear = List<double>.generate(48, (i) => (i * 37 % 17) / 17);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _FloorPainter(
          world: widget.world,
          progress: widget.progress.clamp(0.0, 1.0),
          shake: widget.shake,
          collapse: widget.collapse.clamp(0.0, 1.0),
          wear: _wear,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _FloorPainter extends CustomPainter {
  _FloorPainter({
    required this.world,
    required this.progress,
    required this.shake,
    required this.collapse,
    required this.wear,
  });

  final WorldPalette world;
  final double progress;
  final double shake;
  final double collapse;
  final List<double> wear;

  static const int _columns = 5;
  static const int _rows = 3;

  /// The band the floor occupies, measured up from the bottom of the screen.
  static const double _bandFraction = 0.34;

  @override
  void paint(Canvas canvas, Size size) {
    final bandHeight = size.height * _bandFraction;
    final top = size.height - bandHeight;
    final tileWidth = size.width / _columns;
    final tileHeight = bandHeight / _rows;

    // A soft fade into the background so the floor recedes rather than
    // tiling the whole screen behind the copy.
    canvas.drawRect(
      Rect.fromLTWH(0, top, size.width, bandHeight),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            world.skyBottom.withValues(alpha: 0),
            world.skyBottom.withValues(alpha: 0.85),
          ],
        ).createShader(Rect.fromLTWH(0, top, size.width, bandHeight)),
    );

    for (var row = 0; row < _rows; row++) {
      for (var col = 0; col < _columns; col++) {
        final index = row * _columns + col;
        final wearValue = wear[index];

        // Tiles fall away as the run deepens, biased toward the front of the
        // screen so the path ahead visibly breaks up.
        final depthBias = (row + 1) / _rows;
        final gone = progress * 0.6 * (0.4 + wearValue) * depthBias;
        if (gone > 0.6) continue;

        final wobble =
            math.sin(shake * 2 * math.pi + index) * (progress * 1.6 + collapse * 6);
        final inset = 4 + gone * 22 + collapse * 30;

        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            col * tileWidth + inset + wobble,
            top + row * tileHeight + inset * 0.4,
            tileWidth - inset * 2,
            tileHeight - inset * 1.4,
          ),
          const Radius.circular(14),
        );

        final alpha = (1 - gone * 0.85).clamp(0.0, 1.0);
        canvas.drawRRect(
          rect,
          Paint()..color = world.floor.withValues(alpha: 0.20 * alpha),
        );
        canvas.drawRRect(
          rect,
          Paint()
            ..color = world.floorEdge.withValues(alpha: 0.45 * alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        if (wearValue > 0.72) {
          // A hairline fracture on the weakest tiles.
          final crack = Path()
            ..moveTo(rect.left + rect.width * 0.2, rect.top + rect.height * 0.12)
            ..lineTo(rect.left + rect.width * 0.55, rect.top + rect.height * 0.55)
            ..lineTo(rect.left + rect.width * 0.35, rect.top + rect.height * 0.88);
          canvas.drawPath(
            crack,
            Paint()
              ..color = world.floorEdge.withValues(alpha: 0.5 * alpha)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_FloorPainter old) =>
      old.progress != progress ||
      old.shake != shake ||
      old.collapse != collapse ||
      old.world != world;
}

/// The red vignette that closes in during the panic zone.
///
/// It stays cartoonish rather than harsh: a soft glow at the edges plus a slow
/// breath, never a strobe.
class PanicGlow extends StatelessWidget {
  const PanicGlow({
    required this.active,
    required this.pulse,
    required this.world,
    super.key,
  });

  final bool active;
  final double pulse;
  final WorldPalette world;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: active ? 1 : 0,
        child: CustomPaint(
          painter: _PanicPainter(pulse: pulse),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _PanicPainter extends CustomPainter {
  const _PanicPainter({required this.pulse});
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final breath = 0.55 + 0.45 * (pulse + 1) / 2;
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.95,
        colors: <Color>[
          Colors.transparent,
          const Color(0x00FF2D55),
          Color.lerp(const Color(0x00FF2D55), const Color(0xFFFF2D55), breath)!,
        ],
        stops: const <double>[0.45, 0.78, 1],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_PanicPainter old) => old.pulse != pulse;
}

/// A crack that spreads across the screen when the floor takes a hit.
///
/// Drawn once per new crack, seeded by the crack count so each one lands in a
/// different place and the floor visibly accumulates damage.
class CrackOverlay extends StatelessWidget {
  const CrackOverlay({required this.cracks, required this.world, super.key});

  final int cracks;
  final WorldPalette world;

  @override
  Widget build(BuildContext context) {
    if (cracks <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        painter: _CrackPainter(cracks: cracks, world: world),
        size: Size.infinite,
      ),
    );
  }
}

class _CrackPainter extends CustomPainter {
  const _CrackPainter({required this.cracks, required this.world});

  final int cracks;
  final WorldPalette world;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < cracks; i++) {
      final seed = (i + 1) * 2.399963;
      final origin = Offset(
        size.width * (0.2 + 0.6 * _unit(seed * 7)),
        size.height * (0.25 + 0.55 * _unit(seed * 13)),
      );

      final main = Path()..moveTo(origin.dx, origin.dy);
      var point = origin;
      var angle = seed;
      for (var segment = 0; segment < 5; segment++) {
        angle += math.sin(seed + segment) * 0.9;
        final length = size.shortestSide * (0.07 + 0.03 * segment);
        point = Offset(
          point.dx + math.cos(angle) * length,
          point.dy + math.sin(angle) * length,
        );
        main.lineTo(point.dx, point.dy);
      }

      final width = math.max(1.2, 3.4 - i * 0.5);
      canvas.drawPath(
        main,
        Paint()
          ..color = const Color(0xCC1A0A1F)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        main,
        Paint()
          ..color = const Color(0x55FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round,
      );

      // A branch off the middle so the mark reads as a fracture.
      final branchStart = Offset(
        origin.dx + (point.dx - origin.dx) * 0.5,
        origin.dy + (point.dy - origin.dy) * 0.5,
      );
      final branch = Path()..moveTo(branchStart.dx, branchStart.dy);
      var branchAngle = angle + 1.3;
      var branchPoint = branchStart;
      for (var segment = 0; segment < 3; segment++) {
        branchAngle += math.cos(seed * 3 + segment) * 0.5;
        final length = size.shortestSide * (0.05 + 0.02 * segment);
        branchPoint = Offset(
          branchPoint.dx + math.cos(branchAngle) * length,
          branchPoint.dy + math.sin(branchAngle) * length,
        );
        branch.lineTo(branchPoint.dx, branchPoint.dy);
      }
      canvas.drawPath(
        branch,
        Paint()
          ..color = const Color(0x991A0A1F)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 0.6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /// Deterministic 0..1 from a seed, so a given crack always lands in the same
  /// place and the damage visibly accumulates.
  static double _unit(double seed) {
    final value = math.sin(seed * 12.9898) * 43758.5453;
    return value - value.floorToDouble();
  }

  @override
  bool shouldRepaint(_CrackPainter old) => old.cracks != cracks || old.world != world;
}
