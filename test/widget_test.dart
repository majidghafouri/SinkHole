import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinkhole/audio/haptics.dart';
import 'package:sinkhole/audio/sound_engine.dart';
import 'package:sinkhole/core/difficulty.dart';
import 'package:sinkhole/core/game_random.dart';
import 'package:sinkhole/data/player_profile.dart';
import 'package:sinkhole/data/save_service.dart';
import 'package:sinkhole/engine/run_controller.dart';
import 'package:sinkhole/main.dart';
import 'package:sinkhole/model/power_up.dart';
import 'package:sinkhole/model/puzzle.dart';
import 'package:sinkhole/model/run_result.dart';
import 'package:sinkhole/model/token.dart';
import 'package:sinkhole/puzzle/grid_generator.dart';
import 'package:sinkhole/puzzle/memory_generator.dart';
import 'package:sinkhole/puzzle/pattern_generator.dart';
import 'package:sinkhole/ui/screens/game_screen.dart';
import 'package:sinkhole/ui/theme/app_theme.dart';
import 'package:sinkhole/ui/theme/world_palette.dart';
import 'package:sinkhole/ui/widgets/answer_grid.dart';
import 'package:sinkhole/ui/widgets/bloop.dart';
import 'package:sinkhole/ui/widgets/chunky.dart';
import 'package:sinkhole/ui/widgets/floor_timer_bar.dart';
import 'package:sinkhole/ui/widgets/power_up_tray.dart';
import 'package:sinkhole/ui/widgets/puzzle_card.dart';
import 'package:sinkhole/ui/widgets/run_status_bar.dart';
import 'package:sinkhole/ui/widgets/token_view.dart';

/// A profile backed by memory, so widget tests never touch a platform channel.
Profile testProfile() => Profile(MemoryStore());

/// A sound engine that was never initialised. Every play call is a no-op, which
/// is exactly what is wanted here: no platform channel, no real audio.
SoundEngine silentSound() => SoundEngine();

/// Wraps a widget in the app's theme and palette.
Widget wrap(Widget child, {WorldPalette? world}) {
  final palette = world ?? Worlds.forIndex(0);
  return MaterialApp(
    theme: buildTheme(palette),
    home: WorldScope(world: palette, child: child),
  );
}

/// Winds the run down so the tree can be disposed cleanly.
///
/// Two things would otherwise fail teardown: screens that animate forever by
/// design, and the run controller's real-time feedback hold, which is a plain
/// `Future.delayed` that outlives the widget that started it.
Future<void> teardown(WidgetTester tester) async {
  // Let the feedback hold and any reveal timer fire while the tree is alive.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

RunResult fakeResult({required int depth, bool daily = false}) => RunResult(
  depth: depth,
  bestStreak: 4,
  reason: FallReason.timeout,
  records: const <SolveRecord>[],
  daily: daily,
  worldIndex: Difficulty.worldIndexFor(depth),
  elapsedSeconds: 40,
  powerUpsUsed: 0,
);

void main() {
  group('token rendering', () {
    testWidgets('numbers, glyphs, blanks and empty cells all render', (tester) async {
      final world = Worlds.forIndex(0);
      await tester.pumpWidget(
        wrap(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TokenView(token: const Token.value('24'), world: world, size: 30),
              TokenView(
                token: const Token.glyph(ShapeKind.star, color: 2),
                world: world,
                size: 30,
              ),
              TokenView(token: const Token.blank(), world: world, size: 30),
              TokenView(token: const Token.empty(), world: world, size: 30),
            ],
          ),
        ),
      );

      expect(find.text('24'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      expect(find.byIcon(Icons.help_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rotation and scale reach the glyph', (tester) async {
      final world = Worlds.forIndex(0);
      await tester.pumpWidget(
        wrap(
          TokenView(
            token: const Token.glyph(ShapeKind.triangle, scale: 0.5, rotation: 0.6),
            world: world,
            size: 40,
          ),
        ),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      // 40 * 0.5, which proves the scale factor reached the render.
      expect(icon.size, 20);
      expect(tester.takeException(), isNull);
    });
  });

  group('puzzle card', () {
    testWidgets('shows the prompt and every visible number for a sequence', (
      tester,
    ) async {
      final world = Worlds.forIndex(0);
      await tester.pumpWidget(
        wrap(
          PuzzleCard(
            puzzle: Puzzle(
              kind: PuzzleKind.sequence,
              depth: 1,
              body: const TokenRowBody(<Token>[
                Token.value('2'),
                Token.value('4'),
                Token.value('6'),
                Token.value('8'),
              ]),
              options: const <Token>[Token.value('10')],
              solutionIndex: 0,
            ),
            world: world,
            boss: false,
            onAnswerableChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(PuzzleKind.sequence.prompt), findsOneWidget);
      for (final value in <String>['2', '4', '6', '8']) {
        expect(find.text(value), findsOneWidget, reason: 'missing $value');
      }
    });

    testWidgets('a memory card is unanswerable during the flash, then ready', (
      tester,
    ) async {
      final world = Worlds.forIndex(0);
      final puzzle = MemoryGenerator().generate(GameRandom(3), const Difficulty(6));
      final states = <bool>[];

      await tester.pumpWidget(
        wrap(
          PuzzleCard(
            puzzle: puzzle,
            world: world,
            boss: false,
            onAnswerableChanged: states.add,
          ),
        ),
      );
      expect(states, isNotEmpty);
      expect(states.last, isFalse, reason: 'not answerable during the flash');

      final flash = (puzzle.body as TokenGridBody).flashMs!;
      await tester.pump(Duration(milliseconds: flash + 60));
      expect(states.last, isTrue, reason: 'answerable once the grid is hidden');
    });

    testWidgets('the grid puzzle draws all nine cells with a gap', (tester) async {
      final world = Worlds.forIndex(0);
      final puzzle = GridGenerator().generate(GameRandom(11), const Difficulty(10));
      await tester.pumpWidget(
        wrap(
          PuzzleCard(
            puzzle: puzzle,
            world: world,
            boss: false,
            onAnswerableChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(PuzzleKind.gridLogic.prompt), findsOneWidget);
      expect(find.text('?'), findsWidgets, reason: 'at least one gap');
    });

    testWidgets('a boss card gets a golden frame', (tester) async {
      final world = Worlds.forIndex(0);
      await tester.pumpWidget(
        wrap(
          PuzzleCard(
            puzzle: PatternGenerator().generate(GameRandom(2), const Difficulty(12)),
            world: world,
            boss: true,
            onAnswerableChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.workspace_premium_rounded), findsOneWidget);
    });

    testWidgets('a long pattern row wraps instead of overflowing', (tester) async {
      final world = Worlds.forIndex(0);
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 320,
            child: PuzzleCard(
              puzzle: PatternGenerator().generate(GameRandom(5), const Difficulty(40)),
              world: world,
              boss: false,
              onAnswerableChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('answer grid', () {
    testWidgets('renders four buttons and reports the tapped index', (tester) async {
      final world = Worlds.forIndex(0);
      var tapped = -1;
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 380,
            child: AnswerGrid(
              options: const <Token>[
                Token.value('1'),
                Token.value('2'),
                Token.value('3'),
                Token.value('4'),
              ],
              world: world,
              selected: -1,
              solutionIndex: 2,
              enabled: true,
              onTap: (index) => tapped = index,
            ),
          ),
        ),
      );

      expect(find.text('1'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);

      await tester.tap(find.text('4'));
      await tester.pump();
      expect(tapped, 3);
    });

    testWidgets('a disabled grid ignores taps', (tester) async {
      final world = Worlds.forIndex(0);
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 380,
            child: AnswerGrid(
              options: const <Token>[
                Token.value('1'),
                Token.value('2'),
                Token.value('3'),
                Token.value('4'),
              ],
              world: world,
              selected: -1,
              solutionIndex: 2,
              enabled: false,
              onTap: (_) => taps++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('1'));
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('locking marks the answer and the wrong tap', (tester) async {
      final world = Worlds.forIndex(0);
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 380,
            child: AnswerGrid(
              options: const <Token>[
                Token.value('1'),
                Token.value('2'),
                Token.value('3'),
                Token.value('4'),
              ],
              world: world,
              selected: 0,
              solutionIndex: 2,
              enabled: false,
              locked: true,
              onTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    });

    testWidgets('a three-option grid stays usable', (tester) async {
      final world = Worlds.forIndex(0);
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 380,
            child: AnswerGrid(
              options: const <Token>[
                Token.value('1'),
                Token.value('2'),
                Token.value('3'),
              ],
              world: world,
              selected: -1,
              solutionIndex: 0,
              enabled: true,
              onTap: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('answer buttons meet the 64dp minimum tap target', (tester) async {
      final world = Worlds.forIndex(0);
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 320,
            child: AnswerGrid(
              options: const <Token>[
                Token.value('1'),
                Token.value('2'),
                Token.value('3'),
                Token.value('4'),
              ],
              world: world,
              selected: -1,
              solutionIndex: 0,
              enabled: true,
              onTap: (_) {},
            ),
          ),
        ),
      );

      // The grid lays its buttons out in explicit SizedBoxes, so their heights
      // can be read straight off the tree.
      final heights = tester
          .widgetList<SizedBox>(
            find.descendant(of: find.byType(AnswerGrid), matching: find.byType(SizedBox)),
          )
          .map((s) => s.height)
          .whereType<double>()
          .toList();
      expect(heights, hasLength(4));
      for (final height in heights) {
        expect(height, greaterThanOrEqualTo(64), reason: 'height $height');
      }
    });
  });

  group('floor timer bar', () {
    testWidgets('renders at every fill level', (tester) async {
      final world = Worlds.forIndex(0);
      for (final fraction in <double>[0, 0.1, 0.3, 0.6, 1]) {
        await tester.pumpWidget(
          wrap(
            FloorTimerBar(
              world: world,
              fraction: fraction,
              budgetFraction: 0.7,
              allowanceFraction: fraction,
              frozen: false,
              freezeFraction: 0,
              panic: false,
              pulse: 0,
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: 'fraction $fraction');
      }
    });

    testWidgets('the panic and frozen states render', (tester) async {
      final world = Worlds.forIndex(0);
      await tester.pumpWidget(
        wrap(
          FloorTimerBar(
            world: world,
            fraction: 0.08,
            budgetFraction: 0.05,
            allowanceFraction: 0.08,
            frozen: false,
            freezeFraction: 0,
            panic: true,
            pulse: 0.5,
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        wrap(
          FloorTimerBar(
            world: world,
            fraction: 0.6,
            budgetFraction: 0.5,
            allowanceFraction: 0.9,
            frozen: true,
            freezeFraction: 0.4,
            panic: false,
            pulse: 0.2,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('status bar', () {
    testWidgets('shows depth, the streak flame and three crack pips', (tester) async {
      final world = Worlds.forIndex(0);
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 380,
            child: RunStatusBar(
              world: world,
              depth: 27,
              streak: 6,
              cracks: 2,
              maxCracks: 3,
              shielded: false,
              boss: false,
              bossStep: 0,
              bossSteps: 2,
              daily: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DEPTH'), findsOneWidget);
      expect(find.text('27'), findsOneWidget);
      expect(find.byIcon(Icons.heart_broken_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    });

    testWidgets('a daily run labels the readout DAILY', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 380,
            child: RunStatusBar(
              world: Worlds.forIndex(0),
              depth: 4,
              streak: 0,
              cracks: 0,
              maxCracks: 3,
              shielded: true,
              boss: false,
              bossStep: 0,
              bossSteps: 2,
              daily: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('DAILY'), findsOneWidget);
      expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
    });

    testWidgets('a boss round swaps the flame for progress pips', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 380,
            child: RunStatusBar(
              world: Worlds.forIndex(0),
              depth: 10,
              streak: 9,
              cracks: 0,
              maxCracks: 3,
              shielded: false,
              boss: true,
              bossStep: 1,
              bossSteps: 2,
              daily: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('BOSS'), findsOneWidget);
    });
  });

  group('power-up tray', () {
    testWidgets('three slots render and a filled one reports its power-up', (
      tester,
    ) async {
      final world = Worlds.forIndex(0);
      PowerUp? used;
      await tester.pumpWidget(
        wrap(
          PowerUpTray(
            slots: <TraySlot>[TraySlot(PowerUp.freeze, 2)],
            world: world,
            enabled: true,
            onUse: (p) => used = p,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(PowerUp.freeze.icon), findsOneWidget);
      // The count badge, and only it, reads "2".
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byIcon(PowerUp.freeze.icon));
      await tester.pump();
      expect(used, PowerUp.freeze);
    });

    testWidgets('an empty tray shows three dashed placeholders', (tester) async {
      await tester.pumpWidget(
        wrap(
          PowerUpTray(
            slots: const <TraySlot>[],
            world: Worlds.forIndex(0),
            enabled: true,
            onUse: (_) {},
          ),
        ),
      );
      expect(find.byIcon(Icons.add_rounded), findsNWidgets(3));
    });
  });

  group('bloop', () {
    testWidgets('paints every mood', (tester) async {
      for (final mood in BloopMood.values) {
        await tester.pumpWidget(wrap(Bloop(mood: mood, size: 100)));
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: 'mood $mood');
      }
    });

    testWidgets('paints every skin', (tester) async {
      for (final skin in <String>['classic', 'wizard', 'astronaut', 'pirate']) {
        await tester.pumpWidget(wrap(Bloop(mood: BloopMood.idle, size: 100, skin: skin)));
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: 'skin $skin');
      }
    });
  });

  group('app', () {
    testWidgets('boots into the home screen', (tester) async {
      final profile = testProfile();
      await tester.pumpWidget(
        App(profile: profile, sound: silentSound(), haptics: Haptics(enabled: false)),
      );
      await tester.pump();

      expect(find.text('PLAY'), findsOneWidget);
      expect(find.text('SINKHOLE'), findsOneWidget);
      expect(find.byType(Bloop), findsOneWidget);
    });

    testWidgets('shows the recorded best depth', (tester) async {
      final profile = testProfile();
      profile.recordRun(fakeResult(depth: 14), now: DateTime(2026, 3, 14));
      await tester.pumpWidget(
        App(profile: profile, sound: silentSound(), haptics: Haptics(enabled: false)),
      );
      await tester.pump();

      expect(find.text('14'), findsOneWidget);
      expect(find.text('DAILY CHALLENGE'), findsOneWidget);
    });

    testWidgets('a completed daily run offers its chest', (tester) async {
      final profile = testProfile();
      profile.recordRun(fakeResult(depth: 9, daily: true), now: DateTime.now());
      await tester.pumpWidget(
        App(profile: profile, sound: silentSound(), haptics: Haptics(enabled: false)),
      );
      await tester.pump();

      expect(find.text('CHEST READY'), findsOneWidget);
    });

    testWidgets('tapping PLAY opens a run with a live timer', (tester) async {
      final profile = testProfile();
      await tester.pumpWidget(
        App(profile: profile, sound: silentSound(), haptics: Haptics(enabled: false)),
      );
      await tester.pump();

      await tester.tap(find.text('PLAY'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(GameScreen), findsOneWidget);
      expect(find.byType(FloorTimerBar), findsOneWidget);
      expect(find.text('DEPTH'), findsOneWidget);
      expect(find.text('1'), findsWidgets);

      await teardown(tester);
    });

    testWidgets('answering locks the buttons and shows the outcome', (tester) async {
      final profile = testProfile();
      await tester.pumpWidget(
        App(profile: profile, sound: silentSound(), haptics: Haptics(enabled: false)),
      );
      await tester.pump();
      await tester.tap(find.text('PLAY'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap whichever answer button comes first: at depth 1 the puzzle is a
      // sequence, so every option is live and the outcome marker tells us
      // whether it happened to be the right one.
      final answers = find.descendant(
        of: find.byType(AnswerGrid),
        matching: find.byType(ChunkyButton),
      );
      expect(answers, findsNWidgets(4));
      await tester.tap(answers.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The right answer is always revealed, and a wrong pick is marked as
      // well, so there is at least one tick and, on a miss, a cross too.
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      // The buttons are now inert, so a second tap changes nothing.
      await tester.tap(answers.at(1));
      await tester.pump();
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('the quit dialog pauses and then resumes the run', (tester) async {
      final profile = testProfile();
      await tester.pumpWidget(
        App(profile: profile, sound: silentSound(), haptics: Haptics(enabled: false)),
      );
      await tester.pump();
      await tester.tap(find.text('PLAY'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('CLIMB BACK OUT?'), findsOneWidget);

      await tester.tap(find.text('STAY'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('CLIMB BACK OUT?'), findsNothing);
      expect(find.byType(GameScreen), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('the stats screen opens and shows puzzle type stats', (tester) async {
      final profile = testProfile();
      await tester.pumpWidget(
        App(profile: profile, sound: silentSound(), haptics: Haptics(enabled: false)),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.insights_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('STATS'), findsOneWidget);
      expect(find.text('BY PUZZLE TYPE'), findsOneWidget);
      expect(find.text('BLOOP WARDROBE'), findsOneWidget);

      await teardown(tester);
    });
  });
}
