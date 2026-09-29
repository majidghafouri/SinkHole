import 'package:flutter/material.dart';

import '../../audio/haptics.dart';
import '../../audio/sound_engine.dart';
import '../../core/difficulty.dart';
import '../../core/game_random.dart';
import '../../data/player_profile.dart';
import '../theme/app_theme.dart';
import '../theme/world_palette.dart';
import '../widgets/arena.dart';
import '../widgets/bloop.dart';
import '../widgets/chunky.dart';
import '../widgets/run_status_bar.dart';
import 'game_screen.dart';
import 'stats_screen.dart';

/// The edge of the hole. One button, the best depth, and the daily.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.profile,
    required this.sound,
    required this.haptics,
    super.key,
  });

  final Profile profile;
  final SoundEngine sound;
  final Haptics haptics;

  void _play(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          profile: profile,
          sound: sound,
          haptics: haptics,
          ghost: profile.bestGhost,
        ),
      ),
    );
  }

  void _daily(BuildContext context) {
    Navigator.of(context).pushNamed('/daily');
  }

  @override
  Widget build(BuildContext context) {
    final world = Worlds.forIndex(Difficulty.worldIndexFor(profile.bestDepth));
    final nextWorld = Worlds.nextUnlockDepth(profile.bestDepth);

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
            CrumblingFloor(
              world: world,
              progress: Difficulty(profile.bestDepth.clamp(1, 60)).ramp,
              shake: 0,
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  // The column is at least a full viewport tall so the Spacers
                  // still centre Bloop, and scrolls on short screens or with
                  // large text instead of overflowing.
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                        child: Column(
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                ChunkyPill(
                                  fill: Colors.white.withValues(alpha: 0.1),
                                  child: Text(
                                    'SINKHOLE',
                                    style: SinkType.rounded(
                                      SinkType.label.copyWith(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                _IconPill(
                                  icon: Icons.insights_rounded,
                                  label: 'Stats',
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => StatsScreen(profile: profile),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Bloop(
                              mood: BloopMood.idle,
                              size: 148,
                              skin: profile.selectedSkin,
                              bodyColor: world.accents[0],
                              accentColor: world.ink,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'DON\'T LOOK DOWN',
                              style: SinkType.rounded(
                                SinkType.title.copyWith(
                                  color: Colors.white,
                                  fontSize: 26,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Solve a puzzle before the floor runs out.\n'
                              'Three cracks and Bloop goes over the edge.',
                              textAlign: TextAlign.center,
                              style: SinkType.rounded(
                                SinkType.label.copyWith(
                                  color: world.muted,
                                  letterSpacing: 0,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            const Spacer(),
                            _BestDepthPanel(world: world, profile: profile),
                            const SizedBox(height: 14),
                            ChunkyButton(
                              onTap: () => _play(context),
                              fill: world.accents[0],
                              semanticLabel: 'Start a run',
                              child: SizedBox(
                                height: 72,
                                child: Center(
                                  child: Text(
                                    'PLAY',
                                    style: SinkType.rounded(
                                      SinkType.button.copyWith(
                                        color: world.onButton(0),
                                        fontSize: 28,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _DailyRow(
                              world: world,
                              profile: profile,
                              onTap: () => _daily(context),
                            ),
                            if (nextWorld != null) ...<Widget>[
                              const SizedBox(height: 12),
                              Text(
                                '${Worlds.forIndex(Difficulty.worldIndexFor(nextWorld)).name} '
                                'unlocks at depth $nextWorld',
                                textAlign: TextAlign.center,
                                style: SinkType.rounded(
                                  SinkType.caption.copyWith(
                                    color: world.muted.withValues(alpha: 0.8),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BestDepthPanel extends StatelessWidget {
  const _BestDepthPanel({required this.world, required this.profile});

  final WorldPalette world;
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final stats = <(String, String)>[
      ('RUNS', '${profile.totalRuns}'),
      ('BEST STREAK', '${profile.bestStreak}'),
      ('ACCURACY', '${profile.accuracy}%'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(SinkShape.radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 2),
      ),
      child: Row(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'BEST DEPTH',
                style: SinkType.rounded(SinkType.caption.copyWith(color: world.muted)),
              ),
              RollingNumber(
                value: profile.bestDepth,
                color: world.accents[2],
                style: SinkType.display.copyWith(fontSize: 38),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final stat in stats)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          stat.$1,
                          style: SinkType.rounded(
                            SinkType.caption.copyWith(color: world.muted),
                          ),
                        ),
                        Text(
                          stat.$2,
                          style: SinkType.rounded(
                            SinkType.caption.copyWith(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyRow extends StatelessWidget {
  const _DailyRow({required this.world, required this.profile, required this.onTap});

  final WorldPalette world;
  final Profile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final best = profile.dailyBest(now);
    final done = best > 0;
    final chest = profile.chestAvailable(now);

    return ChunkyButton(
      onTap: onTap,
      fill: Colors.white.withValues(alpha: 0.1),
      outline: Colors.white.withValues(alpha: 0.22),
      semanticLabel: 'Daily challenge',
      child: SizedBox(
        height: 56,
        child: Row(
          children: <Widget>[
            const SizedBox(width: 4),
            Icon(
              chest ? Icons.card_giftcard_rounded : Icons.calendar_today_rounded,
              color: chest ? world.accents[2] : Colors.white70,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              chest ? 'CHEST READY' : 'DAILY CHALLENGE',
              style: SinkType.rounded(
                SinkType.label.copyWith(color: Colors.white, fontSize: 14),
              ),
            ),
            const Spacer(),
            if (done)
              ChunkyPill(
                fill: world.accents[1].withValues(alpha: 0.25),
                child: Text(
                  'BEST $best',
                  style: SinkType.rounded(
                    SinkType.caption.copyWith(color: world.accents[1], fontSize: 11),
                  ),
                ),
              )
            else
              Text(
                'TRY IT',
                style: SinkType.rounded(SinkType.caption.copyWith(color: world.muted)),
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _IconPill extends StatelessWidget {
  const _IconPill({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChunkyButton(
      onTap: onTap,
      padding: EdgeInsets.zero,
      radius: SinkShape.pillRadius,
      fill: Colors.white.withValues(alpha: 0.1),
      outline: Colors.white.withValues(alpha: 0.22),
      outlineWidth: 2,
      elevation: 0,
      semanticLabel: label,
      child: SizedBox.square(
        dimension: 40,
        child: Icon(icon, size: 20, color: Colors.white70),
      ),
    );
  }
}

/// A compact world-progress strip, reused by the daily and stats screens.
class WorldProgressStrip extends StatelessWidget {
  const WorldProgressStrip({required this.profile, super.key});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final world = WorldScope.of(context);
    return Column(
      children: <Widget>[
        for (var i = 0; i < Worlds.all.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _WorldRow(
              palette: Worlds.forIndex(i),
              best: profile.bestDepth,
              depth: Worlds.unlockDepths[i],
              isCurrent: i == Difficulty.worldIndexFor(profile.bestDepth),
              accent: world.accents[0],
            ),
          ),
      ],
    );
  }
}

class _WorldRow extends StatelessWidget {
  const _WorldRow({
    required this.palette,
    required this.best,
    required this.depth,
    required this.isCurrent,
    required this.accent,
  });

  final WorldPalette palette;
  final int best;
  final int depth;
  final bool isCurrent;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final unlocked = best >= depth;
    final next = Worlds.unlockDepths.firstWhere((d) => d > best, orElse: () => depth);
    final span = (next - depth).clamp(1, 999);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: unlocked
            ? palette.skyBottom.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(SinkShape.chipRadius),
        border: Border.all(color: isCurrent ? accent : Colors.transparent, width: 2),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: unlocked ? palette.floor : Colors.white24,
            ),
            child: Icon(
              unlocked ? Icons.check_rounded : Icons.lock_rounded,
              size: 15,
              color: unlocked ? palette.onButton(0) : Colors.white38,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  palette.name.toUpperCase(),
                  style: SinkType.rounded(
                    SinkType.label.copyWith(
                      color: unlocked ? Colors.white : Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  unlocked ? 'Unlocked' : 'Depth $depth',
                  style: SinkType.rounded(
                    SinkType.caption.copyWith(
                      color: Colors.white38,
                      fontSize: 10,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 54,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: unlocked ? 1 : ((best - depth) / span).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(palette.floor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The daily key for the header of the daily screen.
String todayKey() => dailyKeyFor(DateTime.now());
