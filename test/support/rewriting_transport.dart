import 'dart:async';

import 'package:tapedash/obd/transport/transport.dart';

/// A [Transport] that passes everything through to another, but lets a test
/// change what comes back: to give an adapter a fault the simulator does not
/// have, such as printing frames in a format nobody expected, or resetting
/// itself.
class RewritingTransport implements Transport {
  RewritingTransport(this._inner, this.rewrite) {
    _subscription = _inner.incoming.listen((text) {
      final out = rewrite(text);
      if (out != null && !_incoming.isClosed) _incoming.add(out);
    });
  }

  final Transport _inner;

  /// What to do with each piece received: the text to pass on, or null to drop
  /// it.
  String? Function(String text) rewrite;

  late final StreamSubscription<String> _subscription;
  final StreamController<String> _incoming = StreamController<String>.broadcast(
    sync: true,
  );

  @override
  TransportState get currentState => _inner.currentState;

  @override
  Stream<TransportState> get state => _inner.state;

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Future<void> connect() => _inner.connect();

  @override
  Future<void> disconnect() => _inner.disconnect();

  @override
  Future<void> write(String data) => _inner.write(data);

  Future<void> dispose() async {
    await _subscription.cancel();
    await _incoming.close();
  }
}
