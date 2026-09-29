import 'dart:async';

import 'package:flutter/foundation.dart';

import '../audio/haptics.dart';
import '../audio/sound_engine.dart';
import '../core/difficulty.dart';
import '../core/game_random.dart';
import '../data/player_profile.dart';
import '../model/power_up.dart';
import '../model/puzzle.dart';
import '../model/run_result.dart';
import '../model/profile.dart';
import 'skill_readout.dart';
import '../model/token.dart';
import '../puzzle/puzzle_factory.dart';
import '../puzzle/puzzle_fingerprint.dart';

/// Where a run is in its lifecycle.
enum RunPhase {
  /// A memory puzzle is showing its flash and cannot be answered yet.
  revealing,

  /// Waiting for the player to answer.
  answering,

  /// A short hold after an answer so the juice can play out.
  feedback,

  /// The floor gave way; the fall animation is running.
  falling,

  /// The result has been recorded and the screen can navigate away.
  finished,
}

/// A one-shot signal the presentation layer reacts to.
///
/// Keeping these off the controller's state means the UI can fire confetti,
/// audio and haptics without the engine knowing any of that exists, and lets
/// the whole loop be tested with no widget tree at all.
sealed class RunEffect {
  const RunEffect();
}

class PuzzleShownEffect extends RunEffect {
  const PuzzleShownEffect(this.depth, this.boss);
  final int depth;
  final bool boss;
}

class CorrectEffect extends RunEffect {
  const CorrectEffect({
    required this.optionIndex,
    required this.reward,
    required this.streak,
    required this.boss,
    required this.perfect,
  });

  final int optionIndex;
  final double reward;
  final int streak;
  final bool boss;

  /// True when the player answered with most of the timer still on the bar.
  final bool perfect;
}

class WrongEffect extends RunEffect {
  const WrongEffect({required this.optionIndex, required this.shielded});
  final int optionIndex;

  /// True when a shield ate the mistake.
  final bool shielded;
}

class CrackEffect extends RunEffect {
  const CrackEffect(this.cracks);
  final int cracks;
}

class FallEffect extends RunEffect {
  const FallEffect(this.reason, this.result);
  final FallReason reason;
  final RunResult result;
}

class LevelUpEffect extends RunEffect {
  const LevelUpEffect({required this.level, required this.depth, required this.world});

  final int level;
  final int depth;
  final int world;
}

class PowerUpUsedEffect extends RunEffect {
  const PowerUpUsedEffect(this.powerUp);
  final PowerUp powerUp;
}

class PowerUpEarnedEffect extends RunEffect {
  const PowerUpEarnedEffect(this.powerUp);
  final PowerUp powerUp;
}

class BossStepEffect extends RunEffect {
  const BossStepEffect({required this.step, required this.total, required this.cleared});

  final int step;
  final int total;

  /// True when the final step was answered correctly.
  final bool cleared;
}

class PanicEffect extends RunEffect {
  const PanicEffect(this.active);
  final bool active;
}

/// One power-up sitting in the bottom tray.
class TraySlot {
  const TraySlot(this.powerUp, this.count);

  final PowerUp powerUp;

  /// How many are held. More than one is shown as a badge.
  final int count;
}

/// Drives one run of Sinkhole: the floor timer, cracks, streaks, boss rounds
/// and power-ups.
///
/// The controller owns the rules and nothing else. It never touches the widget
/// tree; it exposes state for the UI to read and [effects] for it to react to.
class RunController extends ChangeNotifier {
  RunController({
    required this.seed,
    required this.daily,
    this.profile,
    this.ghost,
    this.sound,
    this.haptics,
    PuzzleFactory? factory,
    DateTime? now,
  }) : rng = GameRandom(seed),
       _factory = factory ?? PuzzleFactory(),
       now = now ?? DateTime.now();

  final int seed;
  final bool daily;
  final Profile? profile;
  final GhostRun? ghost;

  /// Optional so tests can run the whole loop with no platform channels.
  final SoundEngine? sound;
  final Haptics? haptics;

  final GameRandom rng;
  final PuzzleFactory _factory;

  /// Injected so a run can be recorded against a fixed day in tests.
  final DateTime now;

  final StreamController<RunEffect> _effectSink = StreamController<RunEffect>.broadcast();
  final List<SolveRecord> _records = <SolveRecord>[];

  // --------------------------------------------------------------- tuning

  /// How much leftover time can be carried into the next puzzle. This is the
  /// buffer the brief describes: solve fast and you bank seconds.
  static const double maxBuffer = 8.0;

  /// Seconds removed from the bar for a wrong answer, on top of the crack.
  static const double wrongPenalty = 2.0;

  /// Cracks needed before the floor gives way.
  static const int maxCracks = 3;

  /// Seconds left when the screen glows and Bloop panics.
  static const double panicSeconds = 3.0;

  /// Boss rounds land on every tenth depth and take two steps to clear.
  static const int bossInterval = 10;
  static const int bossSteps = 2;

  /// How long the answer feedback hold lasts before the next puzzle appears.
  static const Duration feedbackHold = Duration(milliseconds: 620);

  /// How long the fall animation runs before the result screen appears.
  static const Duration fallDuration = Duration(milliseconds: 1500);

  /// Every fifth solve hands out a power-up.
  static const int powerUpInterval = 5;

  // ---------------------------------------------------------------- state

  RunPhase _phase = RunPhase.answering;
  Puzzle? _puzzle;
  List<Token> _options = const <Token>[];
  int _solutionIndex = 0;

  int _depth = 0;
  double _timeLeft = 0;
  double _budget = 1;
  double _ceiling = 1;
  double _freezeLeft = 0;
  double _revealElapsed = 0;
  double _revealSeconds = 0;
  double _solveElapsed = 0;
  double _runElapsed = 0;
  int _cracks = 0;
  int _streak = 0;
  int _bestStreak = 0;
  bool _shieldActive = false;
  bool _hintUsed = false;
  int _hintReplays = 0;
  int _selectedOption = -1;
  bool _lastAnswerCorrect = false;
  PuzzleKind? _lastKind;
  int _powerUpsUsed = 0;
  double _lastReward = 0;
  bool _panicActive = false;
  int _bossStep = 0;
  int _bossStepsCleared = 0;
  FallReason? _fallReason;
  bool _paused = false;

  /// Fingerprints of every puzzle shown this run, so none of them come round
  /// again. This is what makes a run endless in practice rather than only in
  /// principle.
  final Set<String> _seen = <String>{};

  /// Rolling read on how the player is coping, fed into [Difficulty.skillOffset]
  /// so the content tracks the player rather than only the depth.
  final SkillReadout _skill = SkillReadout();

  Stream<RunEffect> get effects => _effectSink.stream;

  RunPhase get phase => _phase;
  Puzzle? get puzzle => _puzzle;
  int get depth => _depth;
  double get timeLeft => _timeLeft;
  double get budget => _budget;

  /// Full-scale value of the floor timer, i.e. a completely full buffer.
  double get ceiling => _ceiling;

  /// 0 at empty, 1 when the bar is full.
  double get timeFraction => (_timeLeft / _ceiling).clamp(0.0, 1.0);

  /// How much of this puzzle's own allowance is left.
  double get budgetFraction => (_timeLeft / _budget).clamp(0.0, 1.0);

  /// Seconds the player has banked above this puzzle's allowance.
  double get bufferSeconds => (_timeLeft - _budget).clamp(0.0, maxBuffer);

  double get freezeLeft => _freezeLeft;
  bool get isFrozen => _freezeLeft > 0;
  int get cracks => _cracks;
  int get streak => _streak;
  int get bestStreak => _bestStreak;
  bool get shieldActive => _shieldActive;
  bool get hintUsed => _hintUsed;

  /// Increments each time the hint replays a memory flash, so the card can
  /// restart the reveal without the controller tracking animation state.
  int get hintReplays => _hintReplays;

  int get selectedOption => _selectedOption;
  bool get lastAnswerCorrect => _lastAnswerCorrect;
  bool get isFalling => _phase == RunPhase.falling || _phase == RunPhase.finished;
  bool get isOver => _fallReason != null;
  FallReason? get fallReason => _fallReason;
  double get runElapsed => _runElapsed;
  int get powerUpsUsed => _powerUpsUsed;

  /// Seconds paid out by the most recent solve, for the `+2.4s` popup.
  double get lastReward => _lastReward;

  PuzzleKind? get lastKind => _lastKind;

  bool get isPanic => _panicActive;
  bool get acceptsAnswers => _phase == RunPhase.answering && !_paused;

  Difficulty get difficulty => Difficulty(_depth, skillOffset: _skill.offset);
  int get worldIndex => Difficulty.worldIndexFor(_depth);

  /// How far the adaptive layer is currently pushing the curve, in ramp units.
  /// Exposed for the result screen and for tests.
  double get skillOffset => _skill.offset;

  /// How many distinct puzzles this run has shown.
  int get puzzlesShown => _seen.length;

  /// True while a boss round is on screen, including its later steps.
  bool get isBossRound => _depth > 0 && (_depth % bossInterval == 0);

  /// Which boss step the player is on, 1-based; 0 when not in a boss.
  int get bossStep => _bossStep;

  int get bossStepsCleared => _bossStepsCleared;
  int get bossStepCount => bossSteps;

  List<Token> get options => _options;
  int get solutionIndex => _solutionIndex;

  /// The option the player needs to pick. Exposed for the debug overlay and
  /// for tests that drive a run by always solving correctly.
  Token? get solution => _solutionIndex >= 0 && _solutionIndex < _options.length
      ? _options[_solutionIndex]
      : null;

  /// The power-up tray, mirrored from the profile when one is attached.
  List<TraySlot> get tray => <TraySlot>[
    for (final p in PowerUp.values)
      if (countOf(p) > 0) TraySlot(p, countOf(p)),
  ];

  int countOf(PowerUp p) => profile?.powerUpCount(p) ?? 0;

  // ----------------------------------------------------------------- setup

  /// Starts the run at depth 1. The caller drives [tick] from a ticker.
  void start() {
    _depth = 1;
    _records.clear();
    _seen.clear();
    _skill.reset();
    _spawnNext();
    _bg(sound?.startMusic());
  }

  /// Advances the clock. Call once per frame while the run is live.
  void tick(double deltaSeconds) {
    if (_paused || isOver) return;
    if (_phase == RunPhase.feedback || _phase == RunPhase.falling) return;

    _runElapsed += deltaSeconds;

    // The memory flash is free: the floor holds still while it is on screen,
    // and the clock only starts once the question becomes answerable.
    if (_phase == RunPhase.revealing) {
      _revealElapsed += deltaSeconds;
      if (_revealElapsed >= _revealSeconds) {
        _phase = RunPhase.answering;
        _revealElapsed = 0;
        notifyListeners();
      }
      return;
    }

    _solveElapsed += deltaSeconds;

    if (_freezeLeft > 0) {
      _freezeLeft = (_freezeLeft - deltaSeconds).clamp(0.0, PowerUpInfo.freezeSeconds);
      // Repaint anyway so the freeze countdown on the bar stays live.
      notifyListeners();
      return;
    }

    _timeLeft -= deltaSeconds;

    // Tension drives the music tempo: a full bar is calm, an empty one frantic.
    _bg(sound?.setTension(1.0 - budgetFraction));

    final panicking = _timeLeft <= panicSeconds;
    if (panicking != _panicActive) {
      _panicActive = panicking;
      _emit(PanicEffect(panicking));
      if (panicking) haptics?.tick();
    }

    if (_timeLeft <= 0) {
      _timeLeft = 0;
      _endRun(FallReason.timeout);
      return;
    }

    notifyListeners();
  }

  /// Pauses the clock, e.g. when the app goes to the background.
  void setPaused(bool value) {
    if (_paused == value) return;
    _paused = value;
    if (value) {
      _bg(sound?.stopMusic());
    } else {
      _bg(sound?.startMusic());
    }
    notifyListeners();
  }

  // ------------------------------------------------------------- answering

  /// Handles a tap on one of the answer buttons.
  void answer(int optionIndex) {
    if (!acceptsAnswers) return;
    if (optionIndex < 0 || optionIndex >= _options.length) return;

    _selectedOption = optionIndex;
    final correct = optionIndex == _solutionIndex;
    final wasBoss = isBossRound;

    if (correct) {
      _onCorrect(wasBoss);
    } else {
      _onWrong(optionIndex, wasBoss);
    }

    // A third crack ends the run inside _onWrong, and the fall must not be
    // overwritten by the feedback hold.
    if (!isOver) {
      _phase = RunPhase.feedback;
      _bg(Future<void>.delayed(feedbackHold, _advanceAfterFeedback));
    }
    notifyListeners();
  }

  void _onCorrect(bool wasBoss) {
    final puzzle = _puzzle!;
    final solveSeconds = _solveElapsed;
    _lastAnswerCorrect = true;
    _streak++;
    if (_streak > _bestStreak) _bestStreak = _streak;

    final reward = computeReward(budgetFraction, _streak, wasBoss);
    _lastReward = reward;
    _timeLeft = (_timeLeft + reward).clamp(0.0, _ceiling);

    _records.add(
      SolveRecord(
        kind: puzzle.kind,
        depth: _depth,
        correct: true,
        seconds: solveSeconds,
        wasBoss: wasBoss,
      ),
    );
    _skill.record(correct: true, secondsLeftFraction: budgetFraction);

    haptics?.correct();
    sound?.playStreakRung(_streak);
    sound?.playReward();

    _emit(
      CorrectEffect(
        optionIndex: _solutionIndex,
        reward: reward,
        streak: _streak,
        boss: wasBoss,
        perfect: budgetFraction > 0.6,
      ),
    );
    if (wasBoss) {
      _emit(
        BossStepEffect(
          step: _bossStep,
          total: bossSteps,
          cleared: _bossStep >= bossSteps,
        ),
      );
    }
  }

  void _onWrong(int optionIndex, bool wasBoss) {
    final puzzle = _puzzle!;
    final solveSeconds = _solveElapsed;
    _lastAnswerCorrect = false;
    _streak = 0;

    _records.add(
      SolveRecord(
        kind: puzzle.kind,
        depth: _depth,
        correct: false,
        seconds: solveSeconds,
        wasBoss: wasBoss,
      ),
    );
    _skill.record(correct: false, secondsLeftFraction: budgetFraction);

    if (_shieldActive) {
      // A shield eats the whole mistake: no crack, and no time lost either.
      _shieldActive = false;
      sound?.playShield();
      _emit(WrongEffect(optionIndex: optionIndex, shielded: true));
      return;
    }

    _timeLeft = (_timeLeft - wrongPenalty).clamp(0.0, _ceiling);
    _cracks++;
    sound?.playWrong();
    sound?.playCrack();
    haptics?.crack();
    _emit(WrongEffect(optionIndex: optionIndex, shielded: false));
    _emit(CrackEffect(_cracks));

    if (wasBoss) {
      // A botched step ends the boss early instead of compounding the damage.
      _emit(BossStepEffect(step: _bossStep, total: bossSteps, cleared: false));
    }

    if (_cracks >= maxCracks) {
      _endRun(FallReason.cracks);
    }
  }

  /// The reward a solve pays out, in seconds.
  ///
  /// Fast solves are worth noticeably more than slow ones, the streak
  /// multiplies on top, and boss rounds pay half again as much.
  static double computeReward(double budgetFraction, int streak, bool boss) {
    final speed = 1.6 + 2.4 * budgetFraction.clamp(0.0, 1.0);
    final combo = 1.0 + _comboCap(streak) * 0.06;
    return speed * combo * (boss ? 1.5 : 1.0);
  }

  /// Streaks are capped so a long run cannot snowball into a trivial one.
  static int _comboCap(int streak) => streak > 12 ? 12 : streak;

  void _advanceAfterFeedback() {
    if (isOver || _paused) return;
    _phase = RunPhase.answering;
    _advanceDepth();
  }

  /// Decides what comes after an answered puzzle: a new depth, or the next step
  /// of the boss the player is already in.
  void _advanceDepth() {
    // A boss occupies one depth but two steps. The first step is solved, so the
    // round continues at the same depth with a different puzzle rather than
    // moving the counter on.
    if (isBossRound && _lastAnswerCorrect && _bossStep < bossSteps) {
      _bossStep++;
      _bossStepsCleared++;
      // Step two keeps the same boss urgency, so the reward stays boosted, and
      // the round is only paid out once both steps are done.
      _spawnNext(resumeBossStep: true);
      return;
    }

    if (isBossRound) {
      if (_lastAnswerCorrect) {
        _bossStepsCleared++;
        _grantPowerUp();
      }
      _bossStep = 0;
      _lastKind = _puzzle?.kind;
      _depth++;
      _spawnNext();
      return;
    }

    _lastKind = _puzzle?.kind;
    _depth++;
    _spawnNext();

    if (_depth % powerUpInterval == 0) _grantPowerUp();
  }

  // -------------------------------------------------------------- spawning

  void _spawnNext({bool resumeBossStep = false}) {
    final previousLevel = Difficulty(_depth > 0 ? _depth - 1 : 0).level;
    final carry = _carryFromPrevious;

    if (resumeBossStep) {
      // Step two of a boss: same depth, same gold framing, a fresh puzzle.
      _lastKind = _puzzle?.kind;
    } else {
      _bossStep = isBossRound ? 1 : 0;
      if (isBossRound) {
        _bossStepsCleared = 0;
        sound?.playBoss();
      }
    }

    _puzzle = _factory.build(
      rng,
      _depth,
      lastKind: _lastKind,
      boss: isBossRound,
      seen: _seen,
      skillOffset: _skill.offset,
    );
    _seen.add(puzzleFingerprint(_puzzle!));
    _budget = _puzzle!.budgetSeconds;
    _ceiling = _budget + maxBuffer;
    // The very first puzzle has nothing to carry, so it opens at a clean budget.
    _timeLeft = _budget + (_depth <= 1 ? 0 : carry);
    _lastKind = _puzzle!.kind;
    _applyNewPuzzleState();

    final level = Difficulty(_depth).level;
    if (level != previousLevel) {
      sound?.playWhoosh();
      haptics?.levelUp();
      _emit(LevelUpEffect(level: level, depth: _depth, world: worldIndex));
    }

    _bg(sound?.resetTension());
    _emit(PuzzleShownEffect(_depth, isBossRound));
    notifyListeners();
  }

  /// Leftover seconds from the puzzle just finished, clamped to the buffer cap.
  double get _carryFromPrevious => (_timeLeft - _budget).clamp(0.0, maxBuffer);

  /// Resets the per-puzzle state shared by spawning and by skipping.
  void _applyNewPuzzleState() {
    _options = _puzzle!.options;
    _solutionIndex = _puzzle!.solutionIndex;
    _selectedOption = -1;
    _lastAnswerCorrect = false;
    _hintUsed = false;
    _solveElapsed = 0;
    _revealElapsed = 0;
    _revealSeconds = switch (_puzzle!.body) {
      final TokenGridBody grid => (grid.flashMs ?? 0) / 1000.0,
      _ => 0.0,
    };
    _phase = _revealSeconds > 0 ? RunPhase.revealing : RunPhase.answering;
    _panicActive = false;
  }

  // ------------------------------------------------------------ power-ups

  bool canUse(PowerUp p) => countOf(p) > 0 && !isOver && !_paused;

  /// Spends a power-up. Returns false when it cannot be used right now.
  bool use(PowerUp p) {
    if (!canUse(p)) return false;

    switch (p) {
      case PowerUp.freeze:
        _freezeLeft = PowerUpInfo.freezeSeconds;
        sound?.playFreeze();
      case PowerUp.skip:
        _skipPuzzle();
        sound?.playPowerUp();
      case PowerUp.hint:
        _applyHint();
        sound?.playPowerUp();
      case PowerUp.shield:
        _shieldActive = true;
        sound?.playShield();
    }

    profile?.spendPowerUp(p);
    _powerUpsUsed++;
    haptics?.correct();
    _emit(PowerUpUsedEffect(p));
    notifyListeners();
    return true;
  }

  void _skipPuzzle() {
    // A skip costs a sliver of time but keeps the streak: it is a rescue, not
    // a punishment.
    _timeLeft = (_timeLeft - PowerUpInfo.skipCostSeconds).clamp(0.5, _ceiling);
    _puzzle = _factory.build(
      rng,
      _depth,
      lastKind: _puzzle?.kind,
      boss: isBossRound,
      seen: _seen,
      skillOffset: _skill.offset,
    );
    _budget = _puzzle!.budgetSeconds;
    _ceiling = _budget + maxBuffer;
    _timeLeft = _timeLeft.clamp(0.5, _ceiling);
    _applyNewPuzzleState();
    _emit(PuzzleShownEffect(_depth, isBossRound));
  }

  void _applyHint() {
    if (_puzzle!.hasFlash) {
      // For a memory puzzle the most useful hint is simply to see it again.
      _hintReplays++;
      return;
    }
    if (_hintUsed || _options.length <= 2) return;

    final wrong = <int>[
      for (var i = 0; i < _options.length; i++)
        if (i != _solutionIndex) i,
    ];
    if (wrong.isEmpty) return;
    final remove = wrong[_hintReplays % wrong.length];
    _options = <Token>[
      for (var i = 0; i < _options.length; i++)
        if (i != remove) _options[i],
    ];
    if (_solutionIndex > remove) _solutionIndex--;
    _selectedOption = -1;
    _hintUsed = true;
  }

  void _grantPowerUp() {
    final p = rng.pick(PowerUp.values);
    profile?.addPowerUp(p);
    _emit(PowerUpEarnedEffect(p));
  }

  // ---------------------------------------------------------------- ending

  void _endRun(FallReason reason) {
    if (isOver) return;
    if (reason == FallReason.timeout) {
      _skill.record(correct: false, secondsLeftFraction: 0);
    }
    _fallReason = reason;
    _phase = RunPhase.falling;
    _panicActive = false;
    _streak = 0;

    sound?.playFall();
    haptics?.fall();
    _bg(sound?.stopMusic());

    final result = RunResult(
      depth: _depth,
      bestStreak: _bestStreak,
      reason: reason,
      records: List<SolveRecord>.unmodifiable(_records),
      daily: daily,
      worldIndex: worldIndex,
      elapsedSeconds: _runElapsed,
      powerUpsUsed: _powerUpsUsed,
    );
    profile?.recordRun(result, now: now);
    _emit(FallEffect(reason, result));
    notifyListeners();

    _bg(
      Future<void>.delayed(fallDuration, () {
        if (_phase == RunPhase.falling) {
          _phase = RunPhase.finished;
          notifyListeners();
        }
      }),
    );
  }

  /// Ends the run early, for a player who taps the quit affordance.
  void abandon() {
    if (isOver) return;
    _endRun(FallReason.quit);
  }

  void _emit(RunEffect effect) {
    if (_effectSink.isClosed) return;
    _effectSink.add(effect);
  }

  /// Fire-and-forget for the nullable sound engine, keeping call sites terse.
  static void _bg(Future<void>? future) {
    if (future != null) unawaited(future);
  }

  @override
  void dispose() {
    _effectSink.close();
    super.dispose();
  }
}
