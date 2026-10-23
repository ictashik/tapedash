// A real-adapter drive, with a simulated adapter behind the transport factory: the
// same stack as the demo, the session found and kept, the protocol remembered, the
// recording written for the handoff, and the drive stopped and started again.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/live_drive.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/adapter_config.dart';
import 'package:tapedash/obd/link_diary.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/obd/transport/session_log.dart';
import 'package:tapedash/obd/transport/session_sink.dart';
import 'package:tapedash/obd/transport/sim_transport.dart';
import 'package:tapedash/obd/transport/transport.dart';
import 'package:tapedash/obd/transport_factory.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';
import 'package:tapedash/vehicle/sensor.dart';

/// A simulated adapter that, like a radio, says what it is doing.
class DiagTransport extends SimTransport implements LinkDiagnostics {
  DiagTransport({required super.car, required super.scheduler});

  // A test transport: nothing holds it open past the test.
  // ignore: close_sinks
  final StreamController<String> lines = StreamController<String>.broadcast(
    sync: true,
  );

  @override
  Stream<String> get diagnostics => lines.stream;
}

class SimFactory implements TransportFactory {
  SimFactory(this.car, this.clock);

  final SimulatedCar car;
  final FakeClock clock;
  final List<AdapterConfig> asked = [];

  /// The last transport made, when it is one that says what it is doing.
  DiagTransport? diag;

  /// Whether to make transports that say what they are doing.
  bool sayWhatIsHappening = false;

  @override
  Transport create(AdapterConfig config) {
    asked.add(config);
    if (sayWhatIsHappening) {
      return diag = DiagTransport(car: car, scheduler: clock);
    }
    return SimTransport(car: car, scheduler: clock);
  }
}

const _adapter = AdapterConfig(
  kind: AdapterKind.bluetoothClassic,
  address: '00:1D:A5:00:00:01',
  name: 'OBDII',
);

void main() {
  late FakeClock clock;
  late SimulatedCar car;
  late SimFactory factory;

  setUp(() {
    clock = FakeClock()..advance(const Duration(seconds: 100));
    car = SimulatedCar(scenario: DriveScenarios.cityStopGo, scheduler: clock)
      ..start();
    factory = SimFactory(car, clock);
  });

  tearDown(() => car.stop());

  LiveDrive drive({
    bool compatibility = false,
    bool record = false,
    MemorySessionSink? sink,
    AdapterMemory? memory,
  }) => LiveDrive(
    adapter: _adapter,
    transports: factory,
    clock: clock,
    scheduler: clock,
    compatibility: compatibility,
    recordSessions: record,
    sink: sink,
    memory: memory,
    appVersion: '9.9',
  );

  test(
    'it opens the chosen adapter, connects, and fills the vehicle',
    () async {
      final d = drive();
      addTearDown(d.dispose);
      expect(d.connection.value, ConnectionStatus.stopped);
      expect(d.description.value, 'OBDII');

      d.start();
      expect(factory.asked, [_adapter]);
      clock.advance(const Duration(seconds: 30));
      expect(d.connection.value, ConnectionStatus.connected);
      expect(d.sessions.value, same(d.session));
      expect(d.vehicle.reading(Sensor.rpm).value, isNotNull);
      expect(d.pollRate.value, greaterThan(1));
      expect(d.session!.adapterInfo.value!.isCan, isTrue);
    },
  );

  test('starting twice does nothing more', () async {
    final d = drive();
    addTearDown(d.dispose);
    d.start();
    d.start();
    expect(factory.asked.length, 1);
  });

  test('the protocol it found is remembered for the next run', () async {
    final memory = InMemoryAdapterMemory();
    final d = drive(memory: memory);
    addTearDown(d.dispose);
    d.start();
    clock.advance(const Duration(seconds: 30));
    expect(memory.protocol, '6');
  });

  test('compatibility mode is on from the start when asked for', () async {
    final d = drive(compatibility: true);
    addTearDown(d.dispose);
    d.start();
    clock.advance(const Duration(seconds: 30));
    expect(d.session!.poller!.compatibilityMode, isTrue);

    final normal = drive();
    addTearDown(normal.dispose);
    normal.start();
    clock.advance(const Duration(seconds: 30));
    expect(normal.session!.poller!.compatibilityMode, isFalse);
  });

  group('recording, for the hardware handoff', () {
    test('the traffic is written as it happens, and at the end', () async {
      final sink = MemorySessionSink();
      final d = drive(record: true, sink: sink);
      d.start();
      final name = d.recordingName!;
      expect(
        name,
        matches(RegExp(r'^session-\d{8}-\d{6}-bluetoothClassic\.log$')),
      );

      clock.advance(const Duration(seconds: 25));
      // One flush has happened: a drive that crashes still leaves a log.
      final midway = SessionLog.parse(sink.files[name]!);
      expect(midway.header['adapter'], 'OBDII');
      expect(midway.header['address'], '00:1D:A5:00:00:01');
      expect(midway.header['app'], 'tapedash 9.9');
      expect(midway.entries.any((e) => e.text.startsWith('ATZ')), isTrue);

      clock.advance(const Duration(seconds: 25));
      await d.dispose();
      final full = SessionLog.parse(sink.files[name]!);
      expect(full.entries.length, greaterThan(midway.entries.length));
      // What was received is there too.
      expect(
        full.entries.any((e) => e.text.contains('ELM327')),
        isTrue,
        reason: 'the adapter banner',
      );
    });

    test('with recording off, or no sink, nothing is written', () async {
      final sink = MemorySessionSink();
      final off = drive(record: false, sink: sink);
      off.start();
      clock.advance(const Duration(seconds: 25));
      await off.dispose();
      expect(sink.files, isEmpty);
      expect(off.recordingName, isNull);

      final none = drive(record: true);
      none.start();
      clock.advance(const Duration(seconds: 25));
      await none.dispose();
      expect(none.recordingName, isNull);
    });

    test('a sink that fails does not stop the drive', () async {
      final d = LiveDrive(
        adapter: _adapter,
        transports: factory,
        clock: clock,
        scheduler: clock,
        recordSessions: true,
        sink: _BrokenSink(),
      );
      addTearDown(d.dispose);
      d.start();
      clock.advance(const Duration(seconds: 45));
      expect(d.connection.value, ConnectionStatus.connected);
    });
  });

  test('it can be stopped, and started again', () async {
    final d = drive();
    addTearDown(d.dispose);
    d.start();
    clock.advance(const Duration(seconds: 30));
    expect(d.connection.value, ConnectionStatus.connected);

    await d.stop();
    expect(d.connection.value, ConnectionStatus.stopped);
    expect(d.sessions.value, isNull);
    expect(d.pollRate.value, 0);

    d.start();
    expect(factory.asked.length, 2);
    clock.advance(const Duration(seconds: 30));
    expect(d.connection.value, ConnectionStatus.connected);
  });

  group('the connection log', () {
    test('it says what the drive does to reach the adapter, and what the '
        'radio says, whether or not the session is recorded', () async {
      factory.sayWhatIsHappening = true;
      final diary = LinkDiary(clock: clock);
      final d = LiveDrive(
        adapter: _adapter,
        transports: factory,
        clock: clock,
        scheduler: clock,
        diary: diary,
      );
      addTearDown(d.dispose);
      d.start();
      factory.diag!.lines.add('classic: connected by channel 1 (round 2)');
      clock.advance(const Duration(seconds: 30));

      final text = diary.format();
      expect(text, contains('drive started: Bluetooth OBDII'));
      expect(text, contains('00:1D:A5:00:00:01'));
      expect(text, contains('classic: connected by channel 1 (round 2)'));
      expect(text, contains('transport connecting'));
      expect(text, contains('transport connected'));
      expect(text, contains('status connected'));
    });

    test(
      'with the session recorded the same lines are in the recording',
      () async {
        factory.sayWhatIsHappening = true;
        final sink = MemorySessionSink();
        final d = LiveDrive(
          adapter: _adapter,
          transports: factory,
          clock: clock,
          scheduler: clock,
          recordSessions: true,
          sink: sink,
        );
        d.start();
        factory.diag!.lines.add('ble: link status=133 state=disconnected');
        clock.advance(const Duration(seconds: 25));
        final name = d.recordingName!;
        await d.dispose();
        final log = SessionLog.parse(sink.files[name]!);
        final notes = [
          for (final e in log.entries)
            if (e.direction == SessionDirection.note) e.text,
        ];
        expect(notes, contains('link ble: link status=133 state=disconnected'));
      },
    );

    test('a drive with no diary and no recording just drives', () async {
      factory.sayWhatIsHappening = true;
      final d = drive();
      addTearDown(d.dispose);
      d.start();
      factory.diag!.lines.add('anything');
      clock.advance(const Duration(seconds: 30));
      expect(d.connection.value, ConnectionStatus.connected);
    });
  });
}

class _BrokenSink implements SessionSink {
  @override
  Future<void> save(String name, String text) async =>
      throw StateError('the phone is full');
}
