import 'dart:math' as math;

import 'package:flutter/material.dart';

class _Particle {
  _Particle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.size,
    required this.spin,
    required this.shape,
    required this.life,
  });

  Offset position;
  Offset velocity;
  final Color color;
  final double size;
  final double spin;
  final _Shape shape;
  double life;
}

enum _Shape { square, circle, ribbon }

/// Confetti bursts for a correct answer and for clearing a boss.
///
/// It is a plain particle system driven by a ticker rather than a package, so
/// it can be fired from a gesture handler and tuned per world without adding a
/// dependency to a game that otherwise ships no assets.
class ConfettiController extends ChangeNotifier {
  ConfettiController({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;
  final List<_Particle> _particles = <_Particle>[];

  /// Gravity, in logical pixels per second squared.
  static const double _gravity = 900;

  /// How long a single piece lives at full strength. Individual pieces vary
  /// around this so a burst does not all vanish at the same instant.
  static const double lifetime = 1.5;

  bool get isEmpty => _particles.isEmpty;

  /// Fires a burst from [origin] in global coordinates.
  void burst(Offset origin, {int count = 26, List<Color>? colors, double power = 1}) {
    final palette = colors ?? const <Color>[];
    for (var i = 0; i < count; i++) {
      final angle = (-math.pi / 2) + (_random.nextDouble() - 0.5) * 2.4;
      final speed = (280 + _random.nextDouble() * 420) * power;
      _particles.add(
        _Particle(
          position: origin,
          velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
          color: palette.isEmpty
              ? Colors.primaries[_random.nextInt(Colors.primaries.length)]
              : palette[_random.nextInt(palette.length)],
          size: 6 + _random.nextDouble() * 9,
          spin: (_random.nextDouble() - 0.5) * 14,
          shape: _Shape.values[_random.nextInt(_Shape.values.length)],
          life: lifetime * (0.7 + _random.nextDouble() * 0.5),
        ),
      );
    }
    notifyListeners();
  }

  /// Confetti falls off screen, so the layer can be hidden when nothing is live.
  void update(double dt) {
    if (_particles.isEmpty) return;
    final step = dt.clamp(0.0, 0.05);
    for (final p in _particles) {
      p.velocity = Offset(
        p.velocity.dx * (1 - 1.2 * step),
        p.velocity.dy + _gravity * step,
      );
      p.position += p.velocity * step;
    }
    _particles.removeWhere((p) {
      p.life -= step;
      return p.life <= 0;
    });
    notifyListeners();
  }

  void clear() {
    if (_particles.isEmpty) return;
    _particles.clear();
    notifyListeners();
  }
}

/// Paints the live particles. Listens to the controller directly so thousands
/// of pieces never trigger a widget rebuild.
class ConfettiLayer extends StatelessWidget {
  const ConfettiLayer({required this.controller, super.key});

  final ConfettiController controller;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: _ConfettiPainter(controller), size: Size.infinite),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.controller) : super(repaint: controller);

  final ConfettiController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in controller._particles) {
      // Fade the last third of a piece's life so nothing pops out of existence.
      final alpha = (p.life / ConfettiController.lifetime).clamp(0.0, 1.0);
      paint.color = p.color.withValues(alpha: alpha);

      canvas.save();
      canvas.translate(p.position.dx, p.position.dy);
      canvas.rotate(p.spin * (1.0 - alpha) * 3);
      switch (p.shape) {
        case _Shape.square:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.7),
              const Radius.circular(2),
            ),
            paint,
          );
        case _Shape.circle:
          canvas.drawCircle(Offset.zero, p.size * 0.45, paint);
        case _Shape.ribbon:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset.zero,
                width: p.size * 0.35,
                height: p.size * 1.5,
              ),
              const Radius.circular(4),
            ),
            paint,
          );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
