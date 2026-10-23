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

    test('a fresh one has no adapter and no source: the app asks', () async {
      await adapters.load();
      expect(adapters.adapter.value, isNull);
      expect(adapters.source.value, isNull);
      expect(adapters.compatibilityMode.value, isFalse);
      expect(adapters.recordSessions.value, isFalse);
    });

    test('choosing an adapter remembers it, and makes it the source', () async {
      await adapters.choose(_bt);
      expect(adapters.adapter.value, _bt);
      expect(adapters.source.value, DriveSource.obd);

      final again = AdapterStore(store);
      await again.load();
      expect(again.adapter.value, _bt);
      expect(again.source.value, DriveSource.obd);
    });

    test('forgetting the adapter leaves no source, not another one', () async {
      await adapters.choose(_bt);
      final memory = await adapters.memoryFor(_bt);
      memory.protocol = '6';
      await Future<void>.delayed(Duration.zero);

      await adapters.forget();
      expect(adapters.adapter.value, isNull);
      expect(adapters.source.value, isNull);
      expect((await adapters.memoryFor(_bt)).protocol, isNull);
      final again = AdapterStore(store);
      await again.load();
      expect(again.adapter.value, isNull);
      expect(again.source.value, isNull);
    });

    test('forgetting the adapter leaves the GPS source as it was', () async {
      await adapters.choose(_bt);
      await adapters.setSource(DriveSource.gps);
      await adapters.forget();
      expect(adapters.source.value, DriveSource.gps);
      final again = AdapterStore(store);
      await again.load();
      expect(again.source.value, DriveSource.gps);
    });

    test('the GPS can be the source without forgetting the adapter', () async {
      await adapters.choose(_wifi);
      await adapters.setSource(DriveSource.gps);
      expect(adapters.source.value, DriveSource.gps);
      expect(adapters.adapter.value, _wifi);
      await adapters.setSource(DriveSource.obd);
      expect(adapters.source.value, DriveSource.obd);

      await adapters.setSource(DriveSource.gps);
      final again = AdapterStore(store);
      await again.load();
      expect(again.source.value, DriveSource.gps);
      expect(again.adapter.value, _wifi);
    });

    test('the GPS can be the first and only choice', () async {
      await adapters.setSource(DriveSource.gps);
      expect(adapters.source.value, DriveSource.gps);
      expect(adapters.adapter.value, isNull);
    });

    test('with no adapter the car cannot be the source', () async {
      await adapters.setSource(DriveSource.obd);
      expect(adapters.source.value, isNull);
    });

    test('builds from before the source was a setting: a chosen adapter is used, '
        'even if the old demo switch had been left on', () async {
      await store.setString(
        'adapter_config',
        '{"kind":"bluetoothClassic","address":"00:1D:A5:00:00:01","name":"OBDII"}',
      );
      await store.setBool('adapter_use_live', false);
      await adapters.load();
      expect(adapters.adapter.value, _bt);
      expect(adapters.source.value, DriveSource.obd);
    });

    test('a stored OBD source with no adapter is no source', () async {
      await store.setString('drive_source', 'obd');
      await adapters.load();
      expect(adapters.source.value, isNull);
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

    test(
      'a debug build records until told not to, and the choice wins',
      () async {
        final debug = AdapterStore(store, recordByDefault: true);
        await debug.load();
        expect(debug.recordSessions.value, isTrue);

        await debug.setRecordSessions(false);
        final again = AdapterStore(store, recordByDefault: true);
        await again.load();
        expect(
          again.recordSessions.value,
          isFalse,
          reason: 'chosen off in Garage',
        );
      },
    );

    test('a damaged setting is no adapter, not a crash', () async {
      await store.setString('adapter_config', '{not json');
      await adapters.load();
      expect(adapters.adapter.value, isNull);
    });
  });
}

const _btAddress = '00:1D:A5:00:00:01';
