import 'dart:async';

import 'package:tapedash/obd/transport/transport.dart';

/// A transport that hands what it receives to its listeners a microtask later,
/// as a real one does when the platform delivers on the event loop. It wraps
/// another, which delivers at once.
///
/// Whatever is written goes straight through, so a caller sees state changes
/// and data arrive after the call that caused them has returned.
class AsyncTransport implements Transport {
  AsyncTransport(this._inner) {
    _subscriptions
      ..add(
        _inner.incoming.listen(
          (piece) => scheduleMicrotask(() {
            if (!_incoming.isClosed) _incoming.add(piece);
          }),
        ),
      )
      ..add(
        _inner.state.listen(
          (state) => scheduleMicrotask(() {
            if (!_states.isClosed) _states.add(state);
          }),
        ),
      );
  }

  final Transport _inner;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final StreamController<String> _incoming =
      StreamController<String>.broadcast();
  final StreamController<TransportState> _states =
      StreamController<TransportState>.broadcast();

  @override
  TransportState get currentState => _inner.currentState;

  @override
  Stream<TransportState> get state => _states.stream;

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  Future<void> connect() => _inner.connect();

  @override
  Future<void> disconnect() => _inner.disconnect();

  @override
  Future<void> write(String data) => _inner.write(data);

  Future<void> dispose() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await _incoming.close();
    await _states.close();
  }
}
