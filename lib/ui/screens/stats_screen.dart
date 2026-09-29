import 'package:flutter/material.dart';

import '../../data/player_profile.dart';
import '../../model/power_up.dart';
import '../../model/puzzle.dart';
import '../theme/app_theme.dart';
import '../theme/world_palette.dart';
import '../widgets/bloop.dart';
import '../widgets/chunky.dart';
import 'home_screen.dart';

/// Lifetime stats, the strongest and weakest puzzle types, the power-up tray,
/// and the Bloop skin wardrobe.
class StatsScreen extends StatefulWidget {
  const StatsScreen({required this.profile, super.key});

  final Profile profile;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late String _skin = widget.profile.selectedSkin;
  bool _sound = true;
  bool _haptics = true;

  @override
  void initState() {
    super.initState();
    _sound = widget.profile.soundEnabled;
    _haptics = widget.profile.hapticsEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final world = Worlds.forIndex(profile.deepestWorld);

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
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        ChunkyButton(
                          onTap: () => Navigator.of(context).pop(),
                          padding: EdgeInsets.zero,
                          radius: SinkShape.pillRadius,
                          fill: Colors.white.withValues(alpha: 0.1),
                          outline: Colors.white.withValues(alpha: 0.22),
                          outlineWidth: 2,
                          elevation: 0,
                          semanticLabel: 'Back',
                          child: const SizedBox.square(
                            dimension: 40,
                            child: Icon(
                              Icons.arrow_back_rounded,
                              size: 20,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'STATS',
                          style: SinkType.rounded(
                            SinkType.label.copyWith(color: Colors.white, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _Headline(world: world, profile: profile),
                    const SizedBox(height: 14),
                    _Panel(
                      world: world,
                      title: 'BY PUZZLE TYPE',
                      child: Column(
                        children: <Widget>[
                          for (final stat in profile.kindStats)
                            _KindRow(
                              stat: stat,
                              world: world,
                              best: stat.kind == profile.bestPuzzleType,
                              fastest: stat.kind == profile.fastestPuzzleType,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Panel(
                      world: world,
                      title: 'WORLDS',
                      child: WorldProgressStrip(profile: profile),
                    ),
                    const SizedBox(height: 12),
                    _Panel(
                      world: world,
                      title: 'BLOOP WARDROBE',
                      child: Column(
                        children: <Widget>[
                          for (final entry in Profile.skinCatalogue.entries)
                            _SkinRow(
                              id: entry.key,
                              name: entry.value.name,
                              emoji: entry.value.emoji,
                              depth: entry.value.depth,
                              unlocked: profile.unlockedSkins.contains(entry.key),
                              selected: _skin == entry.key,
                              world: world,
                              onTap: () {
                                setState(() => _skin = entry.key);
                                widget.profile.selectSkin(entry.key);
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Panel(
                      world: world,
                      title: 'POWER-UPS',
                      child: Column(
                        children: <Widget>[
                          for (final power in PowerUp.values)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: <Widget>[
                                  Icon(power.icon, size: 20, color: world.accents[2]),
                                  const SizedBox(width: 10),
                                  Text(
                                    power.label,
                                    style: SinkType.rounded(
                                      SinkType.label.copyWith(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      power.hintText,
                                      style: SinkType.rounded(
                                        SinkType.caption.copyWith(
                                          color: world.muted,
                                          fontSize: 11,
                                          letterSpacing: 0,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '×${profile.powerUpCount(power)}',
                                    style: SinkType.rounded(
                                      SinkType.label.copyWith(
                                        color: profile.powerUpCount(power) > 0
                                            ? world.accents[2]
                                            : Colors.white38,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Text(
                            'Earned every 5 solves and by clearing bosses.',
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
                    const SizedBox(height: 12),
                    _Panel(
                      world: world,
                      title: 'SETTINGS',
                      child: Column(
                        children: <Widget>[
                          _Toggle(
                            label: 'Sound',
                            value: _sound,
                            world: world,
                            onChanged: (value) {
                              setState(() => _sound = value);
                              widget.profile.setSound(value);
                            },
                          ),
                          _Toggle(
                            label: 'Haptics',
                            value: _haptics,
                            world: world,
                            onChanged: (value) {
                              setState(() => _haptics = value);
                              widget.profile.setHaptics(value);
                            },
                          ),
                          const SizedBox(height: 6),
                          ChunkyButton(
                            onTap: () {
                              widget.profile.reset();
                              setState(() => _skin = Profile.defaultSkin);
                            },
                            fill: Colors.white.withValues(alpha: 0.08),
                            outline: Colors.white.withValues(alpha: 0.2),
                            child: SizedBox(
                              height: 44,
                              child: Center(
                                child: Text(
                                  'RESET PROGRESS',
                                  style: SinkType.rounded(
                                    SinkType.caption.copyWith(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
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
            ),
          ],
        ),
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.world, required this.profile});

  final WorldPalette world;
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final tiles = <(String, String)>[
      ('BEST DEPTH', '${profile.bestDepth}'),
      ('RUNS', '${profile.totalRuns}'),
      ('TOTAL DEPTH', '${profile.totalDepth}'),
      ('PUZZLES', '${profile.totalSolved}'),
      ('BEST STREAK', '${profile.bestStreak}'),
      ('ACCURACY', '${profile.accuracy}%'),
      if (profile.totalSolved > 0)
        ('AVG SOLVE', '${profile.averageSolveSeconds.toStringAsFixed(1)}s'),
      ('DAILY STREAK', '${profile.dailyStreak}'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final tile in tiles)
          Container(
            width: 100,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(SinkShape.chipRadius),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 2),
            ),
            child: Column(
              children: <Widget>[
                Text(
                  tile.$2,
                  style: SinkType.rounded(
                    SinkType.title.copyWith(color: world.accents[2], fontSize: 20),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tile.$1,
                  textAlign: TextAlign.center,
                  style: SinkType.rounded(
                    SinkType.caption.copyWith(color: world.muted, fontSize: 9),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _KindRow extends StatelessWidget {
  const _KindRow({
    required this.stat,
    required this.world,
    required this.best,
    required this.fastest,
  });

  final KindStatSummary stat;
  final WorldPalette world;

  /// Most solved overall.
  final bool best;

  /// Quickest average.
  final bool fastest;

  @override
  Widget build(BuildContext context) {
    final maxSolved = 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              stat.kind.label,
              style: SinkType.rounded(
                SinkType.caption.copyWith(
                  color: Colors.white,
                  fontSize: 11,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (stat.solved / maxSolved).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(
                  best ? world.accents[2] : world.accents[1],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 62,
            child: Text(
              stat.solved == 0 ? '—' : '${stat.averageSeconds.toStringAsFixed(1)}s',
              textAlign: TextAlign.right,
              style: SinkType.rounded(
                SinkType.caption.copyWith(
                  color: fastest ? world.accents[2] : Colors.white54,
                  fontSize: 11,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 34,
            child: Text(
              '${stat.solved}',
              textAlign: TextAlign.right,
              style: SinkType.rounded(
                SinkType.caption.copyWith(color: Colors.white38, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkinRow extends StatelessWidget {
  const _SkinRow({
    required this.id,
    required this.name,
    required this.emoji,
    required this.depth,
    required this.unlocked,
    required this.selected,
    required this.world,
    required this.onTap,
  });

  final String id;
  final String name;
  final String emoji;
  final int depth;
  final bool unlocked;
  final bool selected;
  final WorldPalette world;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ChunkyButton(
        onTap: unlocked ? onTap : null,
        enabled: unlocked,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        radius: SinkShape.chipRadius,
        fill: selected
            ? world.accents[0].withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.06),
        outline: selected ? world.accents[0] : Colors.transparent,
        outlineWidth: 2,
        elevation: 0,
        child: Row(
          children: <Widget>[
            Bloop(
              mood: BloopMood.idle,
              size: 34,
              skin: id,
              bodyColor: unlocked ? world.accents[0] : Colors.white24,
              accentColor: world.ink,
            ),
            const SizedBox(width: 10),
            Text(
              '$emoji  $name',
              style: SinkType.rounded(
                SinkType.label.copyWith(
                  color: unlocked ? Colors.white : Colors.white38,
                  fontSize: 13,
                  letterSpacing: 0,
                ),
              ),
            ),
            const Spacer(),
            if (unlocked)
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 18,
                color: selected ? world.accents[0] : Colors.white24,
              )
            else
              Text(
                'DEPTH $depth',
                style: SinkType.rounded(
                  SinkType.caption.copyWith(color: Colors.white38, fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.world,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final WorldPalette world;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: SinkType.rounded(
              SinkType.label.copyWith(color: Colors.white, fontSize: 13),
            ),
          ),
          const Spacer(),
          Switch.adaptive(
            value: value,
            activeThumbColor: world.accents[0],
            onChanged: onChanged,
          ),
        ],
      ),
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
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
