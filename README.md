# Sinkhole

An endless survival puzzle. You are standing on a floor that keeps collapsing.
Solve a puzzle before the timer empties, bank the seconds you win, and see how
deep you get. There is no ending, only how far you get before the floor gives
way.

Built with Flutter. Runs on iOS, Android and the web from one codebase.

## Running it

```sh
flutter pub get
flutter run                 # attached device or simulator
flutter test                # 148 unit, widget and golden tests
flutter test integration_test -d <device>   # plays a real run on a device
```

## The loop

A run is one continuous descent:

1. A puzzle appears with a **floor timer** draining.
2. Solve it in time and you are paid bonus seconds. Fast solves bank a **buffer**
   that carries into the next puzzle, so a good run compounds.
3. A wrong answer costs seconds and adds a **crack**. Three cracks ends the run
   even with time left.
4. Every fifth solve earns a power-up; every tenth depth is a **boss** worth half
   again as much.

Difficulty rises with depth. The base allowance shrinks once per level (a band
of five depths) and each puzzle template scales its own parameters on the same
curve, so the floor is always the thing that gets meaner rather than the rules
changing underneath you.

## Puzzle types

Every puzzle is generated from a template plus parameters, so the game never runs
out. A run is fully described by its seed, which is what makes the daily
challenge shareable and replays exact.

| Type | What it asks | The guarantee that makes it fair |
| --- | --- | --- |
| Sequence | What number comes next? | Exactly one rule in the pool fits the visible terms. |
| Pattern | What shape and colour comes next? | Two full cycles are always shown, so the period is visible. |
| Make 24 | Hit the target from four numbers | Solved with an exact rational solver, and every distractor is a value those four numbers provably *cannot* produce. |
| Grid Logic | Fill the 3x3 gap | A Latin square, so the missing value is forced by its row. Deep runs hide two cells that always share one value, keeping a single answer. |
| Memory | Where was this symbol? | The asked symbol appears exactly once, and every wrong option points at a cell that *was* lit, so "which one was empty" never works. |
| Odd One Out | Which one does not belong? | Three identical options, and the odd one differs in exactly one visible property. |

Those guarantees are not aspirational. They are properties asserted across every
depth from 1 to 60 and a range of seeds in `test/puzzle_test.dart`, which
re-derives the answer from the rules rather than trusting the generator.

## Layout

```
lib/
  core/        seeded RNG, the difficulty curve
  model/       tokens, puzzles, run results, power-ups
  puzzle/      the six generators, the make-24 solver, rotation
  engine/      run controller: timer, cracks, streaks, bosses, power-ups
  audio/       procedural WAV synthesis and playback
  data/        Hive-backed profile
  ui/          theme, widgets, screens
```

Two boundaries do most of the work:

**The engine never touches the widget tree.** `RunController` owns the rules and
exposes state plus a stream of one-shot `RunEffect`s. The game screen is the
only place that knows about both, and it translates effects into confetti, audio
and haptics. That is what lets the entire loop be tested with no UI at all.

**Audio ships as no assets.** Every sound is synthesised at startup: a pentatonic
scale walked upward as a streak grows, so a long run literally plays a melody
and a dropped puzzle audibly breaks it.

## Design notes

The four worlds from the brief are in `WorldPalette`, each with a dark calm
background and four saturated accents, and never more than four colours on
screen. Reaching a world unlocks the next Bloop skin.

The floor timer is the most important thing on screen, so it gets more than a
draining bar: the right-hand end is a visibly separate **reserve** for banked
seconds, so a fresh puzzle reads as full rather than half spent, and the colour
bands track the player's own remaining allowance. In the last three seconds the
edges glow, the screen shakes, the music tempo climbs, and Bloop sweats.

Some smaller calls worth knowing about:

- The memory flash is **free**. The floor holds while it is on screen, because
  punishing a player for looking is the wrong lesson.
- A boss spans a single depth and takes two steps. A missed step ends the round
  with one crack rather than compounding the damage.
- `GameScreen` takes an optional `seed`. Leaving it null mixes in the wall clock;
  setting it replays an exact run.

## Tests

`flutter test` covers the rules, the layout and the visuals:

- `puzzle_test.dart` — every generator's fairness guarantee, at every depth.
- `run_controller_test.dart` — the run loop: buffer, cracks, streaks, bosses,
  power-ups, panic, and profile recording. Runs on `fakeAsync`, so it is instant
  and deterministic.
- `widget_test.dart` — screens, tap targets and the app's navigation.
- `golden_test.dart` — renders the real screens at phone size to `test/goldens/`.
  Text renders as boxes there because the test rasterizer has no fonts, which is
  why these are good for checking layout and colour and bad for typography.
- `integration_test/` — plays an actual run on a device, which is the only thing
  that proves the ticker drains and taps land. Verified on an iOS simulator and
  an Android emulator.

## Known gaps

- The daily leaderboard is local. The run seed is shared per day, so depths are
  genuinely comparable and your own attempts on the same seed stand in as the
  board, but there is no backend.
- The Bloop wardrobe reuses one body with different hats, so the wizard, astronaut
  and pirate skins share a silhouette.

## Building in an offline environment

The machine this was written on has no network access to Maven, so the Android
build needed three workarounds. All of them live in
`~/.gradle/init.d/offline-maven-mirror.gradle` and a mirror at
`~/.gradle/offline-maven-mirror`, so no project file is modified. Delete both to
go back to normal online resolution.

1. A local Maven mirror built by hard-linking the Gradle module cache into a
   repository layout, injected as the first repository. It has to be *first*:
   Gradle resolves metadata from the first repository that has a module and then
   fetches the artifact from that same one, so leaving Google's repo in front
   makes it find cached metadata there and then fail to find the artifact.
2. An NDK override, because the Flutter SDK hard-codes 28.2.13676358 and this app
   has no native code for it to ever call.
3. A dependency substitution from AGP 8.11.0 to the cached 8.11.1, because
   Flutter's own `integration_test` module pins the former.

None of this is needed on a machine with network access; `flutter build apk`
works unmodified there.
