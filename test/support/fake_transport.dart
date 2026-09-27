import 'dart:async';

import 'package:tapedash/core/clock.dart';
import 'package:tapedash/obd/transport/transport.dart';

/// A transport a test drives by hand: it records what is written and delivers
/// whatever pieces the test says, at the moment the test says. Like the
/// simulator's transport, it delivers synchronously.
class FakeTransport implements Transport {
  FakeTransport({this.clock, bool connected = true})
    : _current = connected
          ? TransportState.connected
          : const TransportState.disconnected();

  /// If given, each write is stamped with the clock's monotonic time.
  final Clock? clock;

  TransportState _current;
  final StreamController<String> _incoming = StreamController<String>.broadcast(
    sync: true,
  );
  final StreamController<TransportState> _states =
      StreamController<TransportState>.broadcast(sync: true);

  /// When set, writes fail as a transport with a dying link does, while it
  /// still says it is connected.
  bool failWrites = false;

  /// Everything written, in order.
  final List<String> writes = [];

  /// When each write happened, if a clock was given.
  final List<Duration> writeTimes = [];

  @override
  TransportState get currentState => _current;

  @override
  Stream<TransportState> get state => _states.stream;

  @override
  Stream<String> get incoming => _incoming.stream;

  /// What the adapter sends: a piece of text arriving now.
  void receive(String piece) => _incoming.add(piece);

  /// Moves the link to [next] and says so.
  void setState(TransportState next) {
    if (next == _current) return;
    _current = next;
    _states.add(next);
  }

  @override
  Future<void> connect() {
    setState(TransportState.connected);
    return Future<void>.value();
  }

  @override
  Future<void> disconnect() {
    setState(const TransportState.disconnected());
    return Future<void>.value();
  }

  @override
  Future<void> write(String data) {
    if (!_current.isConnected || failWrites) {
      return Future<void>.error(
        const TransportException(
          TransportFailure.notConnected,
          'not connected',
        ),
      );
    }
    writes.add(data);
    final c = clock;
    if (c != null) writeTimes.add(c.monotonic());
    return Future<void>.value();
  }

  Future<void> dispose() async {
    await _incoming.close();
    await _states.close();
  }
}
