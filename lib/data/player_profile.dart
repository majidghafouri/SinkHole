import 'package:flutter/foundation.dart';

import '../core/difficulty.dart';
import '../core/game_random.dart';
import '../model/power_up.dart';
import '../model/puzzle.dart';
import '../model/run_result.dart';
import '../model/profile.dart';
import 'save_service.dart';

/// Everything the game remembers between sessions.
///
/// Reads are eager and writes are explicit: the whole profile is small enough to
/// hold in memory, and every mutation goes through [persist] so a crash can
/// never leave it half-updated.
///
/// It is a [ChangeNotifier] because the app theme and the mascot skin follow
/// the profile: reaching a new world or picking a new hat has to repaint.
class Profile extends ChangeNotifier {
  Profile(this._store) : _state = _store.readState(_key) {
    _bestDepth = _int('bestDepth');
    _totalRuns = _int('totalRuns');
    _totalDepth = _int('totalDepth');
    _totalSolved = _int('totalSolved');
    _totalAnswered = _int('totalAnswered');
    _bestStreak = _int('bestStreak');
    _soundEnabled = _bool('soundEnabled', fallback: true);
    _hapticsEnabled = _bool('hapticsEnabled', fallback: true);
    _selectedSkin = _state['skin'] as String? ?? defaultSkin;
    _unlockedSkins = _stringSet('unlockedSkins')..add(defaultSkin);
    _dailyStreak = _int('dailyStreak');
    _claimedChests = _stringSet('claimedChests');
    _perKindSolved = _intMap('perKindSolved');
    _perKindSeconds = _doubleMap('perKindSeconds');
    _lastPlayedDay = _state['lastPlayedDay'] as String?;
    _powerUps = _intMap('powerUps');
    _bestGhost = _ghost('bestGhost');
    _dailyGhost = _ghost('dailyGhost');
    // Re-derive unlocks so a profile written by an older build still has them.
    _unlockedSkins.addAll(skinUnlocksFor(_bestDepth));
  }

  static const String _key = 'profile';

  final KeyValueStore _store;
  final Map<String, dynamic> _state;

  static const String defaultSkin = 'classic';

  late int _bestDepth;
  late int _totalRuns;
  late int _totalDepth;
  late int _totalSolved;
  late int _totalAnswered;
  late int _bestStreak;
  late bool _soundEnabled;
  late bool _hapticsEnabled;
  late String _selectedSkin;
  late Set<String> _unlockedSkins;
  late int _dailyStreak;
  late Set<String> _claimedChests;
  late Map<String, int> _perKindSolved;
  late Map<String, double> _perKindSeconds;
  late String? _lastPlayedDay;
  late Map<String, int> _powerUps;
  GhostRun? _bestGhost;
  GhostRun? _dailyGhost;

  // ------------------------------------------------------------- read side

  int get bestDepth => _bestDepth;
  int get totalRuns => _totalRuns;
  int get totalDepth => _totalDepth;
  int get totalSolved => _totalSolved;
  int get bestStreak => _bestStreak;
  bool get soundEnabled => _soundEnabled;
  bool get hapticsEnabled => _hapticsEnabled;
  String get selectedSkin => _selectedSkin;
  Set<String> get unlockedSkins => Set.unmodifiable(_unlockedSkins);
  int get dailyStreak => _dailyStreak;
  Set<String> get claimedChests => Set.unmodifiable(_claimedChests);
  GhostRun? get bestGhost => _bestGhost;
  GhostRun? get dailyGhost => _dailyGhost;

  /// The furthest world reached, which is what gates the Bloop skins.
  int get deepestWorld => Difficulty.worldIndexFor(_bestDepth);

  int get accuracy =>
      _totalAnswered == 0 ? 0 : (_totalSolved / _totalAnswered * 100).round();

  double get averageSolveSeconds => _totalSolved == 0
      ? 0
      : _perKindSeconds.values.reduce((a, b) => a + b) / _totalSolved;

  /// Per-type performance across every run so far.
  List<KindStatSummary> get kindStats => PuzzleKind.values
      .map((kind) {
        final solved = _perKindSolved[kind.name] ?? 0;
        final total = _perKindSeconds[kind.name] ?? 0.0;
        return KindStatSummary(
          kind: kind,
          solved: solved,
          averageSeconds: solved == 0 ? 0 : total / solved,
        );
      })
      .toList(growable: false);

  /// The puzzle type the player clears most often.
  PuzzleKind? get bestPuzzleType {
    PuzzleKind? best;
    var bestCount = 0;
    for (final kind in PuzzleKind.values) {
      final n = _perKindSolved[kind.name] ?? 0;
      if (n > bestCount) {
        best = kind;
        bestCount = n;
      }
    }
    return best;
  }

  /// The puzzle type the player solves fastest, ignoring never-solved types.
  PuzzleKind? get fastestPuzzleType {
    PuzzleKind? best;
    var bestAvg = double.infinity;
    for (final stat in kindStats) {
      if (stat.solved == 0) continue;
      if (stat.averageSeconds < bestAvg) {
        best = stat.kind;
        bestAvg = stat.averageSeconds;
      }
    }
    return best;
  }

  int powerUpCount(PowerUp p) => _powerUps[p.name] ?? 0;

  /// The tray contents, in a stable order, skipping empty slots.
  List<(PowerUp, int)> get tray => PowerUp.values
      .map((p) => (p, powerUpCount(p)))
      .where((entry) => entry.$2 > 0)
      .toList(growable: false);

  // ---------------------------------------------------------------- daily

  int dailyBest(DateTime day) =>
      ((_state['dailyBest'] as Map?)?[dailyKeyFor(day)] as num?)?.toInt() ?? 0;

  bool dailyCompleted(DateTime day) => dailyBest(day) > 0;

  List<DailyEntry> dailyEntries(DateTime day) {
    final raw = ((_state['dailyEntries'] as Map?)?[dailyKeyFor(day)] as List?);
    if (raw == null) return const <DailyEntry>[];
    return raw.whereType<Map>().map(DailyEntry.fromJson).toList(growable: false);
  }

  /// True when a chest is waiting to be opened for [day].
  bool chestAvailable(DateTime day) {
    final key = dailyKeyFor(day);
    return dailyBest(day) > 0 && !_claimedChests.contains(key);
  }

  // -------------------------------------------------------------- mutation

  /// Folds a finished run into the profile and persists it.
  /// Returns the personal-best delta, or 0 when the run did not beat it.
  int recordRun(RunResult result, {required DateTime now}) {
    var delta = 0;
    if (result.depth > _bestDepth) {
      delta = result.depth - _bestDepth;
      _bestDepth = result.depth;
    }
    _totalRuns++;
    _totalDepth += result.depth;
    if (result.bestStreak > _bestStreak) _bestStreak = result.bestStreak;

    for (final record in result.records) {
      _totalAnswered++;
      if (!record.correct) continue;
      _totalSolved++;
      _perKindSolved[record.kind.name] = (_perKindSolved[record.kind.name] ?? 0) + 1;
      _perKindSeconds[record.kind.name] =
          (_perKindSeconds[record.kind.name] ?? 0) + record.seconds;
    }

    final ghost = GhostRun(
      depth: result.depth,
      crackDepths: result.records
          .where((r) => !r.correct)
          .map((r) => r.depth)
          .toList(growable: false),
      at: now,
      records: result.records
          .map(
            (r) => (kind: r.kind, depth: r.depth, correct: r.correct, seconds: r.seconds),
          )
          .toList(growable: false),
    );
    if (_bestGhost == null || result.depth > _bestGhost!.depth) {
      _bestGhost = ghost;
    }

    if (result.daily) {
      final key = dailyKeyFor(now);
      final isDailyBest = result.depth > dailyBest(now);
      if (isDailyBest) {
        _state['dailyBest'] = {...?_state['dailyBest'] as Map?, key: result.depth};
        _dailyGhost = ghost;
      }
      // dailyEntries hands back a fixed-length list, so copy before appending.
      final entries = List<DailyEntry>.of(dailyEntries(now))
        ..add(DailyEntry(depth: result.depth, at: now, wasNewBest: isDailyBest))
        ..sort((a, b) => b.depth.compareTo(a.depth));
      _state['dailyEntries'] = {
        ...?_state['dailyEntries'] as Map?,
        key: entries.take(10).map((e) => e.toJson()).toList(),
      };
      _touchDailyStreak(now);
    }

    // Bloop skins are earned by reaching each world.
    _unlockedSkins.addAll(skinUnlocksFor(_bestDepth));

    persist();
    return delta;
  }

  void _touchDailyStreak(DateTime now) {
    final today = dailyKeyFor(now);
    final yesterday = dailyKeyFor(now.subtract(const Duration(days: 1)));
    if (_lastPlayedDay == yesterday) {
      _dailyStreak++;
    } else if (_lastPlayedDay != today) {
      _dailyStreak = 1;
    }
    _lastPlayedDay = today;
  }

  void claimChest(DateTime day) {
    _claimedChests.add(dailyKeyFor(day));
    _powerUps[PowerUp.hint.name] = powerUpCount(PowerUp.hint) + 1;
    persist();
  }

  void addPowerUp(PowerUp p, [int count = 1]) {
    _powerUps[p.name] = powerUpCount(p) + count;
    persist();
  }

  void spendPowerUp(PowerUp p) {
    final next = powerUpCount(p) - 1;
    if (next <= 0) {
      _powerUps.remove(p.name);
    } else {
      _powerUps[p.name] = next;
    }
    persist();
  }

  void selectSkin(String skin) {
    if (!_unlockedSkins.contains(skin)) return;
    _selectedSkin = skin;
    persist();
  }

  void setSound(bool value) {
    _soundEnabled = value;
    persist();
  }

  void setHaptics(bool value) {
    _hapticsEnabled = value;
    persist();
  }

  void reset() {
    _state.clear();
    _bestDepth = 0;
    _totalRuns = 0;
    _totalDepth = 0;
    _totalSolved = 0;
    _totalAnswered = 0;
    _bestStreak = 0;
    _dailyStreak = 0;
    _claimedChests = <String>{};
    _perKindSolved = <String, int>{};
    _perKindSeconds = <String, double>{};
    _lastPlayedDay = null;
    _powerUps = <String, int>{};
    _bestGhost = null;
    _dailyGhost = null;
    _unlockedSkins = <String>{defaultSkin};
    _selectedSkin = defaultSkin;
    persist();
  }

  void persist() {
    _store.writeState(_key, _state);
    notifyListeners();
  }

  // ----------------------------------------------------------------- skins

  /// Skins the player has earned, in unlock order.
  static const skinCatalogue = <String, ({String name, int depth, String emoji})>{
    defaultSkin: (name: 'Classic Bloop', depth: 1, emoji: '🫧'),
    'wizard': (name: 'Wiz Bloop', depth: 11, emoji: '🧙'),
    'astronaut': (name: 'Space Bloop', depth: 26, emoji: '🧑‍🚀'),
    'pirate': (name: 'Cap\'n Bloop', depth: 51, emoji: '🏴‍☠️'),
  };

  static List<String> skinUnlocksFor(int bestDepth) => skinCatalogue.entries
      .where((e) => bestDepth >= e.value.depth)
      .map((e) => e.key)
      .toList(growable: false);

  static bool isSkinUnlocked(String skin, int bestDepth) =>
      skinUnlocksFor(bestDepth).contains(skin);

  // ------------------------------------------------------------- internals

  int _int(String key) => (_state[key] as num?)?.toInt() ?? 0;

  bool _bool(String key, {required bool fallback}) => _state[key] as bool? ?? fallback;

  Set<String> _stringSet(String key) {
    final raw = _state[key] as List?;
    if (raw == null) return <String>{};
    return raw.whereType<String>().toSet();
  }

  Map<String, int> _intMap(String key) {
    final raw = _state[key] as Map?;
    if (raw == null) return <String, int>{};
    return raw.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
  }

  Map<String, double> _doubleMap(String key) {
    final raw = _state[key] as Map?;
    if (raw == null) return <String, double>{};
    return raw.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
  }

  GhostRun? _ghost(String key) {
    final raw = _state[key];
    if (raw is! Map) return null;
    return GhostRun.fromJson(raw);
  }
}

/// A read-only view of one puzzle type's lifetime performance.
class KindStatSummary {
  const KindStatSummary({
    required this.kind,
    required this.solved,
    required this.averageSeconds,
  });

  final PuzzleKind kind;
  final int solved;
  final double averageSeconds;
}
