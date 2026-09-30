import 'dart:async';

import '../core/clock.dart';
import '../core/observable.dart';
import '../core/scheduler.dart';
import '../obd/adapter_config.dart';
import '../obd/obd_session.dart';
import '../obd/transport/recording_transport.dart';
import '../obd/transport/session_sink.dart';
import '../obd/transport/transport.dart';
import '../obd/transport_factory.dart';
import '../vehicle/vehicle_state.dart';
import 'drive_feed.dart';

/// A real car, on a real adapter (CLAUDE.md 7, 8.1): the same OBD stack the demo
/// drive uses, over the transport for the adapter the user chose. What it fills is
/// the [vehicle] the whole UI reads, so nothing else in the app changes.
///
/// The session finds the adapter, starts it up, and, if the link drops, opens it
/// again after 1, 2, 4 and 8 seconds and then every 10 (`ObdSession`), so a phone
/// that goes out of range or an adapter that is unplugged comes back by itself.
///
/// With [recordSessions] the raw traffic is written to [sink] as it happens (every
/// [flushEvery], and when the drive stops), so that a drive that ends in a crash or
/// an unplugged phone still leaves its log behind.
class LiveDrive implements DriveFeed {
  LiveDrive({
    required this.adapter,
    required this.transports,
    required this.clock,
    required this.scheduler,
    this.memory,
    this.compatibility = false,
    this.recordSessions = false,
    this.sink,
    this.flushEvery = const Duration(seconds: 20),
    this.appVersion = '',
  }) : vehicle = VehicleState(clock: clock, scheduler: scheduler);

  final AdapterConfig adapter;
  final TransportFactory transports;
  final Clock clock;
  final Scheduler scheduler;

  /// What is remembered between runs about this adapter (its protocol).
  final AdapterMemory? memory;

  /// Compatibility mode from the start: no batching, and a slower pace.
  final bool compatibility;

  final bool recordSessions;
  final SessionSink? sink;
  final Duration flushEvery;
  final String appVersion;

  @override
  final VehicleState vehicle;

  @override
  bool get isDemo => false;

  final ObservableValue<ConnectionStatus> _connection = ObservableValue(
    ConnectionStatus.stopped,
  );
  final ObservableValue<double> _pollRate = ObservableValue(0);
  final ObservableValue<ObdSession?> _sessions = ObservableValue(null);
  late final ObservableValue<String> _description = ObservableValue(
    adapter.displayName.toUpperCase(),
  );

  Transport? _transport;
  RecordingTransport? _recorder;
  ObdSession? _session;
  ScheduledTask? _flush;
  String? _recordingName;
  void Function()? _statusListener;
  void Function()? _rateListener;
  bool _started = false;

  @override
  Observable<ConnectionStatus> get connection => _connection;

  @override
  Observable<double> get pollRate => _pollRate;

  @override
  Observable<ObdSession?> get sessions => _sessions;

  @override
  Observable<String> get description => _description;

  /// The OBD session, or null before [start].
  ObdSession? get session => _session;

  /// The name the recording is saved under, once one has begun.
  String? get recordingName => _recordingName;

  /// Writes a line about the app into the recording, if there is one: what it
  /// made of the car, and when (see `SessionDirection.note`). Nothing otherwise.
  void note(String text) => _recorder?.note(text);

  @override
  void start() {
    if (_started) return;
    _started = true;
    Transport transport = transports.create(adapter);
    _transport = transport;
    if (recordSessions && sink != null) {
      final now = clock.now().toUtc();
      _recordingName = 'session-${_stamp(now)}-${adapter.kind.name}.log';
      final recorder = RecordingTransport(
        transport,
        clock: clock,
        header: {
          'app': 'tapedash $appVersion'.trim(),
          'adapter': adapter.displayName,
          'kind': adapter.kind.name,
          'address': adapter.address,
          'started': now.toIso8601String(),
          'compatibility': '$compatibility',
        },
      );
      _recorder = recorder;
      transport = recorder;
      _flush = scheduler.runEvery(flushEvery, () => unawaited(_save()));
    }
    final session = ObdSession(
      transport: transport,
      scheduler: scheduler,
      clock: clock,
      vehicle: vehicle,
      memory: memory,
      config: SessionConfig(compatibilityAfterRetries: compatibility ? 0 : 3),
    );
    _session = session;
    _sessions.value = session;
    _statusListener = () => _connection.value = session.status.value;
    _rateListener = () => _pollRate.value = session.pollRate.value;
    session.status.addListener(_statusListener!);
    session.pollRate.addListener(_rateListener!);
    session.start();
  }

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  Future<void> _save() async {
    final recorder = _recorder;
    final name = _recordingName;
    if (recorder == null || name == null || sink == null) return;
    try {
      await sink!.save(name, recorder.log.format());
    } on Object {
      // A full or unwritable phone must not stop the drive; the next flush tries
      // again.
    }
  }

  /// Stops reading the car and, if recording, saves the log. The drive can be
  /// started again.
  Future<void> stop() async {
    _flush?.cancel();
    _flush = null;
    final session = _session;
    if (session != null) {
      if (_statusListener != null) {
        session.status.removeListener(_statusListener!);
      }
      if (_rateListener != null) {
        session.pollRate.removeListener(_rateListener!);
      }
      session.stop();
    }
    await _save();
    session?.dispose();
    await _recorder?.dispose();
    await _transport?.disconnect();
    _session = null;
    _sessions.value = null;
    _recorder = null;
    _transport = null;
    _connection.value = ConnectionStatus.stopped;
    _pollRate.value = 0;
    _started = false;
  }

  /// Stops, and lets go of everything.
  Future<void> dispose() async {
    await stop();
    vehicle.dispose();
  }
}
