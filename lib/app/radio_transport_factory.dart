import '../obd/adapter_config.dart';
import '../obd/transport/native_link_transport.dart';
import '../obd/transport/transport.dart';
import '../obd/transport/wifi_transport.dart';
import '../obd/transport_factory.dart';
import '../platform/adapter_radio.dart';

/// The real transports: a socket for a WiFi adapter (behind the network guard) and
/// a link over the phone's Bluetooth radio for the others.
class RadioTransportFactory implements TransportFactory {
  RadioTransportFactory({AdapterRadio Function(RadioKind kind)? radios})
    : _radios = radios ?? AdapterRadio.new;

  final AdapterRadio Function(RadioKind kind) _radios;
  final Map<RadioKind, AdapterRadio> _made = {};

  /// The radio for [kind], made once and shared: the pairing screen and the drive
  /// use the same channel.
  AdapterRadio radio(RadioKind kind) =>
      _made.putIfAbsent(kind, () => _radios(kind));

  @override
  Transport create(AdapterConfig config) => switch (config.kind) {
    AdapterKind.wifi => WifiTransport(
      host: config.address,
      port: config.port ?? defaultWifiPort,
    ),
    AdapterKind.bluetoothClassic => NativeLinkTransport(
      radio(RadioKind.bluetoothClassic).link(config.address),
    ),
    AdapterKind.ble => NativeLinkTransport(
      radio(RadioKind.ble).link(config.address),
    ),
  };
}
