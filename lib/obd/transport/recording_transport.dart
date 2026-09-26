import 'dart:async';

import '../../core/clock.dart';
import 'session_log.dart';
import 'transport.dart';

/// A [Transport] that passes everything to another and writes it down
/// (CLAUDE.md 10, Recordings).
///
/// The log has each command sent, each piece received and each change of state,
/// with the time of each. Recording the simulator gives the files that
/// `tool/record_sim.dart` makes; recording a real adapter in a real car gives
/// the logs that become regression tests after the hardware handoff.
class RecordingTransport implements Transport {
  RecordingTransport(
    this._inner, {
    required Clock clock,
    Map<String, String> header = const {},
  }) : _clock = clock,
       _header = Map.of(header),
       _start = clock.monotonic() {
    _subscriptions
      ..add(_inner.incoming.listen(_onIncoming))
      ..add(_inner.state.listen(_onState));
  }

  final Transport _inner;
  final Clock _clock;
  final Map<String, String> _header;
  final Duration _start;

  final List<SessionEntry> _entries = [];
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final StreamController<String> _incoming = StreamController<String>.broadcast(
    sync: true,
  );
  final StreamController<TransportState> _states =
      StreamController<TransportState>.broadcast(sync: true);

  /// What has been recorded so far.
  SessionLog get log =>
      SessionLog(header: _header, entries: List.unmodifiable(_entries));

  void _add(SessionDirection direction, String text) {
    _entries.add(SessionEntry(_clock.monotonic() - _start, direction, text));
  }

  void _onIncoming(String text) {
    _add(SessionDirection.received, text);
    if (!_incoming.isClosed) _incoming.add(text);
  }

  void _onState(TransportState state) {
    _add(SessionDirection.event, state.toString());
    if (!_states.isClosed) _states.add(state);
  }

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
  Future<void> write(String data) {
    _add(SessionDirection.sent, data);
    return _inner.write(data);
  }

  /// Stops recording and listening. It does not close the transport inside.
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _incoming.close();
    await _states.close();
  }
}
