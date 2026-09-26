import 'dart:async';

import '../../core/scheduler.dart';
import '../../sim/adapter_quirks.dart';
import '../../sim/ecu.dart';
import '../../sim/elm327_device.dart';
import '../../sim/elm327_simulator.dart';
import '../../sim/scenario_events.dart';
import '../../sim/simulated_car.dart';
import 'transport.dart';

/// A [Transport] to an adapter that is plugged into a [SimulatedCar]
/// (CLAUDE.md 7.5).
///
/// It is the link, the adapter and the car's ECU in one, all on the given
/// [Scheduler], so on a fake clock a 30-minute drive takes a moment. The
/// adapter's quirks come from the scenario unless given, and so do the link
/// faults. To keep one adapter across several links, as a real adapter that
/// stays plugged in does, pass it as [adapter]: an `AdapterDisconnect` drops the link at its time in the drive, and
/// nothing can connect until its outage is over.
///
/// The car is not started here. Start it on the same scheduler; this only asks
/// it questions.
///
/// Output is delivered synchronously, from the scheduled task that produces
/// it, so a listener reads the clock at the true moment each piece arrived.
class SimTransport implements Transport {
  SimTransport({
    required this.car,
    required this.scheduler,
    AdapterQuirks? quirks,
    this.connectDelay = const Duration(milliseconds: 400),
    int seed = 1,
    String version = 'ELM327 v1.5',
    Elm327Simulator? adapter,
  }) {
    this.adapter =
        adapter ??
        Elm327Simulator(
          ecu: SimulatedEcu(car: car),
          quirks: quirks ?? car.scenario.quirks,
          version: version,
          seed: seed,
        );
    _device = Elm327Device(
      simulator: this.adapter,
      scheduler: scheduler,
      seed: seed,
      onOutput: _deliver,
    );
  }

  final SimulatedCar car;
  final Scheduler scheduler;

  /// How long connecting takes, when it works.
  final Duration connectDelay;

  /// The adapter, for a test that wants to see its state. Its settings last
  /// as long as this object does, across connections, as a real adapter's do
  /// while it stays plugged in.
  late final Elm327Simulator adapter;
  late final Elm327Device _device;

  final StreamController<String> _incoming = StreamController<String>.broadcast(
    sync: true,
  );
  final StreamController<TransportState> _states =
      StreamController<TransportState>.broadcast(sync: true);

  TransportState _current = const TransportState.disconnected();
  Completer<void>? _connecting;
  ScheduledTask? _connectTask;
  ScheduledTask? _watchdog;

  /// How often the link is checked against the scenario's faults.
  static const Duration _watchInterval = Duration(milliseconds: 50);

  /// How many commands have been written while another was still being
  /// answered. It stays at zero for an app that waits for the prompt.
  int get overlappedCommands => _device.overlappedCommands;

  @override
  TransportState get currentState => _current;

  @override
  Stream<TransportState> get state => _states.stream;

  @override
  Stream<String> get incoming => _incoming.stream;

  /// Whether the scenario has the link down at this moment of the drive.
  bool get isInOutage {
    final now = car.elapsedSeconds;
    for (final fault in car.scenario.adapterFaults) {
      if (fault is AdapterDisconnect) {
        final start = fault.at.inMicroseconds / 1e6;
        final end = start + fault.outage.inMicroseconds / 1e6;
        if (now >= start && now < end) return true;
      }
    }
    return false;
  }

  void _set(TransportState next) {
    if (next == _current) return;
    _current = next;
    if (!_states.isClosed) _states.add(next);
  }

  @override
  Future<void> connect() {
    if (_current.isConnected) return Future<void>.value();
    final pending = _connecting;
    if (pending != null) return pending.future;

    final completer = Completer<void>();
    _connecting = completer;
    _set(TransportState.connecting);
    _connectTask = scheduler.runAfter(connectDelay, () {
      _connectTask = null;
      _connecting = null;
      if (isInOutage) {
        _set(
          const TransportState.disconnected(
            failure: TransportFailure.unreachable,
          ),
        );
        completer.completeError(
          const TransportException(
            TransportFailure.unreachable,
            'the adapter did not answer',
          ),
        );
        return;
      }
      _device.linkOpened();
      _set(TransportState.connected);
      _watchdog = scheduler.runEvery(_watchInterval, _watch);
      completer.complete();
    });
    return completer.future;
  }

  /// Drops the link when the scenario says it goes.
  void _watch() {
    if (isInOutage) _drop(TransportFailure.lost);
  }

  void _drop(TransportFailure? failure) {
    _watchdog?.cancel();
    _watchdog = null;
    _device.linkClosed();
    _set(TransportState.disconnected(failure: failure));
  }

  @override
  Future<void> disconnect() {
    final pending = _connecting;
    if (pending != null) {
      _connectTask?.cancel();
      _connectTask = null;
      _connecting = null;
      pending.completeError(
        const TransportException(
          TransportFailure.cancelled,
          'disconnected while connecting',
        ),
      );
      _set(const TransportState.disconnected());
    } else if (_current.isConnected) {
      _drop(null);
    }
    return Future<void>.value();
  }

  @override
  Future<void> write(String data) {
    if (!_current.isConnected) {
      return Future<void>.error(
        const TransportException(
          TransportFailure.notConnected,
          'write with no link',
        ),
      );
    }
    _device.receive(data);
    return Future<void>.value();
  }

  void _deliver(String text) {
    if (_current.isConnected && !_incoming.isClosed) _incoming.add(text);
  }

  /// Stops everything and closes the streams. The transport cannot be used
  /// again.
  Future<void> dispose() async {
    _connectTask?.cancel();
    _connectTask = null;
    _watchdog?.cancel();
    _watchdog = null;
    _device.linkClosed();
    final pending = _connecting;
    _connecting = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        const TransportException(TransportFailure.cancelled, 'disposed'),
      );
    }
    await _incoming.close();
    await _states.close();
  }
}
