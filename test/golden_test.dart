import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinkhole/audio/haptics.dart';
import 'package:sinkhole/audio/sound_engine.dart';
import 'package:sinkhole/core/difficulty.dart';
import 'package:sinkhole/core/game_random.dart';
import 'package:sinkhole/data/player_profile.dart';
import 'package:sinkhole/data/save_service.dart';
import 'package:sinkhole/main.dart';
import 'package:sinkhole/model/power_up.dart';
import 'package:sinkhole/model/run_result.dart';
import 'package:sinkhole/puzzle/memory_generator.dart';
import 'package:sinkhole/ui/screens/game_screen.dart';
import 'package:sinkhole/ui/screens/result_screen.dart';
import 'package:sinkhole/ui/theme/app_theme.dart';
import 'package:sinkhole/ui/theme/world_palette.dart';
import 'package:sinkhole/ui/widgets/puzzle_card.dart';

/// Renders the real screens at a phone size and writes them to disk.
///
/// This exists because a screenshot is the only way to actually see whether the
/// game is laid out correctly. Golden files are written with
/// `flutter test --update-goldens`, then read back and inspected.
///
/// Several screens animate forever by design, so every case pumps a fixed set
/// of frames from rest rather than settling, which keeps the output stable.
void main() {
  const size = Size(393, 852);
  const devicePixelRatio = 2.0;

  Future<void> phone(
    WidgetTester tester,
    Widget app, {
    Duration settle = const Duration(milliseconds: 16),
  }) async {
    tester.view.devicePixelRatio = devicePixelRatio;
    tester.view.physicalSize = size * devicePixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
    // One frame to build and lay out, then a fixed advance. A short advance
    // captures the first painted frame; a long one lets entrance animations
    // finish so the golden shows the settled design.
    await tester.pump();
    await tester.pump(settle);
  }

  testWidgets('home', (tester) async {
    final profile = Profile(MemoryStore());
    profile.recordRun(
      RunResult(
        depth: 27,
        bestStreak: 11,
        reason: FallReason.timeout,
        records: const <SolveRecord>[],
        daily: false,
        worldIndex: 1,
        elapsedSeconds: 96,
        powerUpsUsed: 2,
      ),
      now: DateTime(2026, 3, 14),
    );
    await phone(
      tester,
      App(profile: profile, sound: SoundEngine(), haptics: Haptics(enabled: false)),
    );
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/home.png'));
  });

  testWidgets('game at depth 1', (tester) async {
    await phone(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Worlds.forIndex(0)),
        home: GameScreen(
          profile: Profile(MemoryStore()),
          sound: SoundEngine(),
          haptics: Haptics(enabled: false),
          seed: 20260314,
        ),
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/game_depth1.png'),
    );
  });

  testWidgets('game with power-ups and a deep world', (tester) async {
    final profile = Profile(MemoryStore());
    for (final p in PowerUp.values) {
      profile.addPowerUp(p, 2);
    }
    profile.recordRun(
      RunResult(
        depth: 30,
        bestStreak: 8,
        reason: FallReason.cracks,
        records: const <SolveRecord>[],
        daily: false,
        worldIndex: 2,
        elapsedSeconds: 120,
        powerUpsUsed: 1,
      ),
      now: DateTime(2026, 3, 14),
    );
    await phone(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Worlds.forIndex(2)),
        home: GameScreen(
          profile: profile,
          sound: SoundEngine(),
          haptics: Haptics(enabled: false),
          seed: 20260314,
        ),
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/game_crystal.png'),
    );
  });

  testWidgets('memory card mid-flash', (tester) async {
    // A memory puzzle rendered inside a real card, so the flash layout can be
    // checked without driving a whole run to that depth.
    final world = Worlds.forIndex(0);
    final puzzle = MemoryGenerator().generate(GameRandom(3), const Difficulty(6));
    await phone(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(world),
        home: WorldScope(
          world: world,
          child: Scaffold(
            backgroundColor: world.skyBottom,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: PuzzleCard(
                  puzzle: puzzle,
                  world: world,
                  boss: false,
                  onAnswerableChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/card_memory.png'),
    );
  });

  testWidgets('result', (tester) async {
    final profile = Profile(MemoryStore());
    profile.recordRun(
      RunResult(
        depth: 9,
        bestStreak: 6,
        reason: FallReason.timeout,
        records: const <SolveRecord>[],
        daily: false,
        worldIndex: 0,
        elapsedSeconds: 64,
        powerUpsUsed: 1,
      ),
      now: DateTime(2026, 3, 14),
    );
    final world = Worlds.forIndex(0);
    await phone(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(world),
        home: ResultScreen(
          result: RunResult(
            depth: 12,
            bestStreak: 7,
            reason: FallReason.timeout,
            records: const <SolveRecord>[],
            daily: false,
            worldIndex: 0,
            elapsedSeconds: 88,
            powerUpsUsed: 1,
          ),
          profile: profile,
          onPlayAgain: () {},
          onHome: () {},
        ),
      ),
      // Long enough for the tumble-in and the card landing to complete.
      settle: const Duration(milliseconds: 900),
    );
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/result.png'));
  });
}
