import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/radio_transport_factory.dart';
import 'package:tapedash/obd/adapter_config.dart';
import 'package:tapedash/obd/transport/native_link_transport.dart';
import 'package:tapedash/obd/transport/transport.dart';
import 'package:tapedash/obd/transport/wifi_transport.dart';
import 'package:tapedash/platform/adapter_radio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each kind of adapter gets its own kind of transport', () {
    final factory = RadioTransportFactory();
    final wifi = factory.create(
      const AdapterConfig(kind: AdapterKind.wifi, address: '192.168.0.10'),
    );
    final classic = factory.create(
      const AdapterConfig(
        kind: AdapterKind.bluetoothClassic,
        address: '00:1D:A5:00:00:01',
      ),
    );
    final ble = factory.create(
      const AdapterConfig(kind: AdapterKind.ble, address: 'AA:BB:CC:DD:EE:FF'),
    );
    expect(wifi, isA<WifiTransport>());
    expect((wifi as WifiTransport).host, '192.168.0.10');
    expect(wifi.port, defaultWifiPort);
    expect(classic, isA<NativeLinkTransport>());
    expect(ble, isA<NativeLinkTransport>());
    for (final t in [wifi, classic, ble]) {
      expect(t.currentState.status, TransportStatus.disconnected);
    }
  });

  test('a WiFi adapter keeps its own port', () {
    final wifi =
        RadioTransportFactory().create(
              const AdapterConfig(
                kind: AdapterKind.wifi,
                address: '10.0.2.2',
                port: 35001,
              ),
            )
            as WifiTransport;
    expect(wifi.port, 35001);
  });

  test('a radio is made once per kind and shared', () {
    var made = 0;
    final factory = RadioTransportFactory(
      radios: (kind) {
        made++;
        return AdapterRadio(kind);
      },
    );
    expect(
      identical(factory.radio(RadioKind.ble), factory.radio(RadioKind.ble)),
      isTrue,
    );
    factory.radio(RadioKind.bluetoothClassic);
    factory.create(const AdapterConfig(kind: AdapterKind.ble, address: 'AA'));
    expect(made, 2);
  });
}
