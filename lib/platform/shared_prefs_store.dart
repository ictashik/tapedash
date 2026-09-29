import 'package:shared_preferences/shared_preferences.dart';

import '../core/key_value_store.dart';

/// [KeyValueStore] on `shared_preferences` (CLAUDE.md 5), which is the phone's own
/// settings file: nothing leaves it.
class SharedPrefsStore implements KeyValueStore {
  SharedPrefsStore(this._prefs);

  final SharedPreferencesAsync _prefs;

  /// The store for the app.
  factory SharedPrefsStore.instance() =>
      SharedPrefsStore(SharedPreferencesAsync());

  @override
  Future<double?> getDouble(String key) => _prefs.getDouble(key);

  @override
  Future<void> setDouble(String key, double value) =>
      _prefs.setDouble(key, value);

  @override
  Future<String?> getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<bool?> getBool(String key) => _prefs.getBool(key);

  @override
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}
