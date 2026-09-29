import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tapedash/core/key_value_store.dart';
import 'package:tapedash/platform/shared_prefs_store.dart';

void contract(String name, KeyValueStore Function() make) {
  group(name, () {
    late KeyValueStore store;
    setUp(() => store = make());

    test('a value that was never set is null', () async {
      expect(await store.getDouble('a'), isNull);
      expect(await store.getString('a'), isNull);
      expect(await store.getBool('a'), isNull);
    });

    test('values come back as they went in', () async {
      await store.setDouble('d', 102.5);
      await store.setString('s', 'INR');
      await store.setBool('b', true);
      expect(await store.getDouble('d'), 102.5);
      expect(await store.getString('s'), 'INR');
      expect(await store.getBool('b'), isTrue);
    });

    test('remove forgets one', () async {
      await store.setDouble('d', 1);
      await store.remove('d');
      expect(await store.getDouble('d'), isNull);
    });
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  contract('memory store', MemoryKeyValueStore.new);
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  contract('shared_preferences store', () {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    return SharedPrefsStore.instance();
  });
}
