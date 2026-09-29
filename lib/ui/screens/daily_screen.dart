import 'package:flutter/material.dart';

import '../../audio/haptics.dart';
import '../../audio/sound_engine.dart';
import '../../core/game_random.dart';
import '../../data/player_profile.dart';
import '../theme/app_theme.dart';
import '../theme/world_palette.dart';
import '../widgets/bloop.dart';
import '../widgets/chunky.dart';
import 'game_screen.dart';

/// The daily seeded challenge.
///
/// Everyone gets the same puzzles on the same day because the run seed is
/// derived from the date, so depths are directly comparable. The leaderboard is
/// the player's own attempts on that seed, and the best of them becomes the
/// ghost for the next attempt.
class DailyScreen extends StatelessWidget {
  const DailyScreen({
    required this.profile,
    required this.sound,
    required this.haptics,
    super.key,
  });

  final Profile profile;
  final SoundEngine sound;
  final Haptics haptics;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final world = Worlds.forIndex(0);
    final best = profile.dailyBest(now);
    final entries = profile.dailyEntries(now);
    final chest = profile.chestAvailable(now);
    final ghost = profile.dailyGhost;

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
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        _BackPill(onTap: () => Navigator.of(context).pop()),
                        const Spacer(),
                        ChunkyPill(
                          fill: world.accents[1].withValues(alpha: 0.2),
                          outline: world.accents[1],
                          child: Text(
                            'SEED ${dailySeedFor(now) % 100000}',
                            style: SinkType.rounded(
                              SinkType.caption.copyWith(
                                color: world.accents[1],
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Center(
                      child: Bloop(
                        mood: chest ? BloopMood.cheer : BloopMood.idle,
                        size: 116,
                        skin: profile.selectedSkin,
                        bodyColor: world.accents[1],
                        accentColor: world.ink,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'TODAY\'S HOLE',
                      textAlign: TextAlign.center,
                      style: SinkType.rounded(
                        SinkType.title.copyWith(color: Colors.white, fontSize: 26),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Same puzzles for everyone. Be deepest.',
                      textAlign: TextAlign.center,
                      style: SinkType.rounded(
                        SinkType.label.copyWith(
                          color: world.muted,
                          letterSpacing: 0,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _Panel(
                      world: world,
                      title: 'YOUR BEST',
                      child: Row(
                        children: <Widget>[
                          Text(
                            '$best',
                            style: SinkType.rounded(
                              SinkType.display.copyWith(
                                fontSize: 46,
                                color: world.accents[2],
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  best == 0 ? 'Not tried yet' : 'depth reached',
                                  style: SinkType.rounded(
                                    SinkType.caption.copyWith(color: world.muted),
                                  ),
                                ),
                                Text(
                                  '${entries.length} '
                                  'attempt${entries.length == 1 ? '' : 's'} today',
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
                        ],
                      ),
                    ),
                    if (entries.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      _Panel(
                        world: world,
                        title: 'LEADERBOARD',
                        child: Column(
                          children: <Widget>[
                            for (var i = 0; i < entries.length && i < 5; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: <Widget>[
                                    SizedBox(
                                      width: 26,
                                      child: Text(
                                        '#${i + 1}',
                                        style: SinkType.rounded(
                                          SinkType.caption.copyWith(
                                            color: i == 0
                                                ? world.accents[2]
                                                : world.muted,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'Depth ${entries[i].depth}',
                                      style: SinkType.rounded(
                                        SinkType.label.copyWith(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    if (entries[i].wasNewBest)
                                      ChunkyPill(
                                        fill: world.accents[2].withValues(alpha: 0.2),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        child: Text(
                                          'BEST',
                                          style: SinkType.rounded(
                                            SinkType.caption.copyWith(
                                              color: world.accents[2],
                                              fontSize: 9,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _StreakRow(profile: profile, world: world),
                    if (chest) ...<Widget>[
                      const SizedBox(height: 12),
                      ChunkyButton(
                        onTap: () {
                          profile.claimChest(now);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: world.accents[2],
                              content: Text(
                                'Hint power-up added to your tray.',
                                style: SinkType.rounded(
                                  SinkType.label.copyWith(color: world.onButton(2)),
                                ),
                              ),
                            ),
                          );
                        },
                        fill: world.accents[2],
                        child: SizedBox(
                          height: 56,
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(
                                  Icons.card_giftcard_rounded,
                                  color: world.onButton(2),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'OPEN TODAY\'S CHEST',
                                  style: SinkType.rounded(
                                    SinkType.label.copyWith(
                                      color: world.onButton(2),
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    ChunkyButton(
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => GameScreen(
                              profile: profile,
                              sound: sound,
                              haptics: haptics,
                              daily: true,
                              ghost: ghost,
                            ),
                          ),
                        );
                      },
                      fill: world.accents[1],
                      semanticLabel: 'Start the daily challenge',
                      child: SizedBox(
                        height: 70,
                        child: Center(
                          child: Text(
                            best == 0 ? 'START THE DAILY' : 'BEAT $best',
                            style: SinkType.rounded(
                              SinkType.button.copyWith(
                                color: world.onButton(1),
                                fontSize: 24,
                              ),
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

/// A seven-day streak calendar with a chest per day.
class _StreakRow extends StatelessWidget {
  const _StreakRow({required this.profile, required this.world});

  final Profile profile;
  final WorldPalette world;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = startOfDay(now);

    return _Panel(
      world: world,
      title: 'STREAK · ${profile.dailyStreak} DAY${profile.dailyStreak == 1 ? '' : 'S'}',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          for (var i = 6; i >= 0; i--)
            _StreakDay(
              day: today.subtract(Duration(days: i)),
              world: world,
              claimed: profile.claimedChests.contains(
                dailyKeyFor(today.subtract(Duration(days: i))),
              ),
              best: profile.dailyBest(today.subtract(Duration(days: i))),
              isToday: i == 0,
            ),
        ],
      ),
    );
  }
}

class _StreakDay extends StatelessWidget {
  const _StreakDay({
    required this.day,
    required this.world,
    required this.claimed,
    required this.best,
    required this.isToday,
  });

  final DateTime day;
  final WorldPalette world;
  final bool claimed;
  final int best;
  final bool isToday;

  static const List<String> _labels = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final done = best > 0;
    final color = claimed
        ? world.accents[2]
        : done
        ? world.accents[1]
        : Colors.white12;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          _labels[day.weekday - 1],
          style: SinkType.rounded(
            SinkType.caption.copyWith(
              color: isToday ? Colors.white : Colors.white38,
              fontSize: 10,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: color,
            border: isToday ? Border.all(color: Colors.white, width: 2) : null,
          ),
          child: Icon(
            claimed
                ? Icons.card_giftcard_rounded
                : done
                ? Icons.check_rounded
                : Icons.more_horiz_rounded,
            size: 15,
            color: done || claimed ? world.onButton(2) : Colors.white24,
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.world, required this.title, required this.child});

  final WorldPalette world;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(SinkShape.radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: SinkType.rounded(SinkType.caption.copyWith(color: world.muted)),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _BackPill extends StatelessWidget {
  const _BackPill({required this.onTap});
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
      semanticLabel: 'Back',
      child: const SizedBox.square(
        dimension: 40,
        child: Icon(Icons.arrow_back_rounded, size: 20, color: Colors.white70),
      ),
    );
  }
}
