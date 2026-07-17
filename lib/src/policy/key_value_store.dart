import 'package:shared_preferences/shared_preferences.dart';

/// Minimal persistence the policies need, behind an interface so tests use
/// [InMemoryKeyValueStore] and consumers could swap the backend (ADR-P2).
abstract interface class KeyValueStore {
  /// Reads an int, or null if absent.
  Future<int?> getInt(String key);

  /// Writes an int.
  Future<void> setInt(String key, int value);

  /// Reads an int list (e.g. impression timestamps), empty if absent.
  Future<List<int>> getHistory(String key);

  /// Replaces an int list.
  Future<void> setHistory(String key, List<int> values);
}

/// [KeyValueStore] backed by `shared_preferences` (`SharedPreferencesAsync`).
///
/// All keys are namespaced with `ad_flow.` to avoid colliding with the
/// host app's preferences.
class SharedPrefsKeyValueStore implements KeyValueStore {
  /// Creates a store; [prefs] is injectable for tests.
  SharedPrefsKeyValueStore({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  String _k(String key) => 'ad_flow.$key';

  @override
  Future<int?> getInt(String key) async {
    // TYPE-corrupt data (another writer stored a string under our key, or a
    // backend migration mangled it) makes SharedPreferencesAsync.getInt
    // THROW, not return null — and a throwing read propagates into every
    // frequency-cap check, blocking every full-screen show with no self-heal
    // (2026-07 audit). Corrupt persistence is garbage, not an error: read it
    // as absent; the next impression's write overwrites and self-heals.
    try {
      return await _prefs.getInt(_k(key));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setInt(String key, int value) => _prefs.setInt(_k(key), value);

  @override
  Future<List<int>> getHistory(String key) async {
    // See getInt: a type-corrupt entry must read as absent, never throw.
    try {
      final raw = await _prefs.getStringList(_k(key));
      if (raw == null) return const [];
      return [for (final entry in raw) ?int.tryParse(entry)];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> setHistory(String key, List<int> values) =>
      _prefs.setStringList(_k(key), [for (final value in values) '$value']);
}

/// In-memory [KeyValueStore] for tests (and consumers' tests).
class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, int> _ints = {};
  final Map<String, List<int>> _histories = {};

  @override
  Future<int?> getInt(String key) async => _ints[key];

  @override
  Future<void> setInt(String key, int value) async => _ints[key] = value;

  @override
  Future<List<int>> getHistory(String key) async =>
      List.unmodifiable(_histories[key] ?? const []);

  @override
  Future<void> setHistory(String key, List<int> values) async =>
      _histories[key] = List.of(values);
}
