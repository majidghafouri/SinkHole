import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../model/puzzle.dart';
import '../../model/token.dart';
import '../theme/app_theme.dart';
import '../theme/world_palette.dart';
import 'chunky.dart';
import 'token_view.dart';

/// The big white card in the middle of the screen.
///
/// It owns the only piece of puzzle state the engine does not: the memory
/// puzzle's reveal/hide/ask cycle, which is presentation rather than rules. The
/// card reports "I am answerable" through [onAnswerableChanged] so the answer
/// buttons can be disabled during a flash.
class PuzzleCard extends StatefulWidget {
  const PuzzleCard({
    required this.puzzle,
    required this.world,
    required this.boss,
    required this.onAnswerableChanged,
    this.replayToken = 0,
    this.dimmed = false,
    super.key,
  });

  final Puzzle? puzzle;
  final WorldPalette world;
  final bool boss;

  /// Fires when the card becomes answerable, or stops being answerable.
  final ValueChanged<bool> onAnswerableChanged;

  /// Bumped by the hint power-up to replay a memory flash.
  final int replayToken;

  /// Set while a wrong answer is being shown.
  final bool dimmed;

  @override
  State<PuzzleCard> createState() => _PuzzleCardState();
}

enum _Reveal { idle, flashing, hidden }

class _PuzzleCardState extends State<PuzzleCard> {
  _Reveal _reveal = _Reveal.idle;
  Timer? _revealTimer;
  int _lastReplayToken = 0;

  @override
  void initState() {
    super.initState();
    _syncPuzzle(null);
  }

  @override
  void didUpdateWidget(PuzzleCard old) {
    super.didUpdateWidget(old);
    if (old.puzzle != widget.puzzle) {
      _syncPuzzle(old.puzzle);
      return;
    }
    if (widget.replayToken != _lastReplayToken) {
      _lastReplayToken = widget.replayToken;
      if (_flashMs != null) _startReveal();
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  int? get _flashMs {
    final body = widget.puzzle?.body;
    return body is TokenGridBody ? body.flashMs : null;
  }

  void _syncPuzzle(Puzzle? old) {
    _revealTimer?.cancel();
    final flash = _flashMs;
    if (flash == null) {
      setState(() => _reveal = _Reveal.idle);
      widget.onAnswerableChanged(true);
      return;
    }
    setState(() => _reveal = _Reveal.flashing);
    widget.onAnswerableChanged(false);
    _startReveal(flash);
  }

  void _startReveal([int? ms]) {
    final flash = ms ?? _flashMs;
    if (flash == null) return;
    _revealTimer?.cancel();
    setState(() => _reveal = _Reveal.flashing);
    widget.onAnswerableChanged(false);
    _revealTimer = Timer(Duration(milliseconds: flash), () {
      if (!mounted) return;
      setState(() => _reveal = _Reveal.hidden);
      widget.onAnswerableChanged(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final world = widget.world;
    final puzzle = widget.puzzle;
    if (puzzle == null) {
      return const SizedBox.shrink();
    }

    return _CardShell(
      world: world,
      boss: widget.boss,
      dimmed: widget.dimmed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _Prompt(puzzle: puzzle, world: world, boss: widget.boss),
          const SizedBox(height: 18),
          Flexible(child: _buildBody(puzzle, world)),
        ],
      ),
    );
  }

  Widget _buildBody(Puzzle puzzle, WorldPalette world) {
    switch (puzzle.body) {
      case final TextBody body:
        return Center(
          child: FittedBox(
            child: Text(
              body.text,
              style: SinkType.rounded(
                SinkType.display.copyWith(fontSize: 64 * body.scale, color: world.onCard),
              ),
            ),
          ),
        );

      case final TokenRowBody body:
        return _TokenRow(tokens: body.tokens, world: world, chips: body.chips);

      case final TokenGridBody body:
        return _TokenGrid(
          body: body,
          world: world,
          // While flashing the grid is lit; once hidden it goes to a dashed
          // outline so "I saw something there" is never possible.
          revealed: _reveal == _Reveal.flashing,
        );
    }
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.world,
    required this.boss,
    required this.dimmed,
    required this.child,
  });

  final WorldPalette world;
  final bool boss;
  final bool dimmed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final frame = boss ? const Color(0xFFFFD166) : world.onCard.withValues(alpha: 0.22);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: dimmed ? 0.55 : 1,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.86, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        builder: (context, t, inner) => Transform.scale(scale: t, child: inner),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: world.cardSurface,
            borderRadius: BorderRadius.circular(boss ? 30 : 28),
            border: Border.all(color: frame, width: boss ? 6 : 0),
            boxShadow: <BoxShadow>[
              BoxShadow(color: world.shadow, offset: const Offset(0, 8), blurRadius: 0),
              if (boss)
                BoxShadow(
                  color: frame.withValues(alpha: 0.55),
                  blurRadius: 26,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.puzzle, required this.world, required this.boss});

  final Puzzle puzzle;
  final WorldPalette world;
  final bool boss;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (boss) ...<Widget>[
          const Icon(Icons.workspace_premium_rounded, size: 20, color: Color(0xFFD99A00)),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            puzzle.kind.prompt,
            textAlign: TextAlign.center,
            style: SinkType.rounded(
              SinkType.prompt.copyWith(
                color: boss ? const Color(0xFFD99A00) : world.onCard,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TokenRow extends StatelessWidget {
  const _TokenRow({required this.tokens, required this.world, required this.chips});

  final List<Token> tokens;
  final WorldPalette world;
  final bool chips;

  @override
  Widget build(BuildContext context) {
    // A long pattern wraps rather than shrinking to illegibility.
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        runAlignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: <Widget>[
          for (final token in tokens)
            chips
                ? ChunkyTile(
                    fill: world.accents[token.color % world.accents.length].withValues(
                      alpha: 0.18,
                    ),
                    outline: world.onCard.withValues(alpha: 0.18),
                    outlineWidth: 2,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: TokenView(
                      token: token,
                      world: world,
                      size: 34,
                      color: world.onCard,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: TokenView(
                      token: token,
                      world: world,
                      size: 30,
                      color: world.onCard,
                    ),
                  ),
        ],
      ),
    );
  }
}

class _TokenGrid extends StatelessWidget {
  const _TokenGrid({required this.body, required this.world, required this.revealed});

  final TokenGridBody body;
  final WorldPalette world;

  /// True while the memory flash is on screen.
  final bool revealed;

  /// The symbol being asked about, printed beside the prompt once the flash is
  /// over. It is suppressed during the flash, where it would give the answer
  /// away.
  Token? get label => revealed ? null : body.revealLabel;

  /// The largest a grid is allowed to get, in logical pixels. Capping it keeps a
  /// tall card from pushing the answer buttons off the screen, and the available
  /// height shrinks it further on short devices.
  static const double maxGridSide = 260;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.biggest.shortestSide;
            return Center(
              child: SizedBox.square(
                dimension: available > maxGridSide ? maxGridSide : available,
                child: _grid(),
              ),
            );
          },
        ),
        if (label != null) ...<Widget>[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                'FIND',
                style: SinkType.rounded(
                  SinkType.caption.copyWith(
                    color: world.onCard.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TokenView(token: label!, world: world, size: 30, color: world.onCard),
            ],
          ),
        ],
      ],
    );
  }

  Widget _grid() {
    // A 4x4 board needs smaller type than a 3x3 to stay readable in the same
    // square, so the glyph and text scale with the cell size.
    final density = 1.0 - (body.cols - 3) * 0.16;
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: body.cols,
        mainAxisSpacing: 7,
        crossAxisSpacing: 7,
      ),
      itemCount: body.cells.length,
      itemBuilder: (context, index) {
        final token = body.cells[index];
        final lit = revealed && token.isGlyph;
        return ChunkyTile(
          fill: lit
              ? world.accents[token.color % world.accents.length].withValues(alpha: 0.22)
              : Colors.transparent,
          outline: world.onCard.withValues(alpha: lit ? 0.3 : 0.18),
          outlineWidth: 2,
          radius: SinkShape.chipRadius,
          // A cell the player must fill shows a question mark; a cell that was
          // lit during a memory flash goes to a bare dashed outline once hidden.
          dashed: !revealed || token.isBlank,
          child: Center(
            child: token.isBlank
                ? Text(
                    '?',
                    style: SinkType.rounded(
                      SinkType.numeral.copyWith(
                        color: world.accents.last,
                        fontSize: 26 * density,
                      ),
                    ),
                  )
                : lit
                ? TokenView(
                    token: token,
                    world: world,
                    size: 30 * density,
                    color: world.onCard,
                  )
                : const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

/// The small A-I reference the player uses to answer a memory puzzle.
class CellReferenceGrid extends StatelessWidget {
  const CellReferenceGrid({required this.world, this.size = 118, super.key});

  final WorldPalette world;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: 9,
        itemBuilder: (context, index) => ChunkyTile(
          fill: world.cardSurface,
          outline: world.onCard.withValues(alpha: 0.14),
          outlineWidth: 1.5,
          radius: 10,
          padding: EdgeInsets.zero,
          child: Center(
            child: Text(
              cellLabels[index],
              style: SinkType.rounded(
                SinkType.label.copyWith(
                  color: world.onCard.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating `+2.4s` text that rises and fades after a solve.
class RewardPopup extends StatelessWidget {
  const RewardPopup({
    required this.text,
    required this.color,
    required this.visible,
    super.key,
  });

  final String text;
  final Color color;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : const Offset(0, -1.1),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 700),
          opacity: visible ? 1 : 0,
          child: Transform.rotate(
            angle: math.sin(visible ? 1 : 0) * 0.05,
            child: Text(
              text,
              style: SinkType.rounded(
                SinkType.title.copyWith(
                  color: color,
                  fontSize: 30,
                  shadows: const <Shadow>[
                    Shadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 3)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
