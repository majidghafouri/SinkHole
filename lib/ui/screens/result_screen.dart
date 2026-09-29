import 'package:flutter/material.dart';

import '../../core/difficulty.dart';
import '../../data/player_profile.dart';
import '../../model/puzzle.dart';
import '../../model/run_result.dart';
import '../theme/app_theme.dart';
import '../theme/world_palette.dart';
import '../widgets/bloop.dart';
import '../widgets/chunky.dart';
import '../widgets/run_status_bar.dart';

/// The near-miss screen: how deep, how close, and one tap to go again.
class ResultScreen extends StatefulWidget {
  const ResultScreen({
    required this.result,
    required this.profile,
    required this.onPlayAgain,
    required this.onHome,
    this.daily = false,
    super.key,
  });

  final RunResult result;
  final Profile profile;
  final VoidCallback onPlayAgain;
  final VoidCallback onHome;
  final bool daily;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

/// The tumble and the card landing are two separate controllers, hence the
/// regular `TickerProviderStateMixin`.
class _ResultScreenState extends State<ResultScreen> with TickerProviderStateMixin {
  late final AnimationController _fall = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..forward();

  late final AnimationController _card = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();

  @override
  void dispose() {
    _fall.dispose();
    _card.dispose();
    super.dispose();
  }

  /// The line that turns a score into a goal.
  String get _nearMiss {
    final best = widget.profile.bestDepth;
    final depth = widget.result.depth;
    final gap = best - depth;
    if (depth >= best && best > 0) {
      return 'New best! That is a new floor on the map.';
    }
    if (gap <= 0) return 'Your deepest run yet.';
    if (gap <= 3) return 'Only $gap more to beat your best!';
    if (gap <= 10) return '$gap more to match your best.';
    return 'Your best is depth $best.';
  }

  @override
  Widget build(BuildContext context) {
    final world = Worlds.forIndex(widget.result.worldIndex);
    final result = widget.result;

    return WorldScope(
      world: world,
      child: Scaffold(
        backgroundColor: world.skyBottom,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[world.skyTop, world.skyBottom],
                ),
              ),
            ),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  children: <Widget>[
                    // Bloop tumbles in, then the card lands.
                    AnimatedBuilder(
                      animation: _fall,
                      builder: (context, _) => Transform.translate(
                        offset: Offset(0, (1 - _fall.value) * -160),
                        child: Opacity(
                          opacity: _fall.value.clamp(0.0, 1.0),
                          child: Bloop(
                            mood: BloopMood.tumble,
                            size: 96,
                            skin: widget.profile.selectedSkin,
                            bodyColor: world.accents[0],
                            accentColor: world.ink,
                            tumbleProgress: 1 - _fall.value,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      result.reason.headline,
                      textAlign: TextAlign.center,
                      style: SinkType.rounded(
                        SinkType.title.copyWith(color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.reason.quip,
                      textAlign: TextAlign.center,
                      style: SinkType.rounded(
                        SinkType.label.copyWith(
                          color: world.muted,
                          letterSpacing: 0,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FadeTransition(
                      opacity: _card,
                      child: _ScoreCard(result: result, world: world),
                    ),
                    const SizedBox(height: 14),
                    FadeTransition(
                      opacity: _card,
                      child: ChunkyPill(
                        fill: world.accents[2].withValues(alpha: 0.18),
                        outline: world.accents[2],
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        child: Text(
                          _nearMiss,
                          textAlign: TextAlign.center,
                          style: SinkType.rounded(
                            SinkType.label.copyWith(
                              color: world.accents[2],
                              fontSize: 13,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _StatsList(result: result, world: world),
                    const SizedBox(height: 22),
                    ChunkyButton(
                      onTap: widget.onPlayAgain,
                      fill: world.accents[0],
                      semanticLabel: 'Play again',
                      child: SizedBox(
                        height: 64,
                        child: Center(
                          child: Text(
                            'PLAY AGAIN',
                            style: SinkType.rounded(
                              SinkType.button.copyWith(
                                color: world.onButton(0),
                                fontSize: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ChunkyButton(
                      onTap: widget.onHome,
                      fill: Colors.white.withValues(alpha: 0.12),
                      outline: Colors.white.withValues(alpha: 0.25),
                      child: SizedBox(
                        height: 52,
                        child: Center(
                          child: Text(
                            'BACK TO THE EDGE',
                            style: SinkType.rounded(
                              SinkType.label.copyWith(color: Colors.white, fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.result, required this.world});

  final RunResult result;
  final WorldPalette world;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        color: world.cardSurface,
        borderRadius: BorderRadius.circular(SinkShape.radius),
        border: Border.all(color: world.onCard.withValues(alpha: 0.2), width: 3),
        boxShadow: <BoxShadow>[
          BoxShadow(color: world.shadow, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: <Widget>[
          Text(
            result.daily ? 'DAILY DEPTH' : 'DEPTH REACHED',
            style: SinkType.rounded(
              SinkType.caption.copyWith(color: world.onCard.withValues(alpha: 0.55)),
            ),
          ),
          const SizedBox(height: 2),
          RollingNumber(
            value: result.depth,
            color: world.onCard,
            style: SinkType.display.copyWith(fontSize: 64),
          ),
          const SizedBox(height: 4),
          Text(
            'LEVEL ${Difficulty(result.depth).levelLabel}  ·  '
            '${Worlds.forIndex(result.worldIndex).name.toUpperCase()}',
            style: SinkType.rounded(
              SinkType.caption.copyWith(color: world.onCard.withValues(alpha: 0.6)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsList extends StatelessWidget {
  const _StatsList({required this.result, required this.world});

  final RunResult result;
  final WorldPalette world;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Puzzles cleared', '${result.correctAnswers}'),
      ('Best streak', '${result.bestStreak}'),
      ('Accuracy', '${result.accuracy}%'),
      if (result.powerUpsUsed > 0) ('Power-ups used', '${result.powerUpsUsed}'),
      if (result.elapsedSeconds > 0) ('Time', _formatDuration(result.elapsedSeconds)),
    ];

    final fastest = result.fastestKind;
    if (fastest != null) {
      rows.add((
        'Quickest type',
        '${fastest.kind.label} · ${fastest.averageSeconds.toStringAsFixed(1)}s',
      ));
    }

    return Column(
      children: <Widget>[
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(SinkShape.chipRadius),
              ),
              child: Row(
                children: <Widget>[
                  Text(
                    row.$1,
                    style: SinkType.rounded(
                      SinkType.label.copyWith(
                        color: world.muted,
                        letterSpacing: 0,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    row.$2,
                    style: SinkType.rounded(
                      SinkType.label.copyWith(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

String _formatDuration(double seconds) {
  final total = seconds.round();
  final minutes = total ~/ 60;
  final rest = total % 60;
  if (minutes == 0) return '${rest}s';
  return '${minutes}m ${rest.toString().padLeft(2, '0')}s';
}
