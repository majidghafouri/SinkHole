import 'dart:math' as math;

import 'package:flutter/material.dart';

/// What Bloop is doing right now. Every reaction in the brief maps to one.
enum BloopMood {
  idle,

  /// Squeezed by a tap.
  squish,

  /// A correct answer landed.
  cheer,

  /// Wrong answer: bracing.
  wince,

  /// Low on time: a bead of sweat appears.
  sweat,

  /// The last three seconds: eyes go wide.
  panic,

  /// A level transition: arms up.
  celebrate,

  /// Off the edge of the floor, tumbling.
  tumble,
}

/// Bloop: a round, expressive blob.
///
/// Drawn rather than animated from assets so the whole character is a few
/// hundred bytes of geometry, reacts continuously to the game state, and can
/// wear a hat for each unlockable skin.
class Bloop extends StatefulWidget {
  const Bloop({
    required this.mood,
    this.size = 120,
    this.skin = 'classic',
    this.bodyColor,
    this.accentColor,
    this.tumbleProgress = 0,
    super.key,
  });

  final BloopMood mood;
  final double size;
  final String skin;
  final Color? bodyColor;
  final Color? accentColor;

  /// 0 to 1 through the fall, used to spin and shrink Bloop.
  final double tumbleProgress;

  @override
  State<Bloop> createState() => _BloopState();
}

class _BloopState extends State<Bloop> with TickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  /// Drives the one-shot reactions, from a squash back to rest.
  late final AnimationController _react =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420))
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _react.value = 0;
            _react.stop();
          }
        });

  @override
  void didUpdateWidget(Bloop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) {
      _react.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    _react.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_bob, _react]),
      builder: (context, _) {
        final t = _bob.value * 2 * math.pi;
        final react = Curves.easeOutBack.transform(_react.value.clamp(0.0, 1.0));

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _BloopPainter(
              mood: widget.mood,
              bob: t,
              react: react,
              tumble: widget.tumbleProgress.clamp(0.0, 1.0),
              body: widget.bodyColor ?? const Color(0xFF6FE3C4),
              accent: widget.accentColor ?? const Color(0xFF2A1E4F),
              skin: widget.skin,
            ),
          ),
        );
      },
    );
  }
}

class _BloopPainter extends CustomPainter {
  _BloopPainter({
    required this.mood,
    required this.bob,
    required this.react,
    required this.tumble,
    required this.body,
    required this.accent,
    required this.skin,
  });

  final BloopMood mood;
  final double bob;
  final double react;
  final double tumble;
  final Color body;
  final Color accent;
  final String skin;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (tumble > 0) {
      // Falling: Bloop spins away and drops out of frame.
      canvas.translate(0, tumble * size.height * 0.9);
      canvas.rotate(tumble * 2.4 * math.pi);
      canvas.scale(1 - tumble * 0.45);
    }
    canvas.translate(0, math.sin(bob) * radius * 0.045);

    _paintShadow(canvas, radius);
    _paintBody(canvas, radius);
    _paintFace(canvas, radius);
    _paintSkin(canvas, radius);
    canvas.restore();
  }

  void _paintShadow(Canvas canvas, double radius) {
    final shrink = 1 - (react * 0.12) - (tumble * 0.5);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, radius * 0.98),
        width: radius * 1.5 * shrink,
        height: radius * 0.3 * shrink,
      ),
      Paint()..color = const Color(0x33000000),
    );
  }

  void _paintBody(Canvas canvas, double radius) {
    final unit = radius / 100;
    canvas.save();
    canvas.scale(unit);
    _paintBodyUnit(canvas, 100);
    canvas.restore();
  }

  void _paintBodyUnit(Canvas canvas, double radius) {
    // Squashing on a tap and stretching on a cheer is what sells the jelly.
    final squashX = _squashX();
    final squashY = _squashY();

    final path = Path();
    // A blobby circle: four cubic arcs with slightly different radii.
    final rx = radius * 0.92 * squashX;
    final ry = radius * 0.88 * squashY;
    path.moveTo(0, -ry);
    path.cubicTo(rx * 0.72, -ry, rx, -ry * 0.72, rx, 0);
    path.cubicTo(rx, ry * 0.72, rx * 0.72, ry, 0, ry);
    path.cubicTo(-rx * 0.72, ry, -rx, ry * 0.72, -rx, 0);
    path.cubicTo(-rx, -ry * 0.72, -rx * 0.72, -ry, 0, -ry);
    path.close();

    canvas.drawPath(
      path.shift(Offset(0, radius * 0.06)),
      Paint()..color = const Color(0x22000000),
    );

    final fill = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.45),
        radius: 1.1,
        colors: <Color>[
          Color.lerp(body, Colors.white, 0.42)!,
          body,
          Color.lerp(body, accent, 0.30)!,
        ],
        stops: const <double>[0, 0.55, 1],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
    canvas.drawPath(path, fill);

    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.085
        ..strokeJoin = StrokeJoin.round,
    );

    // A small gloss highlight sells the soft 3D look.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-radius * 0.34, -radius * 0.5),
        width: radius * 0.36,
        height: radius * 0.2,
      ),
      Paint()..color = const Color(0x4DFFFFFF),
    );
  }

  double _squashX() {
    if (mood == BloopMood.squish) return 1 + react * 0.16;
    if (mood == BloopMood.cheer) return 1 - react * 0.10;
    return 1 + math.sin(bob) * 0.018;
  }

  double _squashY() {
    if (mood == BloopMood.squish) return 1 - react * 0.16;
    if (mood == BloopMood.cheer) return 1 + react * 0.14;
    return 1 - math.sin(bob) * 0.018;
  }

  /// The face is authored against a 100-unit body radius and scaled to whatever
  /// size the widget was given, so Bloop reads the same at 34px and at 148px.
  void _paintFace(Canvas canvas, double radius) {
    canvas.save();
    canvas.scale(radius / 100);
    _paintFaceUnit(canvas, 100);
    canvas.restore();
  }

  /// Proportions of the white part of one eye, as a fraction of the body radius.
  /// These are small on purpose: the eyes sit inside the blob, they do not fill it.
  static const double _scleraWidth = 0.30;
  static const double _pupilWidth = 0.13;

  void _paintFaceUnit(Canvas canvas, double radius) {
    final eyeY = -radius * 0.14;
    final eyeDx = radius * 0.30;

    // Sweat widens the eyes before the panic zone fully hits.
    final openFactor = switch (mood) {
      BloopMood.panic => 1.35,
      BloopMood.cheer || BloopMood.celebrate => 0.5,
      BloopMood.sweat => 1.15,
      BloopMood.wince => 0.22,
      _ => 1.0,
    };

    final eyePaint = Paint()..color = accent;
    final whitePaint = Paint()..color = Colors.white;
    final sclera = radius * _scleraWidth;

    for (final side in <double>[-1, 1]) {
      final center = Offset(eyeDx * side, eyeY);
      canvas.drawOval(
        Rect.fromCenter(center: center, width: sclera, height: sclera * openFactor),
        whitePaint,
      );
      if (mood == BloopMood.panic) {
        canvas.drawCircle(center, sclera * 0.26, eyePaint);
        canvas.drawCircle(
          center.translate(-sclera * 0.09, -sclera * 0.11),
          sclera * 0.09,
          Paint()..color = Colors.white,
        );
      } else {
        canvas.drawOval(
          Rect.fromCenter(
            center: center,
            width: radius * _pupilWidth,
            height: radius * _pupilWidth * 1.7 * openFactor,
          ),
          eyePaint,
        );
      }
    }

    _paintMouth(canvas, radius);
    _paintCheeks(canvas, radius);

    if (mood == BloopMood.sweat || mood == BloopMood.panic) {
      _paintSweat(canvas, radius);
    }
  }

  void _paintMouth(Canvas canvas, double radius) {
    final mouth = Path();
    final w = radius * 0.3;
    final y = radius * 0.34;

    switch (mood) {
      case BloopMood.cheer:
      case BloopMood.celebrate:
        // A big open grin.
        mouth.moveTo(-w, y - radius * 0.04);
        mouth.quadraticBezierTo(0, y + radius * 0.34, w, y - radius * 0.04);
        mouth.quadraticBezierTo(0, y + radius * 0.06, -w, y - radius * 0.04);
      case BloopMood.wince:
        // A squiggle, for "that was not the floor's fault".
        mouth.moveTo(-w, y);
        mouth.lineTo(-w * 0.33, y - radius * 0.1);
        mouth.lineTo(w * 0.33, y + radius * 0.1);
        mouth.lineTo(w, y);
      case BloopMood.panic:
        // A small round "o".
        mouth.addOval(
          Rect.fromCenter(center: Offset(0, y), width: w * 0.85, height: w * 0.95),
        );
      case BloopMood.tumble:
        mouth.addOval(
          Rect.fromCenter(center: Offset(0, y), width: w * 0.7, height: w * 0.8),
        );
      case BloopMood.squish:
      case BloopMood.sweat:
      case BloopMood.idle:
        mouth.moveTo(-w * 0.6, y);
        mouth.quadraticBezierTo(0, y + radius * 0.13, w * 0.6, y);
    }

    canvas.drawPath(
      mouth,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.075
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintCheeks(Canvas canvas, double radius) {
    if (mood == BloopMood.wince || mood == BloopMood.idle) return;
    final paint = Paint()
      ..color = const Color(0x55FF6B9D)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    for (final side in <double>[-1, 1]) {
      canvas.drawCircle(
        Offset(radius * 0.66 * side, radius * 0.22),
        radius * 0.11,
        paint,
      );
    }
  }

  void _paintSweat(Canvas canvas, double radius) {
    // A bead that slides down and jitters, so the low-time tell is obvious
    // without the player having to read the bar.
    final progress = (bob / (2 * math.pi)) % 1.0;
    final y = -radius * 0.5 + progress * radius * 0.55;
    final x = radius * 0.62 + math.sin(progress * math.pi) * radius * 0.05;
    final drop = Path()
      ..moveTo(x, y - radius * 0.14)
      ..cubicTo(
        x + radius * 0.12,
        y + radius * 0.02,
        x + radius * 0.09,
        y + radius * 0.16,
        x,
        y + radius * 0.16,
      )
      ..cubicTo(
        x - radius * 0.09,
        y + radius * 0.16,
        x - radius * 0.12,
        y + radius * 0.02,
        x,
        y - radius * 0.14,
      );
    canvas.drawPath(drop, Paint()..color = const Color(0xFF7DD3FC));
  }

  /// Hats earned by reaching each world. Purely decorative, so an unknown
  /// skin simply draws nothing extra.
  void _paintSkin(Canvas canvas, double radius) {
    final unit = radius / 100;
    canvas.save();
    canvas.scale(unit);
    _paintSkinUnit(canvas, 100);
    canvas.restore();
  }

  void _paintSkinUnit(Canvas canvas, double radius) {
    switch (skin) {
      case 'wizard':
        _paintWizardHat(canvas, radius);
      case 'astronaut':
        _paintHelmet(canvas, radius);
      case 'pirate':
        _paintPirateHat(canvas, radius);
      case 'classic':
      default:
        break;
    }
  }

  void _paintWizardHat(Canvas canvas, double radius) {
    final brim = Path()
      ..moveTo(-radius * 0.78, -radius * 0.74)
      ..quadraticBezierTo(0, -radius * 0.52, radius * 0.78, -radius * 0.74)
      ..lineTo(radius * 0.62, -radius * 0.82)
      ..quadraticBezierTo(0, -radius * 0.66, -radius * 0.62, -radius * 0.82)
      ..close();
    canvas.drawPath(brim, Paint()..color = const Color(0xFF7C4DFF));

    final cone = Path()
      ..moveTo(-radius * 0.46, -radius * 0.76)
      ..quadraticBezierTo(-radius * 0.3, -radius * 1.4, radius * 0.12, -radius * 1.5)
      ..quadraticBezierTo(radius * 0.5, -radius * 1.3, radius * 0.46, -radius * 0.76)
      ..close();
    canvas.drawPath(cone, Paint()..color = const Color(0xFF9B6BFF));
  }

  void _paintHelmet(Canvas canvas, double radius) {
    final dome = Path()
      ..moveTo(-radius * 0.8, -radius * 0.5)
      ..arcToPoint(
        Offset(radius * 0.8, -radius * 0.5),
        radius: Radius.circular(radius),
        clockwise: true,
      )
      ..close();
    canvas.drawPath(
      dome,
      Paint()
        ..color = const Color(0xCCF4F7FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.1,
    );
    canvas.drawCircle(
      Offset(radius * 0.34, -radius * 0.78),
      radius * 0.07,
      Paint()..color = const Color(0xFFFF6B9D),
    );
  }

  void _paintPirateHat(Canvas canvas, double radius) {
    final skull = Path()
      ..moveTo(-radius * 0.72, -radius * 0.78)
      ..lineTo(-radius * 0.5, -radius * 1.28)
      ..quadraticBezierTo(0, -radius * 1.44, radius * 0.5, -radius * 1.28)
      ..lineTo(radius * 0.72, -radius * 0.78)
      ..quadraticBezierTo(0, -radius * 0.6, -radius * 0.72, -radius * 0.78)
      ..close();
    canvas.drawPath(skull, Paint()..color = const Color(0xFF1E2A4A));

    // A simple cross-bones mark.
    final bone = Paint()
      ..color = Colors.white
      ..strokeWidth = radius * 0.09
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(
        Offset(-radius * 0.24, -radius * 1.02),
        Offset(radius * 0.24, -radius * 1.16),
        bone,
      )
      ..drawLine(
        Offset(radius * 0.24, -radius * 1.02),
        Offset(-radius * 0.24, -radius * 1.16),
        bone,
      );
  }

  @override
  bool shouldRepaint(_BloopPainter old) =>
      old.mood != mood ||
      old.react != react ||
      old.tumble != tumble ||
      old.bob != bob ||
      old.skin != skin ||
      old.body != body;
}
