import 'dart:async';

import 'native_link.dart';
import 'transport.dart';

/// A [Transport] over a [NativeLink]: Bluetooth Classic or BLE, whichever gave
/// the link. What differs between the radios is all in the link; the states, the
/// failures and the cancelling of a connect are the same, and are here once.
class NativeLinkTransport implements Transport, LinkDiagnostics {
  NativeLinkTransport(
    this._link, {
    this.openTimeout = const Duration(seconds: 75),
  }) {
    _incoming = _link.incoming.listen(_incomingController.add);
    _lost = _link.lost.listen((_) => _onLost());
    _diag = _link.diagnostics.listen(_diagController.add);
  }

  final NativeLink _link;

  /// The longest a connection may take before it is given up as failed. The radio
  /// has limits of its own (a BLE open is over in 40 s, a Classic one in about 30);
  /// this is for the case where it never answers at all, so that the session is not
  /// left waiting on a native call for ever.
  final Duration openTimeout;
  late final StreamSubscription<String> _incoming;
  late final StreamSubscription<void> _lost;
  late final StreamSubscription<String> _diag;

  final StreamController<String> _diagController =
      StreamController<String>.broadcast(sync: true);

  @override
  Stream<String> get diagnostics => _diagController.stream;

  final StreamController<String> _incomingController =
      StreamController<String>.broadcast(sync: true);
  final StreamController<TransportState> _states =
      StreamController<TransportState>.broadcast(sync: true);

  TransportState _current = const TransportState.disconnected();
  int _generation = 0;

  /// Why the last connect failed, if it did, for the screen that asked.
  NativeLinkProblem? lastProblem;

  @override
  TransportState get currentState => _current;

  @override
  Stream<TransportState> get state => _states.stream;

  @override
  Stream<String> get incoming => _incomingController.stream;

  void _set(TransportState next) {
    if (next == _current) return;
    _current = next;
    _states.add(next);
  }

  @override
  Future<void> connect() async {
    if (_current.status != TransportStatus.disconnected) return;
    final generation = ++_generation;
    lastProblem = null;
    _set(TransportState.connecting);
    try {
      await _link.open().timeout(
        openTimeout,
        onTimeout: () {
          unawaited(_link.close());
          throw const NativeLinkException(
            NativeLinkProblem.connectFailed,
            'The radio did not answer',
          );
        },
      );
    } on NativeLinkException catch (error) {
      if (generation != _generation) {
        throw const TransportException(TransportFailure.cancelled);
      }
      lastProblem = error.problem;
      const failure = TransportFailure.unreachable;
      _diagController.add(
        'connect failed: ${error.problem.name}'
        '${error.message == null ? '' : ' (${error.message})'}',
      );
      _set(const TransportState.disconnected(failure: failure));
      throw TransportException(failure, error.message ?? error.problem.name);
    } on Object catch (error) {
      if (generation != _generation) {
        throw const TransportException(TransportFailure.cancelled);
      }
      lastProblem = NativeLinkProblem.other;
      const failure = TransportFailure.unreachable;
      _diagController.add('connect failed: $error');
      _set(const TransportState.disconnected(failure: failure));
      throw TransportException(failure, '$error');
    }
    if (generation != _generation) {
      // A disconnect came while this was being made: close what it made.
      unawaited(_link.close());
      throw const TransportException(TransportFailure.cancelled);
    }
    _set(TransportState.connected);
  }

  void _onLost() {
    if (!_current.isConnected) return;
    _diagController.add('the link was lost');
    _generation++;
    _set(const TransportState.disconnected(failure: TransportFailure.lost));
  }

  @override
  Future<void> disconnect() async {
    _generation++;
    final was = _current;
    if (was.status != TransportStatus.disconnected || was.failure != null) {
      _set(const TransportState.disconnected());
    }
    try {
      await _link.close();
    } on Object {
      // Nothing left to close.
    }
  }

  @override
  Future<void> write(String data) async {
    if (!_current.isConnected) {
      throw const TransportException(TransportFailure.notConnected);
    }
    try {
      await _link.send(data);
    } on Object catch (error) {
      _onLost();
      throw TransportException(TransportFailure.lost, '$error');
    }
  }

  /// Lets go of everything, for good.
  Future<void> dispose() async {
    await disconnect();
    await _incoming.cancel();
    await _lost.cancel();
    await _diag.cancel();
    await _diagController.close();
    await _incomingController.close();
    await _states.close();
  }
}
