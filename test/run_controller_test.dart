import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinkhole/core/difficulty.dart';
import 'package:sinkhole/data/player_profile.dart' show Profile;
import 'package:sinkhole/data/save_service.dart';
import 'package:sinkhole/engine/run_controller.dart';
import 'package:sinkhole/model/power_up.dart';
import 'package:sinkhole/model/puzzle.dart';
import 'package:sinkhole/model/run_result.dart';
import 'package:sinkhole/puzzle/puzzle_fingerprint.dart';

/// Collects everything the controller emits. Stream delivery is asynchronous,
/// so assertions always run after a pump.
class _Recorder {
  final List<RunEffect> all = <RunEffect>[];
  StreamSubscription<RunEffect>? _sub;

  void attach(RunController run) {
    _sub = run.effects.listen(all.add);
  }

  List<T> of<T extends RunEffect>() => all.whereType<T>().toList();

  Future<void> dispose() => _sub?.cancel() ?? Future<void>.value();
}

final Duration _afterFeedback =
    RunController.feedbackHold + const Duration(milliseconds: 50);
final Duration _afterFall = RunController.fallDuration + const Duration(milliseconds: 50);

RunController makeRun({
  Profile? profile,
  int seed = 4242,
  bool daily = false,
  DateTime? now,
}) => RunController(
  seed: seed,
  daily: daily,
  profile: profile,
  now: now ?? DateTime(2026, 3, 14),
);

Profile profileWith(Map<PowerUp, int> counts) {
  final profile = PlayerProfileFactory.inMemory();
  for (final entry in counts.entries) {
    profile.addPowerUp(entry.key, entry.value);
  }
  return profile;
}

/// Answers correctly and steps past the feedback hold.
///
/// A memory puzzle cannot be answered while it is revealing, so the clock is
/// pumped until the question is live. Without that, a solve would be silently
/// dropped and the run would stall.
void solveAndAdvance(FakeAsync async, RunController run, {int times = 1}) {
  for (var i = 0; i < times; i++) {
    if (run.isOver) return;
    while (!run.acceptsAnswers && !run.isOver) {
      run.tick(1 / 60);
    }
    if (run.isOver) return;
    run.answer(run.solutionIndex);
    async.elapse(_afterFeedback);
  }
}

/// Delivers any pending one-shot effects so they can be asserted on.
void pump(FakeAsync async) => async.elapse(Duration.zero);

int wrongOption(RunController run) => List<int>.generate(
  run.options.length,
  (i) => i,
).firstWhere((i) => i != run.solutionIndex);

void main() {
  group('opening', () {
    test('starts at depth 1 with a full timer, three cracks and no streak', () {
      fakeAsync((async) {
        final run = makeRun()..start();
        expect(run.depth, 1);
        expect(run.cracks, 0);
        expect(run.streak, 0);
        expect(run.puzzle, isNotNull);
        expect(run.options, isNotEmpty);
        expect(run.solutionIndex, inInclusiveRange(0, run.options.length - 1));
        expect(run.timeLeft, closeTo(run.budget, 0.001));
        expect(run.timeFraction, greaterThan(0.5));
        expect(run.isBossRound, isFalse);
        expect(run.acceptsAnswers, isTrue);
        expect(run.isPanic, isFalse);
      });
    });

    test('the first puzzle is the trivially easy scripted one', () {
      fakeAsync((async) {
        final run = makeRun()..start();
        expect(run.puzzle!.kind, PuzzleKind.sequence);
        final terms = (run.puzzle!.body as TokenRowBody).tokens;
        expect(terms, hasLength(4), reason: 'depth 1 is the tutorial beat');
      });
    });

    test('the reward scales with speed, streak and boss, and streak is capped', () {
      double reward(double fraction, int streak, {bool boss = false}) =>
          RunController.computeReward(fraction, streak, boss);

      expect(reward(0.1, 0), lessThan(reward(0.9, 0)));
      expect(reward(0.5, 5), greaterThan(reward(0.5, 0)));
      expect(reward(0.5, 0, boss: true), greaterThan(reward(0.5, 0)));
      expect(reward(0.5, 40), closeTo(reward(0.5, 12), 0.0001));
    });
  });

  group('answering', () {
    test('a correct answer banks time, grows the streak and advances', () {
      fakeAsync((async) {
        final run = makeRun()..start();
        final rec = _Recorder()..attach(run);
        final before = run.timeLeft;

        run.answer(run.solutionIndex);
        expect(run.streak, 1);
        expect(run.timeLeft, greaterThan(before));
        expect(run.phase, RunPhase.feedback);
        expect(rec.of<CorrectEffect>(), isEmpty, reason: 'not delivered yet');

        async.elapse(_afterFeedback);
        expect(run.depth, 2);
        final correct = rec.of<CorrectEffect>().single;
        expect(correct.reward, greaterThan(0));
        expect(correct.streak, 1);
        expect(correct.boss, isFalse);
      });
    });

    test('a wrong answer cracks the floor, costs time and breaks the streak', () {
      fakeAsync((async) {
        final run = makeRun()..start();
        solveAndAdvance(async, run);
        expect(run.depth, 2);

        final before = run.timeLeft;
        run.answer(wrongOption(run));
        expect(run.cracks, 1);
        expect(run.streak, 0);
        expect(
          run.timeLeft,
          lessThan(before - 1.0),
          reason: 'a wrong answer costs time on top of the crack',
        );
      });
    });

    test('inputs are ignored while a memory card is revealing its flash', () {
      fakeAsync((async) {
        final run = makeRun(seed: 9)..start();
        var guard = 0;
        while (!run.puzzle!.hasFlash && !run.isOver && guard++ < 60) {
          solveAndAdvance(async, run);
        }
        expect(run.puzzle!.hasFlash, isTrue);

        expect(run.phase, RunPhase.revealing);
        expect(run.acceptsAnswers, isFalse);

        final depth = run.depth;
        final streak = run.streak;
        final cracks = run.cracks;
        run.answer(run.solutionIndex);
        expect(run.depth, depth, reason: 'a reveal-phase tap must be ignored');
        expect(run.streak, streak);
        expect(run.cracks, cracks);
      });
    });

    test('the floor timer holds still during the flash, then starts running', () {
      fakeAsync((async) {
        final run = makeRun(seed: 9)..start();
        var guard = 0;
        while (!run.puzzle!.hasFlash && !run.isOver && guard++ < 60) {
          solveAndAdvance(async, run);
        }
        final before = run.timeLeft;
        final flashSeconds = (run.puzzle!.body as TokenGridBody).flashMs! / 1000.0;

        run.tick(flashSeconds * 0.9);
        expect(run.timeLeft, closeTo(before, 0.001), reason: 'the flash is free');
        expect(run.phase, RunPhase.revealing);

        run.tick(0.2);
        expect(run.phase, RunPhase.answering);

        run.tick(0.5);
        expect(run.timeLeft, lessThan(before), reason: 'then it drains');
      });
    });

    test('the panic zone engages in the last seconds and clears on a solve', () {
      fakeAsync((async) {
        final run = makeRun()..start();
        final rec = _Recorder()..attach(run);

        while (run.timeLeft > RunController.panicSeconds) {
          run.tick(0.1);
        }
        expect(run.isPanic, isTrue);
        pump(async);
        expect(rec.of<PanicEffect>().last.active, isTrue);

        solveAndAdvance(async, run);
        expect(run.isPanic, isFalse);
      });
    });
  });

  group('the floor timer', () {
    test('running out ends the run and reports the depth', () {
      fakeAsync((async) {
        final run = makeRun()..start();
        final rec = _Recorder()..attach(run);
        for (var i = 0; i < 2000 && !run.isOver; i++) {
          run.tick(0.1);
        }
        expect(run.isOver, isTrue);
        expect(run.fallReason, FallReason.timeout);
        expect(run.phase, RunPhase.falling);

        pump(async);
        final fall = rec.of<FallEffect>().single;
        expect(fall.reason, FallReason.timeout);
        expect(fall.result.depth, 1);
        expect(fall.result.records, isEmpty);
      });
    });

    test('three cracks end the run even with plenty of time left', () {
      fakeAsync((async) {
        final run = makeRun()..start();
        for (var crack = 0; crack < RunController.maxCracks; crack++) {
          expect(run.timeLeft, greaterThan(2.0));
          run.answer(wrongOption(run));
          if (run.isOver) break;
          async.elapse(_afterFeedback);
        }
        expect(run.isOver, isTrue);
        expect(run.fallReason, FallReason.cracks);
        expect(run.cracks, RunController.maxCracks);
      });
    });

    test('fast solves build a buffer that carries into the next puzzle', () {
      fakeAsync((async) {
        final run = makeRun()..start();
        solveAndAdvance(async, run);
        expect(run.bufferSeconds, greaterThan(0.5));

        final carried = run.bufferSeconds;
        final nextBudget = run.budget;
        expect(run.timeLeft, closeTo(nextBudget + carried, 0.001));
      });
    });

    test('the buffer is capped so a good run cannot snowball', () {
      fakeAsync((async) {
        final run = makeRun()..start();
        solveAndAdvance(async, run, times: 6);
        expect(run.bufferSeconds, lessThanOrEqualTo(RunController.maxBuffer));
        expect(run.timeLeft, lessThanOrEqualTo(run.ceiling));
      });
    });

    test('the base allowance shrinks each level and never below the floor', () {
      expect(Difficulty(1).baseSeconds, 12.0);
      expect(Difficulty(6).baseSeconds, lessThan(Difficulty(1).baseSeconds));
      expect(Difficulty(46).baseSeconds, greaterThanOrEqualTo(5.0));
      expect(Difficulty(100).baseSeconds, 5.0);
      expect(Difficulty(500).baseSeconds, 5.0);
      expect(Difficulty(1).level, 0);
      expect(Difficulty(5).level, 0);
      expect(Difficulty(6).level, 1);
    });
  });

  group('boss rounds', () {
    test('a boss takes two steps but only one depth', () {
      fakeAsync((async) {
        final run = makeRun()..start();
        final rec = _Recorder()..attach(run);

        solveAndAdvance(async, run, times: 9);
        expect(run.depth, 10);
        expect(run.isBossRound, isTrue);
        expect(run.bossStep, 1);
        expect(run.bossStepCount, 2);
        final firstPuzzle = run.puzzle;

        // Step one.
        run.answer(run.solutionIndex);
        async.elapse(_afterFeedback);
        expect(rec.of<BossStepEffect>().single.step, 1);
        expect(
          rec.of<BossStepEffect>().single.cleared,
          isFalse,
          reason: 'step 1 of 2 is not the clear',
        );
        expect(run.depth, 10, reason: 'the round does not advance the depth');
        expect(run.isBossRound, isTrue);
        expect(run.bossStep, 2);
        expect(run.puzzle, isNot(firstPuzzle), reason: 'step two is a different puzzle');

        // Step two finishes the round and only then moves on.
        run.answer(run.solutionIndex);
        async.elapse(_afterFeedback);
        expect(rec.of<BossStepEffect>().last.cleared, isTrue);
        expect(rec.of<BossStepEffect>().last.step, 2);
        expect(run.depth, 11);
        expect(run.isBossRound, isFalse);
        expect(run.bossStep, 0);
      });
    });

    test('both boss steps show different puzzles', () {
      fakeAsync((async) {
        final run = makeRun()..start();
        solveAndAdvance(async, run, times: 9);
        expect(run.isBossRound, isTrue);
        final step1 = puzzleFingerprint(run.puzzle!);
        run.answer(run.solutionIndex);
        async.elapse(_afterFeedback);
        expect(run.bossStep, 2);
        expect(puzzleFingerprint(run.puzzle!), isNot(step1));
      });
    });

    test('failing a boss step ends the round with a crack, not a death', () {
      fakeAsync((async) {
        final run = makeRun()..start();
        final rec = _Recorder()..attach(run);
        solveAndAdvance(async, run, times: 9);
        expect(run.isBossRound, isTrue);

        run.answer(wrongOption(run));
        expect(run.cracks, 1);
        pump(async);
        expect(rec.of<BossStepEffect>().single.cleared, isFalse);
        async.elapse(_afterFeedback);
        expect(run.depth, 11);
        expect(run.isOver, isFalse);
      });
    });

    test('boss rounds draw from the slower templates', () {
      fakeAsync((async) {
        final run = makeRun()..start();
        final kinds = <PuzzleKind>{};
        var guard = 0;
        while (!run.isOver && guard++ < 60) {
          if (run.isBossRound) kinds.add(run.puzzle!.kind);
          solveAndAdvance(async, run);
        }
        expect(kinds, isNotEmpty);
        expect(
          kinds.any(
            (k) =>
                k == PuzzleKind.make24 ||
                k == PuzzleKind.memory ||
                k == PuzzleKind.gridLogic,
          ),
          isTrue,
        );
      });
    });

    test('clearing a boss pays a power-up', () {
      fakeAsync((async) {
        final profile = PlayerProfileFactory.inMemory();
        final run = makeRun(profile: profile)..start();
        final rec = _Recorder()..attach(run);
        solveAndAdvance(async, run, times: 9);
        final before = profile.tray.length;
        solveAndAdvance(async, run);
        pump(async);
        expect(rec.of<PowerUpEarnedEffect>(), isNotEmpty);
        expect(profile.tray.length, greaterThanOrEqualTo(before));
      });
    });
  });

  group('power-ups', () {
    test('freeze holds the timer and then releases it', () {
      fakeAsync((async) {
        final profile = profileWith({PowerUp.freeze: 1});
        final run = makeRun(profile: profile)..start();
        expect(profile.powerUpCount(PowerUp.freeze), 1);

        expect(run.use(PowerUp.freeze), isTrue);
        expect(profile.powerUpCount(PowerUp.freeze), 0);
        expect(run.isFrozen, isTrue);

        final before = run.timeLeft;
        for (var i = 0; i < 40; i++) {
          run.tick(0.1);
        }
        expect(run.timeLeft, closeTo(before, 0.001));

        for (var i = 0; i < 80; i++) {
          run.tick(0.1);
        }
        expect(run.isFrozen, isFalse);
        run.tick(0.1);
        expect(run.timeLeft, lessThan(before), reason: 'it drains again');
      });
    });

    test('skip swaps in a new puzzle without cracking or losing the streak', () {
      fakeAsync((async) {
        final profile = profileWith({PowerUp.skip: 1});
        final run = makeRun(profile: profile)..start();
        final first = run.puzzle;

        expect(run.use(PowerUp.skip), isTrue);
        expect(run.cracks, 0);
        expect(run.puzzle, isNot(first));
        expect(run.solutionIndex, inInclusiveRange(0, run.options.length - 1));
        expect(run.solution, isNotNull);
        expect(run.timeLeft, greaterThan(0.5));
      });
    });

    test('hint removes exactly one wrong option and keeps the answer', () {
      fakeAsync((async) {
        final profile = profileWith({PowerUp.hint: 1});
        final run = makeRun(seed: 77, profile: profile)..start();
        final answer = run.solution;
        final before = run.options.length;
        expect(before, greaterThan(2));

        expect(run.use(PowerUp.hint), isTrue);
        expect(run.options, hasLength(before - 1));
        expect(run.solution, answer, reason: 'the answer must survive the trim');
        expect(run.hintUsed, isTrue);
      });
    });

    test('hint replays the flash on a memory puzzle instead of trimming', () {
      fakeAsync((async) {
        final profile = profileWith({PowerUp.hint: 1});
        final run = makeRun(seed: 9, profile: profile)..start();
        var guard = 0;
        while (!run.puzzle!.hasFlash && !run.isOver && guard++ < 60) {
          solveAndAdvance(async, run);
        }
        final before = run.options.length;

        expect(run.use(PowerUp.hint), isTrue);
        expect(run.options, hasLength(before), reason: 'nothing was removed');
        expect(run.hintReplays, 1);
      });
    });

    test('a shield absorbs a mistake entirely', () {
      fakeAsync((async) {
        final profile = profileWith({PowerUp.shield: 1});
        final run = makeRun(seed: 5, profile: profile)..start();
        expect(run.use(PowerUp.shield), isTrue);
        expect(run.shieldActive, isTrue);

        final before = run.timeLeft;
        final rec = _Recorder()..attach(run);
        run.answer(wrongOption(run));
        pump(async);

        expect(rec.of<WrongEffect>().single.shielded, isTrue);
        expect(run.cracks, 0, reason: 'the shield ate the crack');
        expect(run.shieldActive, isFalse);
        expect(
          run.timeLeft,
          greaterThan(before - 0.5),
          reason: 'the shield ate the penalty too',
        );
        expect(run.isOver, isFalse);
      });
    });

    test('a power-up cannot be spent when none is held', () {
      fakeAsync((async) {
        final run = makeRun()..start();
        expect(run.canUse(PowerUp.freeze), isFalse);
        expect(run.use(PowerUp.freeze), isFalse);
      });
    });

    test('a power-up is earned every fifth solve', () {
      fakeAsync((async) {
        final profile = PlayerProfileFactory.inMemory();
        final run = makeRun(profile: profile)..start();
        final rec = _Recorder()..attach(run);
        solveAndAdvance(async, run, times: 6);
        pump(async);
        expect(rec.of<PowerUpEarnedEffect>(), isNotEmpty);
        expect(profile.tray, isNotEmpty);
      });
    });
  });

  group('level transitions', () {
    test('a new level fires on the first depth of every band of five', () {
      fakeAsync((async) {
        final run = makeRun()..start();
        final rec = _Recorder()..attach(run);
        solveAndAdvance(async, run, times: 11);
        pump(async);

        final levels = rec.of<LevelUpEffect>();
        expect(levels.map((e) => e.depth).toList(), containsAll(<int>[6, 11]));
        expect(levels.first.level, 1);
        expect(
          levels.map((e) => e.depth),
          isNot(contains(1)),
          reason: 'depth 1 opens level 1, not a transition',
        );
      });
    });

    test('worlds change at the depths the palette table specifies', () {
      expect(Difficulty.worldIndexFor(1), 0);
      expect(Difficulty.worldIndexFor(10), 0);
      expect(Difficulty.worldIndexFor(11), 1);
      expect(Difficulty.worldIndexFor(25), 1);
      expect(Difficulty.worldIndexFor(26), 2);
      expect(Difficulty.worldIndexFor(50), 2);
      expect(Difficulty.worldIndexFor(51), 3);
      expect(Difficulty.worldIndexFor(999), 3);
    });
  });

  group('result and profile', () {
    test('a finished run is recorded with its stats', () {
      fakeAsync((async) {
        final profile = PlayerProfileFactory.inMemory();
        final run = makeRun(profile: profile)..start();
        solveAndAdvance(async, run, times: 8);
        final streak = run.bestStreak;

        var guard = 0;
        while (!run.isOver && guard++ < 6) {
          run.answer(wrongOption(run));
          if (run.isOver) break;
          async.elapse(_afterFeedback);
        }

        expect(run.isOver, isTrue);
        expect(profile.totalRuns, 1);
        expect(profile.totalSolved, 8);
        expect(profile.bestStreak, streak);
        expect(profile.totalDepth, run.depth);
        expect(profile.bestDepth, run.depth);
        expect(profile.accuracy, inInclusiveRange(0, 100));
      });
    });

    test('a daily run is written to the daily board', () {
      fakeAsync((async) {
        final profile = PlayerProfileFactory.inMemory();
        final run = makeRun(profile: profile, daily: true)..start();
        solveAndAdvance(async, run, times: 4);
        run.abandon();

        expect(run.isOver, isTrue);
        expect(profile.dailyBest(DateTime(2026, 3, 14)), run.depth);
        expect(profile.dailyCompleted(DateTime(2026, 3, 14)), isTrue);
        expect(profile.dailyEntries(DateTime(2026, 3, 14)), isNotEmpty);
      });
    });

    test('a second daily run only sets a new best when it beats the first', () {
      fakeAsync((async) {
        final profile = PlayerProfileFactory.inMemory();
        final now = DateTime(2026, 3, 14);

        final first = makeRun(profile: profile, daily: true, seed: 1)..start();
        solveAndAdvance(async, first, times: 6);
        final deep = first.depth;
        first.abandon();
        expect(profile.dailyBest(now), deep);

        // A run that ends sooner must not overwrite the record.
        final second = makeRun(profile: profile, daily: true, seed: 2)..start();
        solveAndAdvance(async, second, times: 2);
        second.abandon();
        expect(profile.dailyBest(now), deep);
      });
    });

    test('a free run does not touch the daily board', () {
      fakeAsync((async) {
        final profile = PlayerProfileFactory.inMemory();
        makeRun(profile: profile)
          ..start()
          ..abandon();
        expect(profile.dailyBest(DateTime(2026, 3, 14)), 0);
      });
    });

    test('a chest is offered after a daily run and only once', () {
      fakeAsync((async) {
        final profile = PlayerProfileFactory.inMemory();
        final now = DateTime(2026, 3, 14);
        makeRun(profile: profile, daily: true)
          ..start()
          ..abandon();

        expect(profile.chestAvailable(now), isTrue);
        profile.claimChest(now);
        expect(profile.chestAvailable(now), isFalse);
        expect(profile.powerUpCount(PowerUp.hint), 1);
      });
    });
  });

  group('lifecycle', () {
    test('pausing stops the clock and resuming restarts it', () {
      fakeAsync((async) {
        final run = makeRun()..start();
        run.setPaused(true);
        final before = run.timeLeft;
        for (var i = 0; i < 20; i++) {
          run.tick(0.1);
        }
        expect(run.timeLeft, closeTo(before, 0.001));

        run.setPaused(false);
        run.tick(0.1);
        expect(run.timeLeft, lessThan(before));
      });
    });

    test('taps are ignored once the run is over', () {
      fakeAsync((async) {
        final run = makeRun()..start();
        run.abandon();
        final depth = run.depth;
        run.answer(0);
        expect(run.depth, depth);
      });
    });

    test('the controller reports finished so the screen can navigate', () {
      fakeAsync((async) {
        final run = makeRun()..start();
        run.abandon();
        expect(run.phase, RunPhase.falling);
        async.elapse(_afterFall);
        expect(run.phase, RunPhase.finished);
      });
    });

    test('a perfect player reaches the late worlds without breaking', () {
      fakeAsync((async) {
        final run = makeRun(seed: 8888)..start();
        solveAndAdvance(async, run, times: 110);
        expect(run.isOver, isFalse, reason: 'a perfect player never falls');
        expect(run.depth, greaterThanOrEqualTo(95));
        expect(run.bestStreak, greaterThanOrEqualTo(95));
        expect(run.cracks, 0);
        expect(run.worldIndex, 3, reason: 'Neon Abyss starts at depth 51');
        expect(run.timeLeft.isNaN, isFalse);
        expect(run.timeFraction.isNaN, isFalse);
        expect(run.bufferSeconds.isNaN, isFalse);
      });
    });

    test('a careless player falls quickly and the result is coherent', () {
      fakeAsync((async) {
        final run = makeRun(seed: 1234)..start();
        var guard = 0;
        while (!run.isOver && guard++ < 500) {
          while (!run.acceptsAnswers && !run.isOver) {
            run.tick(1 / 60);
          }
          if (run.isOver) break;
          run.answer((run.solutionIndex + 1) % run.options.length);
          async.elapse(_afterFeedback);
        }
        expect(run.isOver, isTrue);
        final rec = _Recorder()..attach(run);
        run.abandon();
        pump(async);
        expect(rec.of<FallEffect>(), isEmpty, reason: 'already over');
      });
    });

    test('the puzzle stream is deterministic for a given seed', () {
      List<String> play(int seed) {
        final result = <String>[];
        fakeAsync((async) {
          final run = makeRun(seed: seed)..start();
          var guard = 0;
          while (run.depth <= 30 && guard++ < 60) {
            result.add('${run.depth}:${run.puzzle!.kind}:${run.solution}');
            solveAndAdvance(async, run);
          }
        });
        return result;
      }

      expect(play(2468), play(2468));
      expect(play(2468), isNot(play(1357)));
    });
  });
}

/// Small indirection so the tests read well and the store stays swappable.
class PlayerProfileFactory {
  static Profile inMemory() => Profile(MemoryStore());
}
