import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';

/// A tiny string key/value store.
///
/// The game persists exactly one JSON document, so the surface is kept to two
/// methods. That indirection is what lets the engine be unit tested without a
/// platform channel, and leaves room to swap in a different backend later.
abstract class KeyValueStore {
  String? readString(String key);

  Future<void> writeString(String key, String value);

  /// Loads a stored state, or an empty map on first launch.
  Map<String, dynamic> readState(String key) {
    final raw = readString(key);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // Corrupt payload: start clean rather than trapping the player.
    }
    return <String, dynamic>{};
  }

  Future<void> writeState(String key, Map<String, dynamic> state) =>
      writeString(key, jsonEncode(state));
}

/// Hive-backed store. Hive is used because it works unchanged on web
/// (IndexedDB) and on device (a file), which a `dart:io`-only store would not.
class HiveStore extends KeyValueStore {
  HiveStore(this._box);

  static const String boxName = 'sinkhole';

  final Box<String> _box;

  static Future<HiveStore> open() async {
    await Hive.initFlutter();
    final box = await Hive.openBox<String>(boxName);
    return HiveStore(box);
  }

  @override
  String? readString(String key) => _box.get(key);

  @override
  Future<void> writeString(String key, String value) => _box.put(key, value);
}

/// In-memory store for tests and for the first frame before Hive is ready.
class MemoryStore extends KeyValueStore {
  MemoryStore([Map<String, String>? initial]) : _data = <String, String>{...?initial};

  final Map<String, String> _data;

  @override
  String? readString(String key) => _data[key];

  @override
  Future<void> writeString(String key, String value) async => _data[key] = value;
}
