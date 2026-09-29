import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinkhole/core/difficulty.dart';
import 'package:sinkhole/core/game_random.dart';
import 'package:sinkhole/model/power_up.dart';
import 'package:sinkhole/model/puzzle.dart';
import 'package:sinkhole/data/player_profile.dart';
import 'package:sinkhole/data/save_service.dart';
import 'package:sinkhole/engine/run_controller.dart';
import 'package:sinkhole/puzzle/puzzle_factory.dart';
import 'package:sinkhole/puzzle/puzzle_fingerprint.dart';
import 'package:sinkhole/puzzle/sequence_generator.dart';
import 'package:sinkhole/puzzle/grid_generator.dart';
import 'package:sinkhole/puzzle/pattern_generator.dart';
import 'package:sinkhole/puzzle/make24_generator.dart';
import 'package:sinkhole/puzzle/memory_generator.dart';
import 'package:sinkhole/puzzle/odd_one_generator.dart';

/// Guards the two things that make a run feel endless: there is always something
/// new to show, and what is shown is suited to the player.
///
/// These are regression tests. The content space used to be small enough that
/// runs genuinely repeated, and a puzzle type had a hard ceiling of 108
/// arrangements, so both are asserted here rather than left to chance.
/// Lets the run move on. Comfortably past the feedback hold, because elapsing
/// by exactly the hold duration races the controller's own timer.
final _settle = RunController.feedbackHold + const Duration(milliseconds: 60);

/// Solves whatever is on screen and returns once the next puzzle is up.
///
/// Two different clocks are involved: the memory flash is driven by the game
/// clock in [RunController.tick], while the feedback hold is a real timer. A
/// memory puzzle is therefore silently unanswerable if you only elapse, and a
/// puzzle that was answered during its flash is silently skipped.
void _solve(RunController run, FakeAsync async) {
  var guard = 0;
  while (!run.acceptsAnswers && !run.isOver && guard++ < 600) {
    run.tick(1 / 60);
  }
  if (run.isOver) return;
  run.answer(run.solutionIndex);
  async.elapse(_settle);
}

/// The same, but deliberately wrong, so the adaptive read can be watched moving
/// against the grain.
void _solveWrong(RunController run, FakeAsync async) {
  var guard = 0;
  while (!run.acceptsAnswers && !run.isOver && guard++ < 600) {
    run.tick(1 / 60);
  }
  if (run.isOver) return;
  final wrong = (List<int>.generate(
    run.options.length,
    (i) => i,
  )).firstWhere((i) => i != run.solutionIndex);
  run.answer(wrong);
  async.elapse(_settle);
}

void main() {
  group('content space', () {
    /// Counts distinct puzzles a template can produce at a depth, stopping as
    /// soon as it has seen [cap]. Counting to a cap rather than always drawing
    /// a fixed number of samples is what keeps this affordable: make 24 solves
    /// a target for every candidate, so brute-forcing tens of thousands of
    /// puzzles dominated the whole test run.
    int distinctOf(PuzzleKind kind, Difficulty d,
        {int samples = 900, int cap = 1000}) {
      final seen = <String>{};
      for (var i = 0; i < samples; i++) {
        final rng = GameRandom(i * 2654435761 + d.depth);
        final puzzle = switch (kind) {
          PuzzleKind.sequence => const SequenceGenerator().generate(rng, d),
          PuzzleKind.pattern => const PatternGenerator().generate(rng, d),
          PuzzleKind.make24 => const Make24Generator().generate(rng, d),
          PuzzleKind.gridLogic => const GridGenerator().generate(rng, d),
          PuzzleKind.memory => const MemoryGenerator().generate(rng, d),
          PuzzleKind.oddOne => const OddOneGenerator().generate(rng, d),
        };
        seen.add(puzzleFingerprint(puzzle));
        if (seen.length >= cap) break;
      }
      return seen.length;
    }

    test('no template has a small pool at any depth', () {
      for (final kind in PuzzleKind.values) {
        for (final depth in <int>[1, 8, 16, 26, 40, 60, 90]) {
          // gridLogic is expected to be the tightest. On a 3x3 it is bounded by
          // construction, because there are only twelve Latin squares of order
          // three, so its floor follows the board. Everything else has to be
          // effectively unlimited.
          final floor = switch (kind) {
            // Bounded by construction: a 3x3 has twelve Latin squares, and an
            // odd-one-out is a base glyph plus one changed property.
            PuzzleKind.gridLogic => Difficulty(depth).gridSize == 3 ? 90 : 600,
            PuzzleKind.oddOne => 400,
            _ => 700,
          };
          expect(
            distinctOf(kind, Difficulty(depth), cap: floor + 1),
            greaterThan(floor),
            reason:
                '$kind only produced $floor-or-fewer puzzles '
                'at depth $depth',
          );
        }
      }
    });

    test('the grid template outgrows its old ceiling as the run deepens', () {
      // A 3x3 Latin square has exactly twelve possible layouts, so the shallow
      // pool is inherently small. The 4x4 board is what makes the deeper half
      // of a run interesting.
      final early = distinctOf(PuzzleKind.gridLogic, const Difficulty(8));
      final late = distinctOf(PuzzleKind.gridLogic, const Difficulty(60));
      expect(
        late,
        greaterThan(early * 3),
        reason: '4x4 boards should multiply the arrangements',
      );
      expect(const Difficulty(8).gridSize, 3);
      expect(const Difficulty(60).gridSize, 4);
      // The board size is what makes the deeper half of a run interesting.
      expect(
        const Difficulty(60).gridBlanks,
        greaterThan(const Difficulty(8).gridBlanks),
      );
    });

    test('consecutive puzzles of one type do not all look the same', () {
      // Distinct values are not enough on their own: a type could offer 400
      // variations that all have the same shape. These assert the *card*
      // changes, not just the numbers in it.
      for (final kind in <PuzzleKind>[
        PuzzleKind.pattern,
        PuzzleKind.gridLogic,
        PuzzleKind.memory,
      ]) {
        final bodies = <String>{};
        for (var i = 0; i < 400; i++) {
          bodies.add(
            puzzleBodyKey(switch (kind) {
              PuzzleKind.pattern => const PatternGenerator().generate(
                GameRandom(i * 7919),
                const Difficulty(20),
              ),
              PuzzleKind.gridLogic => const GridGenerator().generate(
                GameRandom(i * 7919),
                const Difficulty(20),
              ),
              PuzzleKind.memory => const MemoryGenerator().generate(
                GameRandom(i * 7919),
                const Difficulty(20),
              ),
              _ => throw ArgumentError(kind.name),
            }),
          );
        }
        // The card body includes the tokens, so this catches a type that varies
        // only its answer options.
        expect(
          bodies.length,
          greaterThan(40),
          reason: '$kind shows the same card over and over',
        );
      }
    });
  });

  group('a run never repeats itself', () {
    test('no puzzle comes round twice, deep into a run', () {
      for (final depth in <int>[60, 150, 400]) {
        var runsWithRepeat = 0;
        var repeats = 0;
        for (var seed = 0; seed < 40; seed++) {
          final rng = GameRandom(seed * 7919 + 1);
          final factory = PuzzleFactory();
          final seen = <String>{};
          PuzzleKind? last;
          for (var d = 1; d <= depth; d++) {
            final puzzle = factory.build(
              rng,
              d,
              lastKind: last,
              boss: d % 10 == 0,
              seen: seen,
            );
            if (!seen.add(puzzleFingerprint(puzzle))) repeats++;
            last = puzzle.kind;
          }
        }
        if (repeats > 0) runsWithRepeat++;
        expect(
          repeats,
          0,
          reason: 'repeats appeared in $runsWithRepeat runs at depth $depth',
        );
      }
    });

    test('the factory avoids a fingerprint it is told to avoid', () {
      final factory = PuzzleFactory();
      final rng = GameRandom(99);
      final target = factory.build(rng, 20, seen: const <String>{});
      final key = puzzleFingerprint(target);

      final next = factory.build(GameRandom(99), 20, seen: <String>{key});
      expect(puzzleFingerprint(next), isNot(key));
    });

    test('when a pool is genuinely spent, the run switches type instead', () {
      // Deliberately hand the factory a seen-set holding every fingerprint
      // available at this depth. It must still return a puzzle rather than
      // looping or throwing.
      final rng = GameRandom(7);
      final factory = PuzzleFactory();
      final all = <String>{};
      for (var i = 0; i < 1500; i++) {
        all.add(puzzleFingerprint(factory.build(GameRandom(i * 31), 12)));
      }
      final puzzle = factory.build(rng, 12, seen: all);
      expect(puzzle.options, isNotEmpty);
      expect(puzzle.solutionIndex, inInclusiveRange(0, puzzle.options.length - 1));
    });

    test('a run through the real controller shows only fresh puzzles', () {
      fakeAsync((async) {
        final run = RunController(
          seed: 20260314,
          daily: true,
          profile: Profile(MemoryStore()),
          now: DateTime(2026, 3, 14),
        )..start();

        final seen = <String>{};
        for (var i = 0; i < 250; i++) {
          if (run.isOver) break;
          // The fingerprint has to be taken while the puzzle is on screen:
          // after answering, the controller holds the same puzzle until the
          // feedback hold elapses, so checking afterwards would compare each
          // puzzle with itself.
          expect(
            seen.add(puzzleFingerprint(run.puzzle!)),
            isTrue,
            reason: 'depth ${run.depth} repeated an earlier puzzle',
          );
          _solve(run, async);
        }
        expect(
          seen.length,
          greaterThan(200),
          reason: 'the run should have shown a lot of distinct puzzles',
        );
        run.dispose();
      });
    });
  });

  group('content matches the player', () {
    test('the skill offset is bounded so the curve stays the spine', () {
      fakeAsync((async) {
        final run = RunController(seed: 1, daily: false, profile: Profile(MemoryStore()))
          ..start();

        // Cruise: answer instantly and correctly many times over. The feedback
        // hold is a real timer, so it has to elapse for the run to move on.
        for (var i = 0; i < 120; i++) {
          if (run.isOver) break;
          _solve(run, async);
          expect(run.skillOffset.abs(), lessThanOrEqualTo(Difficulty.maxSkillOffset));
        }
        expect(
          run.skillOffset,
          greaterThan(0),
          reason: 'a player cruising should be nudged upward',
        );
        // The average approaches its cap asymptotically, so it converges on the
        // cap rather than landing on it exactly.
        expect(
          run.skillOffset,
          closeTo(Difficulty.maxSkillOffset, 1e-6),
          reason: 'a long clean run should saturate the cap, not exceed it',
        );

        // Then fall. The read is a moving average on purpose, so it should start
        // coming back down immediately but not flip sign after one mistake.
        expect(run.isOver, isFalse);
        final cruising = run.skillOffset;
        for (var crack = 0; crack < 2 && !run.isOver; crack++) {
          _solveWrong(run, async);
        }
        expect(
          run.skillOffset,
          lessThan(cruising),
          reason: 'a player struggling should be eased back',
        );
        run.dispose();
      });
    });

    test('a sustained bad run drives the offset below the baseline', () {
      fakeAsync((async) {
        final run = RunController(seed: 11, daily: false, profile: Profile(MemoryStore()))
          ..start();
        // Miss every other puzzle so the run does not end on three cracks.
        var guard = 0;
        while (!run.isOver && guard++ < 30) {
          _solveWrong(run, async);
          if (run.isOver) break;
          _solve(run, async);
        }
        expect(
          run.skillOffset,
          lessThan(0),
          reason: 'a struggling player should be handed easier content',
        );
        run.dispose();
      });
    });

    test('a fresh run starts from the depth baseline', () {
      fakeAsync((async) {
        final profile = Profile(MemoryStore());
        final run = RunController(seed: 2, daily: false, profile: profile)..start();
        for (var i = 0; i < 20; i++) {
          if (run.isOver) break;
          _solve(run, async);
        }
        expect(run.skillOffset, isNot(0));

        run.abandon();
        run.dispose();

        final next = RunController(seed: 3, daily: false, profile: profile)..start();
        expect(
          next.skillOffset,
          0,
          reason: 'a new run should not inherit the last run momentum',
        );
        next.dispose();
      });
    });

    test('harder templates stay locked until they are meant to appear', () {
      final factory = PuzzleFactory();
      for (var seed = 0; seed < 40; seed++) {
        for (var depth = 1; depth <= 4; depth++) {
          expect(factory.pickKind(GameRandom(seed), depth), isNot(PuzzleKind.make24));
        }
        for (var depth = 1; depth <= 5; depth++) {
          expect(factory.pickKind(GameRandom(seed), depth), isNot(PuzzleKind.memory));
        }
        for (var depth = 1; depth <= 5; depth++) {
          expect(factory.pickKind(GameRandom(seed), depth), isNot(PuzzleKind.gridLogic));
        }
      }
    });
  });

  group('the grid board grows with depth', () {
    test('board size and hidden-cell count both scale', () {
      expect(const Difficulty(1).gridSize, 3);
      expect(const Difficulty(16).gridSize, 3);
      expect(const Difficulty(17).gridSize, 4);
      expect(const Difficulty(80).gridSize, 4);

      expect(const Difficulty(1).gridBlanks, 1);
      expect(const Difficulty(80).gridBlanks, 3);
    });

    test('a 4x4 board still has exactly one correct answer', () {
      for (var seed = 0; seed < 300; seed++) {
        final puzzle = const GridGenerator().generate(
          GameRandom(seed * 131),
          const Difficulty(60),
        );
        final body = puzzle.body as TokenGridBody;
        expect(body.cols, 4);
        expect(body.cells, hasLength(16));

        // Filling every gap with the answer must produce a valid Latin square,
        // and no other option may.
        final answer = puzzle.solution.text!;
        List<String> fill(String v) => <String>[
          for (final cell in body.cells) cell.isBlank ? v : cell.text!,
        ];

        bool valid(List<String> values) {
          for (var r = 0; r < 4; r++) {
            final row = <String>{for (var c = 0; c < 4; c++) values[r * 4 + c]};
            if (row.length != 4) return false;
          }
          for (var c = 0; c < 4; c++) {
            final col = <String>{for (var r = 0; r < 4; r++) values[r * 4 + c]};
            if (col.length != 4) return false;
          }
          return true;
        }

        expect(valid(fill(answer)), isTrue, reason: 'seed $seed answer wrong');
        for (var i = 0; i < puzzle.options.length; i++) {
          if (i == puzzle.solutionIndex) continue;
          expect(
            valid(fill(puzzle.options[i].text!)),
            isFalse,
            reason: 'seed $seed: ${puzzle.options[i].text} also works',
          );
        }
      }
    });
  });

  group('the pattern template varies its shape, not just its colours', () {
    test('the cycle length grows with depth', () {
      expect(const Difficulty(1).patternCycleLength, 2);
      expect(const Difficulty(20).patternCycleLength, 3);
      expect(const Difficulty(80).patternCycleLength, 4);
    });

    test('two cycles are always shown, so the period is visible', () {
      for (var depth = 1; depth <= 90; depth++) {
        for (var seed = 0; seed < 12; seed++) {
          final puzzle = const PatternGenerator().generate(
            GameRandom(seed * 331 + depth),
            Difficulty(depth),
          );
          final shown = (puzzle.body as TokenRowBody).tokens;
          final filled = shown.where((t) => !t.isBlank).toList();
          expect(shown.last.isBlank, isTrue);

          // Find the shortest period that explains the row, then require that it
          // is shown `patternCycles` times. Without the repeat there is nothing
          // for the player to recognise and no way to tell the answer from a
          // guess, and the cycle length itself is allowed to vary.
          int? period;
          for (var p = 2; p <= filled.length ~/ 2; p++) {
            var repeats = true;
            for (var i = p; i < filled.length; i++) {
              if (filled[i] != filled[i - p]) {
                repeats = false;
                break;
              }
            }
            if (repeats) {
              period = p;
              break;
            }
          }
          expect(
            period,
            isNotNull,
            reason: 'depth $depth showed a row that never repeats',
          );
          expect(
            filled.length,
            Difficulty.patternCycles * period!,
            reason:
                'depth $depth did not show the cycle '
                '${Difficulty.patternCycles} times',
          );
          expect(period, lessThanOrEqualTo(Difficulty(depth).patternCycleLength));
        }
      }
    });
  });

  group('run records still line up with the fresh content', () {
    test('a deep run produces a coherent result', () {
      fakeAsync((async) {
        final profile = Profile(MemoryStore());
        final run = RunController(seed: 4242, daily: false, profile: profile)..start();

        var guard = 0;
        while (!run.isOver && guard++ < 400) {
          _solve(run, async);
        }
        expect(run.isOver, isFalse, reason: 'a perfect player never falls');
        expect(run.depth, greaterThan(200));
        expect(run.puzzlesShown, greaterThan(200));
        run.dispose();
      });
    });
  });

  group('power-ups are still reachable during a long run', () {
    test('a long clean run banks a tray', () {
      fakeAsync((async) {
        final profile = Profile(MemoryStore());
        final run = RunController(seed: 555, daily: false, profile: profile)..start();
        var guard = 0;
        while (!run.isOver && guard++ < 400) {
          _solve(run, async);
        }
        expect(
          profile.tray,
          isNotEmpty,
          reason: 'a long clean run should have earned power-ups',
        );
        expect(PowerUp.values.length, 4);
        run.dispose();
      });
    });
  });
}
