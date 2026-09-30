import 'adapter_config.dart';
import 'transport/transport.dart';

/// Makes the [Transport] for an adapter the user chose. The real one is in
/// `lib/app/`, where the platform channels are; a test gives one that makes a
/// simulated adapter.
abstract interface class TransportFactory {
  Transport create(AdapterConfig config);
}
