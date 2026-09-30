import '../obd/adapter_checker.dart';
import '../obd/adapter_config.dart';
import '../obd/transport/wifi_transport.dart';
import '../obd/transport_factory.dart';

/// [AdapterChecker] over the real transports: the network guard for the address,
/// and a connect for the test.
class TransportAdapterChecker implements AdapterChecker {
  const TransportAdapterChecker(this._transports);

  final TransportFactory _transports;

  @override
  bool allows(String host) => NetworkGuard.allows(host);

  @override
  Future<bool> reachable(AdapterConfig config) async {
    final transport = _transports.create(config);
    try {
      await transport.connect();
      return true;
    } on Object {
      return false;
    } finally {
      await transport.disconnect();
    }
  }
}
