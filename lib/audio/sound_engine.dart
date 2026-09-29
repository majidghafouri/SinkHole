import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'wav_store.dart';
import 'wave_synth.dart';

/// A synthesised sound, ready to be replayed without re-encoding.
@immutable
class _Clip {
  const _Clip(this.id, this.source, this.volume);

  final String id;

  /// A file on native, a data URI on web. Built once at startup so replaying a
  /// sound is a single call rather than a re-encode.
  final Source source;

  final double volume;
}

/// All game audio, synthesised at startup and played from memory.
///
/// Two design notes drive the shape of this class. First, a correct answer walks
/// up a pentatonic scale, so a long streak literally plays a melody and a
/// dropped puzzle audibly breaks it. Second, the music bed is pre-rendered per
/// tempo and switched between, so raising tension costs nothing per frame.
class SoundEngine {
  SoundEngine({WaveSynth? synth}) : _synth = synth ?? const WaveSynth();

  final WaveSynth _synth;

  /// A major pentatonic scale, so any order of notes stays consonant.
  static const List<double> _scaleRatios = <double>[
    1.0, // C
    1.125, // D
    1.25, // E
    1.5, // G
    1.6875, // A
  ];

  static const double _rootHz = 523.25; // C5
  static const int _melodyOctaves = 4;

  /// Music tiers, from relaxed to frantic.
  static const List<({double hz, double beatMs})> _tiers = [
    (hz: 196.00, beatMs: 420),
    (hz: 220.00, beatMs: 300),
    (hz: 246.94, beatMs: 210),
    (hz: 277.18, beatMs: 150),
  ];

  final Map<String, _Clip> _clips = <String, _Clip>{};
  final Map<String, AudioPlayer> _players = <String, AudioPlayer>{};

  bool _ready = false;
  bool _muted = false;
  bool _musicWanted = false;
  int _tier = -1;

  AudioPlayer? _music;

  /// The rendered music bed for the current tempo tier.
  Source? _bedSource;
  int _bedIndex = -1;

  bool get isReady => _ready;

  bool get muted => _muted;

  /// How many rung notes the streak melody can play before wrapping.
  int get melodyLength => _melodyOctaves * _scaleRatios.length;

  /// Renders every sound and prepares the bytes for the platform.
  ///
  /// Deliberately does *not* create an [AudioPlayer] per clip. Doing that meant
  /// 20-odd platform-channel round trips on the startup path, and on Android the
  /// resulting MediaPlayer contention was enough to hang `main()` before
  /// `runApp` ever ran, leaving the app stuck on the splash. Players are now
  /// created on first use, which also means a game that only ever plays four
  /// different sounds only ever pays for four.
  Future<void> init() async {
    if (_ready) return;

    await _materialise();

    _music = AudioPlayer(playerId: 'music')..setReleaseMode(ReleaseMode.loop);
    await _music!.setVolume(0);

    _ready = true;
  }

  /// Returns the player for [id], creating it on first use.
  Future<AudioPlayer> _playerFor(String id) async {
    final existing = _players[id];
    if (existing != null) return existing;

    final clip = _clips[id];
    final player = AudioPlayer(playerId: 'sfx_$id')..setReleaseMode(ReleaseMode.stop);
    await player.setVolume(clip?.volume ?? 0.5);
    _players[id] = player;
    return player;
  }

  /// Renders every sound, then hands the bytes to the platform adapter, which
  /// writes a real `.wav` on native and keeps a data URI on web.
  Future<void> _materialise() async {
    final rendered = <String, ({Uint8List bytes, double volume})>{};

    for (var i = 0; i < melodyLength; i++) {
      final step = i % _scaleRatios.length;
      final octave = i ~/ _scaleRatios.length;
      final frequency = _rootHz * _scaleRatios[step] * math.pow(2, octave).toDouble();
      rendered['note$i'] = (
        bytes: _synth.pluck(
          frequency: frequency,
          milliseconds: 340,
          // Higher rungs ring longer, so a streak audibly builds.
          gain: 0.28 + 0.05 * octave,
        ),
        // Quieter than the reward stinger, so a long streak does not fatigue.
        volume: 0.4 + 0.03 * octave,
      );
    }

    _buildEffects(rendered);

    for (final entry in rendered.entries) {
      _clips[entry.key] = _Clip(
        entry.key,
        await wavSource(entry.key, entry.value.bytes),
        entry.value.volume,
      );
    }
  }

  void _buildEffects(Map<String, ({Uint8List bytes, double volume})> out) {
    void add(String id, Uint8List bytes, double volume) =>
        out[id] = (bytes: bytes, volume: volume);

    // "You did it": a short rising arpeggio.
    add(
      'reward',
      _synth.sequence(<Uint8List>[
        _synth.pluck(frequency: 523.25, milliseconds: 110),
        _synth.pluck(frequency: 659.25, milliseconds: 110),
        _synth.pluck(frequency: 783.99, milliseconds: 230),
      ]),
      0.5,
    );
    // Wrong answer: a rounded descending blip, deliberately not harsh.
    add('wrong', _synth.boop(milliseconds: 260), 0.55);
    // A crack is lower and drier than a wrong answer.
    add(
      'crack',
      _synth.tone(
        frequency: 150,
        milliseconds: 200,
        gain: 0.5,
        attackMs: 1,
        releaseMs: 120,
        partials: const [(1.0, 1.0), (2.7, 0.4)],
      ),
      0.6,
    );
    add('tap', _synth.pluck(frequency: 880, milliseconds: 55), 0.28);
    add('whoosh', _synth.whoosh(milliseconds: 420), 0.45);
    add(
      'freeze',
      _synth.tone(
        frequency: 1200,
        milliseconds: 700,
        gain: 0.35,
        attackMs: 20,
        releaseMs: 300,
        vibratoHz: 9,
        vibratoCents: 60,
      ),
      0.4,
    );
    add('shield', _synth.boop(fromHz: 400, toHz: 620, milliseconds: 240), 0.5);
    add(
      'powerup',
      _synth.sequence(<Uint8List>[
        _synth.pluck(frequency: 659.25, milliseconds: 90),
        _synth.pluck(frequency: 987.77, milliseconds: 90),
        _synth.pluck(frequency: 1318.51, milliseconds: 180),
      ]),
      0.5,
    );
    // Boss arrival: a low, wide swell.
    add(
      'boss',
      _synth.tone(
        frequency: 110,
        milliseconds: 900,
        gain: 0.5,
        attackMs: 120,
        releaseMs: 500,
        partials: const [(1.0, 1.0), (1.5, 0.5), (2.0, 0.3)],
      ),
      0.55,
    );
    // Falling: a long comic slide.
    add('fall', _synth.boop(fromHz: 700, toHz: 90, milliseconds: 850), 0.6);
    add('land', _synth.boop(fromHz: 140, toHz: 70, milliseconds: 200), 0.6);
  }

  // ------------------------------------------------------------- one-shots

  void playTap() => _play('tap');

  /// Plays the next note of the scale, wrapping at the top of the register so
  /// a very long streak keeps sounding intentional.
  void playStreakRung(int streak) =>
      _play(streak <= 0 ? 'tap' : 'note${(streak - 1) % melodyLength}');

  void playReward() => _play('reward');

  void playWrong() => _play('wrong');

  void playCrack() => _play('crack');

  void playWhoosh() => _play('whoosh');

  void playFreeze() => _play('freeze');

  void playShield() => _play('shield');

  void playPowerUp() => _play('powerup');

  void playBoss() => _play('boss');

  void playFall() => _play('fall');

  void playLand() => _play('land');

  void _play(String id) {
    if (!_ready || _muted) return;
    final clip = _clips[id];
    if (clip == null) return;
    // The player is created on demand, so a tap that lands before a sound has
    // ever played still makes noise.
    unawaited(() async {
      final player = await _playerFor(id);
      _retrigger(player, clip);
    }());
  }

  /// Restarts a one-shot. `unawaited` keeps the public helpers synchronous so
  /// they can be called straight from a gesture handler.
  static void _retrigger(AudioPlayer player, _Clip clip) {
    unawaited(() async {
      await player.stop();
      await player.setVolume(clip.volume);
      await player.play(clip.source, mode: PlayerMode.lowLatency);
    }());
  }

  // ---------------------------------------------------------------- music

  /// Starts the bed. [tier] is 0 for calm and 3 for panic.
  Future<void> startMusic({int tier = 0}) async {
    _musicWanted = true;
    await _setTier(tier);
  }

  /// Ramps the tempo as the floor timer drains. Dropping to zero on a fresh
  /// puzzle is what makes a solve feel like relief.
  Future<void> setTension(double tension) async {
    if (!_musicWanted) return;
    final target = (tension.clamp(0.0, 1.0) * (_tiers.length - 1)).round();
    if (target == _tier) return;
    await _setTier(target);
  }

  Future<void> resetTension() => _setTier(0);

  Future<void> stopMusic() async {
    _musicWanted = false;
    await _music?.stop();
    await _music?.setVolume(0);
  }

  Future<void> _setTier(int tier) async {
    if (!_ready || _music == null) return;
    final clamped = tier.clamp(0, _tiers.length - 1);
    if (clamped == _tier) return;
    _tier = clamped;

    final spec = _tiers[clamped];
    final bed = await _bedFor(clamped, spec);
    final player = _music!;
    await player.stop();
    await player.setReleaseMode(ReleaseMode.loop);
    await player.play(bed, mode: PlayerMode.mediaPlayer);
    await player.setVolume(_musicWanted && !_muted ? _tierVolume(clamped) : 0);
  }

  /// The chord bed is four beats long, so a shorter beat means a faster loop
  /// with no re-synthesis and no gap. The rendered bytes are cached per tier,
  /// because writing a file per tempo change would be wasteful.
  Future<Source> _bedFor(int index, ({double hz, double beatMs}) spec) async {
    if (_bedIndex == index && _bedSource != null) return _bedSource!;
    final notes = <double>[1.0, 1.2, 1.5, 1.2];
    final clips = <Uint8List>[
      for (final ratio in notes)
        _synth.pad(rootHz: spec.hz * ratio, milliseconds: spec.beatMs, gain: 0.16),
    ];
    final bytes = _synth.looped(_synth.sequence(clips), spec.beatMs * notes.length);
    final source = await wavSource('bed_$index', bytes);
    _bedSource = source;
    _bedIndex = index;
    return source;
  }

  static double _tierVolume(int tier) => switch (tier) {
    0 => 0.16,
    1 => 0.20,
    2 => 0.24,
    _ => 0.28,
  };

  void setMuted(bool value) {
    if (_muted == value) return;
    _muted = value;
    if (value) {
      for (final player in _players.values) {
        player.stop();
      }
      _music?.stop();
    } else if (_musicWanted) {
      // Force a restart: _setTier is a no-op when the tier is unchanged.
      _tier = -1;
      unawaited(_setTier(0));
    }
  }

  Future<void> dispose() async {
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
    _clips.clear();
    await _music?.dispose();
    _music = null;
    _bedSource = null;
    _bedIndex = -1;
    _ready = false;
  }
}

/// Fire-and-forget, so the one-shot helpers stay synchronous and can be called
/// straight from a gesture handler.
void unawaited(Future<void> future) {}
