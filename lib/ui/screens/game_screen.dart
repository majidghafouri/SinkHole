import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../audio/haptics.dart';
import '../../audio/sound_engine.dart';
import '../../core/difficulty.dart';
import '../../data/player_profile.dart';
import '../../engine/run_controller.dart';
import '../../model/power_up.dart';
import '../../model/profile.dart';
import '../../model/run_result.dart';
import '../theme/app_theme.dart';
import '../theme/world_palette.dart';
import '../widgets/answer_grid.dart';
import '../widgets/arena.dart';
import '../widgets/bloop.dart';
import '../widgets/chunky.dart';
import '../widgets/confetti.dart';
import '../widgets/floor_timer_bar.dart';
import '../widgets/power_up_tray.dart';
import '../widgets/puzzle_card.dart';
import '../widgets/run_status_bar.dart';
import 'result_screen.dart';

/// The game screen.
///
/// This is the only place that knows about both the engine and the
/// presentation: it drives the clock, translates [RunEffect]s into juice, and
/// hands the finished [RunResult] to the result card. Everything it draws is
/// already palette-aware, so a world change repaints the whole screen.
class GameScreen extends StatefulWidget {
  const GameScreen({
    required this.profile,
    required this.sound,
    required this.haptics,
    this.daily = false,
    this.ghost,
    this.seed,
    super.key,
  });

  final Profile profile;
  final SoundEngine sound;
  final Haptics haptics;
  final bool daily;
  final GhostRun? ghost;

  /// Pins the run's puzzle sequence. Left null, the run mixes the wall clock
  /// into the seed so two quick restarts are not identical. Set it to replay an
  /// exact run.
  final int? seed;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

/// The screen owns two tickers of its own: the game clock and the pulse that
/// drives the timer, the floor and the world transition. Hence the regular
/// `TickerProviderStateMixin`, not the single-ticker one.
class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final RunController _run;
  late final Ticker _ticker;

  /// A free-running driver for the things that must breathe without a
  /// controller: the timer pulse, the floor wobble and Bloop's idle.
  late final AnimationController _pulse;

  final ConfettiController _confetti = ConfettiController();
  final GlobalKey _cardKey = GlobalKey();

  StreamSubscription<RunEffect>? _effectSub;
  Duration _lastTick = Duration.zero;

  int _worldIndex = 0;
  bool _resultShown = false;

  /// The card wobble, driven to 1 on a wrong answer and released on completion.
  double _wobble = 0;

  /// Bloop's mood between events, e.g. the cheer that follows a solve.
  BloopMood _mood = BloopMood.idle;

  /// The memory card's own reveal state, surfaced here so the answer buttons
  /// can grey out while a flash is on screen.
  bool _answerable = true;

  PowerUp? _toast;
  bool _toastVisible = false;
  int? _pendingWorld;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _run = RunController(
      seed: widget.seed ?? seedForRun(daily: widget.daily, now: DateTime.now()),
      daily: widget.daily,
      profile: widget.profile,
      ghost: widget.ghost,
      sound: widget.sound,
      haptics: widget.haptics,
    )..start();
    _worldIndex = _run.worldIndex;

    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();

    _ticker = createTicker(_onFrame)..start();
    _effectSub = _run.effects.listen(_handleEffect);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _effectSub?.cancel();
    _confetti.dispose();
    _ticker.dispose();
    _pulse.dispose();
    _run.dispose();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The floor keeps collapsing whether or not anyone is watching.
    _run.setPaused(state != AppLifecycleState.resumed);
  }

  void _onFrame(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final dt = (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;
    if (dt <= 0) return;
    _run.tick(dt);
    _confetti.update(dt);
  }

  // ---------------------------------------------------------------- effects

  void _handleEffect(RunEffect effect) {
    if (!mounted) return;
    switch (effect) {
      case PuzzleShownEffect():
        setState(() {
          _mood = BloopMood.idle;
          _toastVisible = false;
          _answerable = true;
        });
        _confetti.clear();

      case CorrectEffect(:final boss, :final perfect):
        _confetti.burst(
          _cardCentre,
          count: boss ? 60 : (perfect ? 34 : 22),
          colors: Worlds.forIndex(_worldIndex).accents,
          power: boss ? 1.3 : 1.0,
        );
        setState(() {
          _mood = boss || perfect ? BloopMood.celebrate : BloopMood.cheer;
          _toastVisible = true;
        });

      case WrongEffect(:final shielded):
        setState(() {
          _wobble = 1;
          _mood = BloopMood.wince;
        });
        if (shielded) {
          _confetti.burst(
            _cardCentre,
            count: 14,
            colors: const <Color>[Color(0xFF7DD3FC)],
          );
        }

      case CrackEffect():
        setState(() {});

      case LevelUpEffect(:final world):
        if (world != _worldIndex) {
          _worldIndex = world;
          _pendingWorld = world;
          _confetti.burst(
            _cardCentre,
            count: 44,
            colors: Worlds.forIndex(world).accents,
            power: 1.25,
          );
        }
        setState(() => _mood = BloopMood.celebrate);

      case PowerUpEarnedEffect(:final powerUp):
        setState(() {
          _toast = powerUp;
          _toastVisible = true;
        });

      case PowerUpUsedEffect():
        setState(() => _toastVisible = false);

      case PanicEffect():
        setState(() {});

      case BossStepEffect():
        setState(() {});

      case FallEffect(:final result):
        _beginFall(result);
    }
  }

  void _beginFall(RunResult result) {
    if (_resultShown) return;
    _resultShown = true;
    _confetti.clear();
    // Let the tumble play out, then swap in the result card.
    Future<void>.delayed(RunController.fallDuration, () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 420),
          pageBuilder: (_, animation, secondary) => ResultScreen(
            result: result,
            profile: widget.profile,
            daily: widget.daily,
            onPlayAgain: _restart,
            onHome: () =>
                Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false),
          ),
          transitionsBuilder: (_, animation, secondary, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    });
  }

  void _restart() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          profile: widget.profile,
          sound: widget.sound,
          haptics: widget.haptics,
          daily: widget.daily,
          // The run just recorded becomes the ghost for the next attempt.
          ghost: widget.profile.bestGhost,
        ),
      ),
    );
  }

  /// The centre of the puzzle card in global coordinates, used to aim confetti.
  Offset get _cardCentre {
    final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      final size = MediaQuery.sizeOf(context);
      return Offset(size.width / 2, size.height * 0.42);
    }
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  BloopMood get _currentMood {
    if (_run.isFalling) return BloopMood.tumble;
    if (_run.isPanic) return BloopMood.panic;
    if (_run.timeLeft <= 4.5 && _run.timeLeft > RunController.panicSeconds) {
      return BloopMood.sweat;
    }
    return _mood;
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _run,
      builder: (context, _) => _buildWorld(context),
    );
  }

  Widget _buildWorld(BuildContext context) {
    final world = Worlds.forIndex(_worldIndex);
    final panic = _run.isPanic;

    return WorldScope(
      world: world,
      child: Scaffold(
        backgroundColor: world.skyBottom,
        body: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final pulse = _pulse.value * 2 * math.pi;
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _Sky(world: world),
                CrumblingFloor(
                  world: world,
                  progress: _run.difficulty.ramp,
                  shake: pulse,
                ),
                // The screen shake in the panic zone, and nothing else: it has
                // to be unmistakable without making the puzzle unreadable.
                Transform.translate(
                  offset: panic
                      ? Offset(_shake(pulse, 0), _shake(pulse, 1.7))
                      : Offset.zero,
                  child: child,
                ),
                PanicGlow(active: panic, pulse: pulse, world: world),
                CrackOverlay(cracks: _run.cracks, world: world),
                ConfettiLayer(controller: _confetti),
                if (_pendingWorld != null)
                  _WorldTransition(
                    worldIndex: _pendingWorld!,
                    onDone: () {
                      if (mounted) setState(() => _pendingWorld = null);
                    },
                  ),
                if (_run.isFalling) _FallCurtain(world: world),
              ],
            );
          },
          child: _SafeFrame(
            child: Column(
              children: <Widget>[
                _topRow(world),
                const SizedBox(height: 10),
                FloorTimerBar(
                  world: world,
                  fraction: _run.timeFraction,
                  budgetFraction: _run.budget / _run.ceiling,
                  allowanceFraction: _run.budgetFraction,
                  frozen: _run.isFrozen,
                  freezeFraction: _run.freezeLeft / PowerUpInfo.freezeSeconds,
                  panic: panic,
                  pulse: _pulse.value,
                ),
                if (widget.ghost != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Center(
                    child: GhostMarker(
                      ghostDepth: widget.ghost!.depth,
                      currentDepth: _run.depth,
                      world: world,
                    ),
                  ),
                ],
                Expanded(child: _middle(world)),
                _bottom(world),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static double _shake(double pulse, double phase) => math.sin(pulse * 6 + phase) * 3.5;

  Widget _topRow(WorldPalette world) {
    return Row(
      children: <Widget>[
        _QuitButton(onQuit: _confirmQuit),
        Expanded(
          child: RunStatusBar(
            world: world,
            depth: _run.depth,
            streak: _run.streak,
            cracks: _run.cracks,
            maxCracks: RunController.maxCracks,
            shielded: _run.shieldActive,
            boss: _run.isBossRound,
            bossStep: _run.bossStep,
            bossSteps: _run.bossStepCount,
            daily: widget.daily,
          ),
        ),
      ],
    );
  }

  Widget _middle(WorldPalette world) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Column(
          children: <Widget>[
            if (_toast != null)
              PowerUpToast(powerUp: _toast!, visible: _toastVisible, world: world),
            Expanded(
              child: Align(
                // Slightly above centre: it leaves the thumb zone for the
                // answers without stranding the card under the timer bar.
                alignment: const Alignment(0, -0.35),
                child: SingleChildScrollView(
                  child: _Wobble(
                    strength: _wobble,
                    onDone: () => setState(() => _wobble = 0),
                    child: PuzzleCard(
                      key: _cardKey,
                      puzzle: _run.puzzle,
                      world: world,
                      boss: _run.isBossRound,
                      dimmed: _run.selectedOption >= 0,
                      replayToken: _run.hintReplays,
                      onAnswerableChanged: (value) {
                        if (_answerable != value) {
                          setState(() => _answerable = value);
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
            // Bloop stands on the floor in front of the card, leaving the area
            // below free for the answer buttons.
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Bloop(
                mood: _currentMood,
                size: 74,
                skin: widget.profile.selectedSkin,
                bodyColor: world.accents[0],
                accentColor: world.ink,
                tumbleProgress: _run.isFalling ? 1 : 0,
              ),
            ),
          ],
        ),
        Positioned(
          top: 6,
          left: 0,
          right: 0,
          child: Center(
            child: _ResultLine(run: _run, world: world),
          ),
        ),
      ],
    );
  }

  Widget _bottom(WorldPalette world) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AnswerGrid(
            options: _run.options,
            world: world,
            selected: _run.selectedOption,
            solutionIndex: _run.solutionIndex,
            enabled: _answerable && _run.acceptsAnswers,
            locked: _run.selectedOption >= 0,
            onTap: _run.answer,
          ),
          const SizedBox(height: 12),
          PowerUpTray(
            slots: _run.tray,
            world: world,
            enabled: !_run.isOver,
            onUse: _run.use,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmQuit() async {
    if (_run.isOver) return;
    _run.setPaused(true);
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => _QuitDialog(
        world: Worlds.forIndex(_worldIndex),
        onStay: () => Navigator.of(context).pop(false),
        onLeave: () => Navigator.of(context).pop(true),
      ),
    );
    if (leave ?? false) {
      _run.abandon();
    } else {
      _run.setPaused(false);
    }
  }
}

/// The play column, inside the safe area and on a consistent gutter.
class _SafeFrame extends StatelessWidget {
  const _SafeFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: child),
    );
  }
}

/// The vertical gradient the whole world sits on.
class _Sky extends StatelessWidget {
  const _Sky({required this.world});
  final WorldPalette world;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[world.skyTop, world.skyBottom],
        ),
      ),
    );
  }
}

/// Shakes the card after a wrong answer, then settles.
class _Wobble extends StatefulWidget {
  const _Wobble({required this.strength, required this.child, required this.onDone});

  final double strength;
  final Widget child;
  final VoidCallback onDone;

  @override
  State<_Wobble> createState() => _WobbleState();
}

class _WobbleState extends State<_Wobble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(_Wobble old) {
    super.didUpdateWidget(old);
    if (widget.strength > 0 && old.strength == 0) {
      _c.forward(from: 0).whenComplete(widget.onDone);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = (1 - _c.value) * math.sin(_c.value * math.pi * 6);
        return Transform.translate(
          offset: Offset(t * 14, t * 4),
          child: Transform.rotate(angle: t * 0.035, child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// The `+2.4s` reward on a solve, or `CRACK!` on a mistake.
class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.run, required this.world});

  final RunController run;
  final WorldPalette world;

  @override
  Widget build(BuildContext context) {
    final answered = run.selectedOption >= 0;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 140),
      opacity: answered ? 1 : 0,
      child: Text(
        !answered
            ? ''
            : run.lastAnswerCorrect
            ? formatSeconds(run.lastReward)
            : 'CRACK!',
        style: SinkType.rounded(
          SinkType.title.copyWith(
            fontSize: 30,
            color: run.lastAnswerCorrect ? world.accents[2] : const Color(0xFFFF5470),
            shadows: const <Shadow>[
              Shadow(color: Color(0x77000000), blurRadius: 8, offset: Offset(0, 3)),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuitButton extends StatelessWidget {
  const _QuitButton({required this.onQuit});
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChunkyButton(
        onTap: onQuit,
        padding: EdgeInsets.zero,
        radius: SinkShape.pillRadius,
        fill: Colors.white.withValues(alpha: 0.12),
        outline: Colors.white.withValues(alpha: 0.25),
        outlineWidth: 2,
        elevation: 0,
        semanticLabel: 'Leave the run',
        child: const SizedBox.square(
          dimension: 34,
          child: Icon(Icons.close_rounded, size: 19, color: Colors.white70),
        ),
      ),
    );
  }
}

class _QuitDialog extends StatelessWidget {
  const _QuitDialog({required this.world, required this.onStay, required this.onLeave});

  final WorldPalette world;
  final VoidCallback onStay;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: world.skyTop,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SinkShape.radius),
        side: BorderSide(color: world.accents[0], width: 3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Bloop(
              mood: BloopMood.idle,
              size: 72,
              bodyColor: world.accents[0],
              accentColor: world.ink,
            ),
            const SizedBox(height: 10),
            Text(
              'CLIMB BACK OUT?',
              style: SinkType.rounded(SinkType.title.copyWith(color: Colors.white)),
            ),
            const SizedBox(height: 8),
            Text(
              'The run ends here and your depth is recorded.',
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
            Row(
              children: <Widget>[
                Expanded(
                  child: ChunkyButton(
                    onTap: onStay,
                    fill: Colors.white.withValues(alpha: 0.14),
                    child: Text(
                      'STAY',
                      style: SinkType.rounded(
                        SinkType.label.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ChunkyButton(
                    onTap: onLeave,
                    fill: world.accents[3],
                    child: Text(
                      'LEAVE',
                      style: SinkType.rounded(
                        SinkType.label.copyWith(color: world.onButton(3)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The short cinematic that drops the camera into a new world.
class _WorldTransition extends StatefulWidget {
  const _WorldTransition({required this.worldIndex, required this.onDone});

  final int worldIndex;
  final VoidCallback onDone;

  @override
  State<_WorldTransition> createState() => _WorldTransitionState();
}

class _WorldTransitionState extends State<_WorldTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final world = Worlds.forIndex(widget.worldIndex);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = Curves.easeInCubic.transform(_c.value);
          // The band sweeps up past the camera while the name is legible.
          final bandHeight = MediaQuery.sizeOf(context).height * 0.34;
          return Opacity(
            opacity: (1 - t * 1.15).clamp(0.0, 1.0),
            child: Align(
              alignment: Alignment.topCenter,
              child: Transform.translate(
                offset: Offset(0, -bandHeight * t),
                child: Container(
                  height: bandHeight,
                  width: double.infinity,
                  color: world.floor,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          world.name.toUpperCase(),
                          style: SinkType.rounded(
                            SinkType.title.copyWith(
                              color: world.onButton(0),
                              fontSize: 26,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          world.tagline.toUpperCase(),
                          style: SinkType.rounded(
                            SinkType.caption.copyWith(
                              color: world.onButton(0),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The falling sequence: the void rushes up and Bloop tumbles out of frame.
class _FallCurtain extends StatelessWidget {
  const _FallCurtain({required this.world});
  final WorldPalette world;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: RunController.fallDuration,
        curve: Curves.easeInCubic,
        builder: (context, t, _) => Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Transform.translate(
              offset: Offset(0, -MediaQuery.sizeOf(context).height * t * 0.5),
              child: ColoredBox(color: world.skyTop.withValues(alpha: 0.92 * t)),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: 150 * t),
                child: Bloop(
                  mood: BloopMood.tumble,
                  size: 90,
                  bodyColor: world.accents[0],
                  accentColor: world.ink,
                  tumbleProgress: t,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
