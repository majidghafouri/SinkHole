import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/world_palette.dart';
import 'chunky.dart';

/// The top row: depth on the left, streak flame in the middle, cracks on the
/// right. Nothing else lives up here, so the three things that matter are the
/// only things a thumb-eye can find.
class RunStatusBar extends StatelessWidget {
  const RunStatusBar({
    required this.world,
    required this.depth,
    required this.streak,
    required this.cracks,
    required this.maxCracks,
    required this.shielded,
    required this.boss,
    required this.bossStep,
    required this.bossSteps,
    required this.daily,
    this.ghostDepth,
    super.key,
  });

  final WorldPalette world;
  final int depth;
  final int streak;
  final int cracks;
  final int maxCracks;
  final bool shielded;
  final bool boss;
  final int bossStep;
  final int bossSteps;
  final bool daily;

  /// Where a previous run fell, so the ghost marker can sit on the floor.
  final int? ghostDepth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _DepthReadout(world: world, depth: depth, daily: daily),
        const Spacer(),
        if (boss)
          _BossPips(world: world, step: bossStep, total: bossSteps)
        else
          _StreakFlame(world: world, streak: streak),
        const Spacer(),
        _CrackPips(world: world, cracks: cracks, max: maxCracks, shielded: shielded),
      ],
    );
  }
}

class _DepthReadout extends StatelessWidget {
  const _DepthReadout({required this.world, required this.depth, required this.daily});

  final WorldPalette world;
  final int depth;
  final bool daily;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          daily ? 'DAILY' : 'DEPTH',
          style: SinkType.rounded(SinkType.caption.copyWith(color: world.muted)),
        ),
        RollingNumber(value: depth, color: Colors.white),
      ],
    );
  }
}

/// The depth counter, which rolls like a slot machine when it changes.
class RollingNumber extends StatelessWidget {
  const RollingNumber({
    required this.value,
    this.color = Colors.white,
    this.style,
    super.key,
  });

  final int value;
  final Color color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => ClipRect(
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.55),
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
      ),
      child: Text(
        '$value',
        key: ValueKey<int>(value),
        style: SinkType.rounded((style ?? SinkType.display).copyWith(color: color)),
      ),
    );
  }
}

class _StreakFlame extends StatelessWidget {
  const _StreakFlame({required this.world, required this.streak});

  final WorldPalette world;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final colors = Worlds.streakFlame(streak);
    final alive = streak > 0;
    // The flame grows every few answers, then changes colour.
    final scale = alive ? (1 + math.min(streak, 12) * 0.045) : 0.8;

    return AnimatedScale(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      scale: scale,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: alive
            ? _FlameShape(
                key: ValueKey<int>(streak),
                colors: colors,
                size: 26 + math.min(streak, 12) * 1.4,
              )
            : SizedBox(
                key: const ValueKey<String>('cold'),
                width: 30,
                height: 30,
                child: Icon(
                  Icons.local_fire_department_rounded,
                  size: 22,
                  color: world.muted.withValues(alpha: 0.45),
                ),
              ),
      ),
    );
  }
}

class _FlameShape extends StatelessWidget {
  const _FlameShape({required this.colors, required this.size, super.key});

  final List<Color> colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _FlamePainter(colors)),
    );
  }
}

class _FlamePainter extends CustomPainter {
  const _FlamePainter(this.colors);
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    // A gradient needs two stops. The lowest tier would otherwise hand it a
    // single colour, which asserts during paint.
    final colors = this.colors.length >= 2
        ? this.colors
        : <Color>[this.colors.first, Color.lerp(this.colors.first, Colors.white, 0.35)!];

    final path = Path()
      ..moveTo(size.width * 0.5, 0)
      ..cubicTo(
        size.width * 0.92,
        size.height * 0.34,
        size.width * 0.86,
        size.height * 0.78,
        size.width * 0.5,
        size.height,
      )
      ..cubicTo(
        size.width * 0.14,
        size.height * 0.78,
        size.width * 0.08,
        size.height * 0.34,
        size.width * 0.5,
        0,
      )
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ).createShader(Offset.zero & size),
    );
    // The outline keeps the flame readable against a bright card behind it.
    // A bright core keeps the flame readable on any background.
    canvas.drawCircle(
      size.center(Offset.zero),
      size.width * 0.16,
      Paint()..color = Colors.white.withValues(alpha: 0.75),
    );
  }

  @override
  bool shouldRepaint(_FlamePainter old) => old.colors != colors;
}

class _CrackPips extends StatelessWidget {
  const _CrackPips({
    required this.world,
    required this.cracks,
    required this.max,
    required this.shielded,
  });

  final WorldPalette world;
  final int cracks;
  final int max;
  final bool shielded;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < max; i++)
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: i < cracks ? 1 : 0.32,
              child: Icon(
                i < cracks ? Icons.heart_broken_rounded : Icons.favorite_rounded,
                size: 21,
                color: i < cracks ? const Color(0xFFFF5470) : world.muted,
              ),
            ),
          ),
        // A shield takes the next hit, so it is shown as a live pip.
        AnimatedScale(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutBack,
          scale: shielded ? 1 : 0,
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(Icons.shield_rounded, size: 21, color: world.accents[1]),
          ),
        ),
      ],
    );
  }
}

class _BossPips extends StatelessWidget {
  const _BossPips({required this.world, required this.step, required this.total});

  final WorldPalette world;
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFD166);
    return ChunkyPill(
      fill: const Color(0x33FFD166),
      outline: gold,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.workspace_premium_rounded, size: 15, color: gold),
          const SizedBox(width: 6),
          Text(
            'BOSS',
            style: SinkType.rounded(SinkType.caption.copyWith(color: gold, fontSize: 12)),
          ),
          const SizedBox(width: 8),
          for (var i = 1; i <= total; i++)
            Container(
              margin: const EdgeInsets.only(right: 4),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i <= step ? gold : gold.withValues(alpha: 0.25),
              ),
            ),
        ],
      ),
    );
  }
}

/// The ghost marker: where a previous run of the daily fell.
class GhostMarker extends StatelessWidget {
  const GhostMarker({
    required this.ghostDepth,
    required this.currentDepth,
    required this.world,
    super.key,
  });

  final int ghostDepth;
  final int currentDepth;
  final WorldPalette world;

  @override
  Widget build(BuildContext context) {
    final passed = currentDepth > ghostDepth;
    return ChunkyPill(
      fill: Colors.white.withValues(alpha: 0.12),
      outline: Colors.white.withValues(alpha: 0.3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            passed ? Icons.check_circle_rounded : Icons.history_rounded,
            size: 14,
            color: passed ? const Color(0xFF3DDC7F) : Colors.white70,
          ),
          const SizedBox(width: 6),
          Text(
            passed ? 'GHOST BEATEN' : 'GHOST $ghostDepth',
            style: SinkType.rounded(
              SinkType.caption.copyWith(
                fontSize: 11,
                color: passed ? const Color(0xFF3DDC7F) : Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
