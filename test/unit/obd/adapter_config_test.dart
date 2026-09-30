import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/key_value_store.dart';
import 'package:tapedash/obd/adapter_config.dart';

const _bt = AdapterConfig(
  kind: AdapterKind.bluetoothClassic,
  address: '00:1D:A5:00:00:01',
  name: 'OBDII',
);
const _wifi = AdapterConfig(
  kind: AdapterKind.wifi,
  address: '192.168.0.10',
  port: 35000,
);

void main() {
  group('AdapterConfig', () {
    test('it round-trips through JSON', () {
      for (final c in [_bt, _wifi]) {
        expect(AdapterConfig.fromJson(c.toJson()), c);
      }
      expect(_wifi.toJson()['port'], 35000);
      expect(_bt.toJson().containsKey('port'), isFalse);
    });

    test('a broken one is null, not a crash', () {
      expect(AdapterConfig.fromJson(null), isNull);
      expect(AdapterConfig.fromJson('x'), isNull);
      expect(AdapterConfig.fromJson({'kind': 'wifi'}), isNull);
      expect(AdapterConfig.fromJson({'kind': 'nope', 'address': 'a'}), isNull);
      expect(AdapterConfig.fromJson({'kind': 'wifi', 'address': ''}), isNull);
      expect(
        AdapterConfig.fromJson({'kind': 'ble', 'address': 'AA', 'name': 5}),
        const AdapterConfig(kind: AdapterKind.ble, address: 'AA'),
      );
    });

    test('a nameless adapter is called by its address', () {
      expect(_bt.displayName, 'OBDII');
      expect(_wifi.displayName, '192.168.0.10');
    });

    test('the id tells adapters apart, and is the same for the same one', () {
      expect(_bt.id, 'bluetoothClassic:00:1D:A5:00:00:01');
      expect(_wifi.id, 'wifi:192.168.0.10:35000');
      expect(
        const AdapterConfig(kind: AdapterKind.wifi, address: '192.168.0.10').id,
        _wifi.id,
        reason: 'the usual port is the default',
      );
      expect(
        const AdapterConfig(kind: AdapterKind.ble, address: _btAddress).id,
        isNot(
          const AdapterConfig(
            kind: AdapterKind.bluetoothClassic,
            address: _btAddress,
          ).id,
        ),
      );
    });
  });

  group('AdapterStore', () {
    late MemoryKeyValueStore store;
    late AdapterStore adapters;

    setUp(() {
      store = MemoryKeyValueStore();
      adapters = AdapterStore(store);
    });

    test('a fresh one has no adapter and uses the demo', () async {
      await adapters.load();
      expect(adapters.adapter.value, isNull);
      expect(adapters.useAdapter.value, isFalse);
      expect(adapters.compatibilityMode.value, isFalse);
      expect(adapters.recordSessions.value, isFalse);
    });

    test('choosing an adapter remembers it, and switches to it', () async {
      await adapters.choose(_bt);
      expect(adapters.adapter.value, _bt);
      expect(adapters.useAdapter.value, isTrue);

      final again = AdapterStore(store);
      await again.load();
      expect(again.adapter.value, _bt);
      expect(again.useAdapter.value, isTrue);
    });

    test(
      'forgetting goes back to the demo, and forgets its protocol',
      () async {
        await adapters.choose(_bt);
        final memory = await adapters.memoryFor(_bt);
        memory.protocol = '6';
        await Future<void>.delayed(Duration.zero);

        await adapters.forget();
        expect(adapters.adapter.value, isNull);
        expect(adapters.useAdapter.value, isFalse);
        expect((await adapters.memoryFor(_bt)).protocol, isNull);
        final again = AdapterStore(store);
        await again.load();
        expect(again.adapter.value, isNull);
        expect(again.useAdapter.value, isFalse);
      },
    );

    test('the demo can be used without forgetting the adapter', () async {
      await adapters.choose(_wifi);
      await adapters.setUseAdapter(false);
      expect(adapters.useAdapter.value, isFalse);
      expect(adapters.adapter.value, _wifi);
      await adapters.setUseAdapter(true);
      expect(adapters.useAdapter.value, isTrue);
    });

    test('with no adapter there is nothing to use', () async {
      await adapters.setUseAdapter(true);
      expect(adapters.useAdapter.value, isFalse);
    });

    test('the protocol is remembered per adapter', () async {
      final a = await adapters.memoryFor(_bt);
      final b = await adapters.memoryFor(_wifi);
      expect(a.protocol, isNull);
      a.protocol = '6';
      b.protocol = '3';
      await Future<void>.delayed(Duration.zero);

      expect((await adapters.memoryFor(_bt)).protocol, '6');
      expect((await adapters.memoryFor(_wifi)).protocol, '3');
      a.protocol = null;
      await Future<void>.delayed(Duration.zero);
      expect((await adapters.memoryFor(_bt)).protocol, isNull);
    });

    test('compatibility mode and recording are remembered', () async {
      await adapters.setCompatibilityMode(true);
      await adapters.setRecordSessions(true);
      final again = AdapterStore(store);
      await again.load();
      expect(again.compatibilityMode.value, isTrue);
      expect(again.recordSessions.value, isTrue);
    });

    test('a damaged setting is no adapter, not a crash', () async {
      await store.setString('adapter_config', '{not json');
      await adapters.load();
      expect(adapters.adapter.value, isNull);
    });
  });
}

const _btAddress = '00:1D:A5:00:00:01';
