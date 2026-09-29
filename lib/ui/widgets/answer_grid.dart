import 'package:flutter/material.dart';

import '../../model/token.dart';
import '../theme/app_theme.dart';
import '../theme/world_palette.dart';
import 'chunky.dart';
import 'token_view.dart';

/// How an option is drawn after the player has answered.
enum AnswerState { idle, correct, wrong, dimmed, shielded }

/// A large, rounded answer button in the thumb zone.
///
/// The button count is two or four, so the layout is a single row or a 2x2
/// grid. Every button is at least 64dp tall, per the brief.
class AnswerGrid extends StatelessWidget {
  const AnswerGrid({
    required this.options,
    required this.world,
    required this.selected,
    required this.solutionIndex,
    required this.onTap,
    required this.enabled,
    this.locked = false,
    super.key,
  });

  final List<Token> options;
  final WorldPalette world;

  /// The option the player tapped, or -1.
  final int selected;

  final int solutionIndex;
  final ValueChanged<int> onTap;
  final bool enabled;

  /// True once an answer has been given, so the buttons stop responding and
  /// show how the answer compared.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    if (options.length <= 2) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < options.length; i++) ...<Widget>[
            _AnswerButton(
              token: options[i],
              index: i,
              world: world,
              state: _stateFor(i),
              onTap: () => onTap(i),
              enabled: enabled,
            ),
            if (i != options.length - 1) const SizedBox(height: 10),
          ],
        ],
      );
    }

    // Four options in a 2x2 grid: the widest targets without straying from a
    // one-thumb portrait layout.
    const gap = 10.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 420 ? 4 : 2;
        final rows = (options.length / columns).ceil();
        final cellWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
        // Cap the height so a 2x2 grid never eats the whole screen; 64 is the
        // brief's minimum tap target.
        final cellHeight = ((cellWidth - 12) * 0.62).clamp(64.0, 104.0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var row = 0; row < rows; row++) ...<Widget>[
              if (row > 0) const SizedBox(height: gap),
              Row(
                children: <Widget>[
                  for (var col = 0; col < columns; col++) ...<Widget>[
                    if (col > 0) const SizedBox(width: gap),
                    if (row * columns + col < options.length)
                      SizedBox(
                        width: cellWidth,
                        height: cellHeight,
                        child: _AnswerButton(
                          token: options[row * columns + col],
                          index: row * columns + col,
                          world: world,
                          state: _stateFor(row * columns + col),
                          onTap: () => onTap(row * columns + col),
                          enabled: enabled,
                          compact: true,
                        ),
                      ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  AnswerState _stateFor(int index) {
    if (!locked) return AnswerState.idle;
    if (index == solutionIndex) return AnswerState.correct;
    if (index == selected) return AnswerState.wrong;
    return AnswerState.dimmed;
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.token,
    required this.index,
    required this.world,
    required this.state,
    required this.onTap,
    required this.enabled,
    this.compact = false,
  });

  final Token token;
  final int index;
  final WorldPalette world;
  final AnswerState state;
  final VoidCallback onTap;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final base = world.buttonFill(index);
    final (fill, outline, onFill) = switch (state) {
      AnswerState.idle => (base, world.onCard, world.onButton(index)),
      AnswerState.correct => (
        const Color(0xFF3DDC7F),
        const Color(0xFF14522F),
        Colors.white,
      ),
      AnswerState.wrong => (
        const Color(0xFFFF6B7D),
        const Color(0xFF6B1020),
        Colors.white,
      ),
      AnswerState.dimmed => (
        base.withValues(alpha: 0.28),
        world.onCard.withValues(alpha: 0.2),
        world.onButton(index).withValues(alpha: 0.5),
      ),
      AnswerState.shielded => (
        const Color(0xFF7DD3FC),
        const Color(0xFF10405C),
        Colors.white,
      ),
    };

    return ChunkyButton(
      fill: fill,
      outline: outline,
      onFill: onFill,
      enabled: enabled,
      onTap: onTap,
      radius: SinkShape.radius,
      padding: EdgeInsets.zero,
      semanticLabel: 'Answer option ${index + 1}',
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          if (state == AnswerState.correct || state == AnswerState.shielded)
            Positioned.fill(child: _CorrectGlow(color: onFill)),
          Center(
            child: TokenView(
              token: token,
              world: world,
              size: compact ? 36 : 44,
              color: onFill,
            ),
          ),
          if (state == AnswerState.correct)
            Positioned(
              right: 8,
              top: 6,
              child: Icon(
                Icons.check_circle_rounded,
                size: 22,
                color: onFill.withValues(alpha: 0.9),
              ),
            )
          else if (state == AnswerState.wrong)
            Positioned(
              right: 8,
              top: 6,
              child: Icon(
                Icons.cancel_rounded,
                size: 22,
                color: onFill.withValues(alpha: 0.9),
              ),
            ),
        ],
      ),
    );
  }
}

/// A quick expanding ring behind a correct answer.
class _CorrectGlow extends StatefulWidget {
  const _CorrectGlow({required this.color});
  final Color color;

  @override
  State<_CorrectGlow> createState() => _CorrectGlowState();
}

class _CorrectGlowState extends State<_CorrectGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_c.value);
        return CustomPaint(
          painter: _RingPainter(progress: t, color: widget.color),
          size: Size.infinite,
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = size.shortestSide;
    final radius = shortest * (0.3 + progress * 0.75);
    canvas.drawCircle(
      size.center(Offset.zero),
      radius,
      Paint()
        ..color = color.withValues(alpha: (1 - progress) * 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = shortest * 0.08 * (1 - progress),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
