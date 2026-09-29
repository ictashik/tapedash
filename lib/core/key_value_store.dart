/// Small settings that outlive the app (CLAUDE.md 5: `shared_preferences` on the
/// phone, this in tests). Domain code takes one and never a plugin.
abstract interface class KeyValueStore {
  Future<double?> getDouble(String key);
  Future<void> setDouble(String key, double value);
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<bool?> getBool(String key);
  Future<void> setBool(String key, bool value);
  Future<void> remove(String key);
}

/// A [KeyValueStore] in memory, for tests.
class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, Object> _values = {};

  @override
  Future<double?> getDouble(String key) async => _values[key] as double?;

  @override
  Future<void> setDouble(String key, double value) async =>
      _values[key] = value;

  @override
  Future<String?> getString(String key) async => _values[key] as String?;

  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;

  @override
  Future<bool?> getBool(String key) async => _values[key] as bool?;

  @override
  Future<void> setBool(String key, bool value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);
}
