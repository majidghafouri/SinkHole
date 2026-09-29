import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// A chunky, springy tap target.
///
/// Every tappable thing in the game goes through this so the squash, the press
/// scale and the ink response stay identical, and so the brief's "instant
/// feedback within 100ms" holds for the whole UI.
class ChunkyButton extends StatefulWidget {
  const ChunkyButton({
    required this.child,
    required this.onTap,
    this.fill,
    this.onFill,
    this.outline,
    this.radius = SinkShape.radius,
    this.outlineWidth = SinkShape.outline,
    this.elevation = 5,
    this.enabled = true,
    this.padding,
    this.semanticLabel,
    this.onLongPress,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? fill;
  final Color? onFill;
  final Color? outline;
  final double radius;
  final double outlineWidth;

  /// The thickness of the drop shadow beneath the button.
  final double elevation;

  final bool enabled;
  final EdgeInsetsGeometry? padding;
  final String? semanticLabel;

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
    reverseDuration: const Duration(milliseconds: 220),
  );

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.enabled) return;
    HapticFeedback.selectionClick();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final fill = widget.fill ?? Theme.of(context).colorScheme.primary;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTapDown: (_) => _press.forward(),
        onTapUp: (_) => _press.reverse(),
        onTapCancel: _press.reverse,
        onTap: widget.enabled ? _handleTap : null,
        onLongPress: widget.onLongPress,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _press,
          builder: (context, child) {
            // Pressing drives three things at once: a slight shrink, a
            // shallower shadow, and a hint of rotation for the candy feel.
            final t = Curves.easeOut.transform(_press.value);
            return Transform.translate(
              offset: Offset(0, t * 2),
              child: Transform.scale(
                scale: 1 - t * 0.04,
                child: Transform.rotate(
                  angle: t * 0.012,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.enabled ? fill : fill.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(widget.radius),
                      border: Border.all(
                        color: widget.outline ?? const Color(0xFF1B1230),
                        width: widget.outlineWidth,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: const Color(0x44000000),
                          offset: Offset(0, widget.elevation * (1 - t * 0.7)),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: child,
                  ),
                ),
              ),
            );
          },
          child: Padding(
            padding: widget.padding ?? const EdgeInsets.all(14),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// A rounded, outlined tile used for puzzle chips and grid cells.
class ChunkyTile extends StatelessWidget {
  const ChunkyTile({
    required this.child,
    this.fill,
    this.outline,
    this.outlineWidth = SinkShape.outline,
    this.radius = SinkShape.chipRadius,
    this.dashed = false,
    this.padding,
    this.dimmed = false,
    super.key,
  });

  final Widget child;
  final Color? fill;
  final Color? outline;
  final double outlineWidth;
  final double radius;

  /// Dashed outlines mark a cell the player has to fill.
  final bool dashed;

  final EdgeInsetsGeometry? padding;

  /// Fades the tile without removing it from the layout.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final borderColor = outline ?? const Color(0xFF1B1230);
    return Opacity(
      opacity: dimmed ? 0.35 : 1,
      child: CustomPaint(
        painter: dashed
            ? _DashedRoundedBorder(
                color: borderColor,
                strokeWidth: outlineWidth,
                radius: radius,
              )
            : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill ?? Colors.transparent,
            borderRadius: BorderRadius.circular(radius),
            border: dashed ? null : Border.all(color: borderColor, width: outlineWidth),
          ),
          child: Padding(padding: padding ?? const EdgeInsets.all(8), child: child),
        ),
      ),
    );
  }
}

class _DashedRoundedBorder extends CustomPainter {
  const _DashedRoundedBorder({
    required this.color,
    required this.strokeWidth,
    required this.radius,
  });

  final Color color;
  final double strokeWidth;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 7.0;
      const gap = 6.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRoundedBorder old) =>
      old.color != color || old.strokeWidth != strokeWidth || old.radius != radius;
}

/// A small pill label, used for streaks, world names and counters.
class ChunkyPill extends StatelessWidget {
  const ChunkyPill({
    required this.child,
    this.fill,
    this.outline,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    super.key,
  });

  final Widget child;
  final Color? fill;
  final Color? outline;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill ?? Colors.transparent,
        borderRadius: BorderRadius.circular(SinkShape.pillRadius),
        border: outline == null ? null : Border.all(color: outline!, width: 2),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A full-screen tappable scrim used behind menus that overlay the game.
class TapScrim extends StatelessWidget {
  const TapScrim({required this.onTap, this.color, this.child, super.key});

  final VoidCallback onTap;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ColoredBox(color: color ?? const Color(0xB3000000), child: child),
    );
  }
}
