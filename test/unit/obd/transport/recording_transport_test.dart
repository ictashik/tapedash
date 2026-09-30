import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/transport/recording_transport.dart';
import 'package:tapedash/obd/transport/session_log.dart';
import 'package:tapedash/obd/transport/sim_transport.dart';
import 'package:tapedash/obd/transport/transport.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/drive_scenario.dart';
import 'package:tapedash/sim/driver.dart';
import 'package:tapedash/sim/scenario_events.dart';
import 'package:tapedash/sim/sim_route.dart';
import 'package:tapedash/sim/simulated_car.dart';

DriveScenario _scenario({
  AdapterQuirks quirks = AdapterQuirks.none,
  List<AdapterFault> faults = const [],
}) => DriveScenario(
  name: 'test',
  description: 'idles, warm and running',
  route: SimRoute.straight(100),
  quirks: quirks,
  adapterFaults: faults,
  startCoolantC: 90,
  engineRunningAtStart: true,
  driverBuilder: () => ScriptedDriver([IdleFor(100000)]),
);

class _Rig {
  _Rig({DriveScenario? scenario}) {
    car = SimulatedCar(scenario: scenario ?? _scenario(), scheduler: clock)
      ..start();
    inner = SimTransport(car: car, scheduler: clock);
    recorder = RecordingTransport(
      inner,
      clock: clock,
      header: const {'scenario': 'test'},
    );
    recorder.incoming.listen(received.add);
    recorder.state.listen(states.add);
  }

  final clock = FakeClock();
  late final SimulatedCar car;
  late final SimTransport inner;
  late final RecordingTransport recorder;
  final List<String> received = [];
  final List<TransportState> states = [];

  void advance(int ms) => clock.advance(Duration(milliseconds: ms));

  void close() {
    car.stop();
    recorder.dispose();
    inner.dispose();
  }
}

void main() {
  test('it records what happens, and when', () async {
    final rig = _Rig();
    addTearDown(rig.close);

    final connected = rig.recorder.connect();
    rig.advance(1000);
    await connected;
    await rig.recorder.write('ATI\r');
    rig.advance(100);
    await rig.recorder.disconnect();

    expect(
      rig.recorder.log.format(),
      '# tapedash-session v1\n'
      '# scenario: test\n'
      '0.000 ! connecting\n'
      '0.400 ! connected\n'
      '1.000 > ATI\\r\n'
      '1.000 < ATI\\rELM327 v1.5\\r\\n\\r\\n>\n'
      '1.100 ! disconnected\n',
    );
  });

  test('what it passes on is what it recorded', () async {
    final rig = _Rig();
    addTearDown(rig.close);
    final connected = rig.recorder.connect();
    rig.advance(1000);
    await connected;

    await rig.recorder.write('ATI\r');
    rig.advance(100);

    expect(rig.received.join(), 'ATI\rELM327 v1.5\r\n\r\n>');
    expect(rig.states, [TransportState.connecting, TransportState.connected]);
    expect(rig.recorder.currentState, TransportState.connected);
    final recorded = rig.recorder.log.entries
        .where((e) => e.direction == SessionDirection.received)
        .map((e) => e.text)
        .join();
    expect(recorded, rig.received.join());
  });

  test('pieces are recorded separately, as they arrive', () async {
    final rig = _Rig(
      scenario: _scenario(
        quirks: const AdapterQuirks(latency: Duration(milliseconds: 80)),
      ),
    );
    addTearDown(rig.close);
    final connected = rig.recorder.connect();
    rig.advance(1000);
    await connected;
    for (final c in ['ATSP6\r', '0100\r']) {
      await rig.recorder.write(c);
      rig.advance(500);
    }

    await rig.recorder.write('010C\r');
    rig.advance(500);

    final entries = rig.recorder.log.entries;
    final start = entries.lastIndexWhere(
      (e) => e.direction == SessionDirection.sent,
    );
    expect(entries.skip(start).map((e) => (e.direction, e.text)).toList(), [
      (SessionDirection.sent, '010C\r'),
      (SessionDirection.received, '010C\r'),
      (SessionDirection.received, entries[start + 2].text),
      (SessionDirection.received, '\r\n>'),
    ]);
    expect(entries[start + 2].text, startsWith('41 0C '));
    // The prompt is an adaptive-timing wait after the answer.
    expect((entries[start + 3].at - entries[start + 2].at).inMilliseconds, 40);
  });

  test('a link that drops is recorded with why', () async {
    final rig = _Rig(
      scenario: _scenario(
        faults: const [
          AdapterDisconnect(
            at: Duration(seconds: 5),
            outage: Duration(seconds: 3),
          ),
        ],
      ),
    );
    addTearDown(rig.close);
    final connected = rig.recorder.connect();
    rig.advance(1000);
    await connected;

    rig.advance(5000);

    expect(rig.recorder.log.entries.last.direction, SessionDirection.event);
    expect(rig.recorder.log.entries.last.text, 'disconnected (lost)');
  });

  test('a write with no link is recorded, and fails as it would', () async {
    final rig = _Rig();
    addTearDown(rig.close);

    await expectLater(
      rig.recorder.write('ATZ\r'),
      throwsA(isA<TransportException>()),
    );

    expect(rig.recorder.log.entries.single.text, 'ATZ\r');
  });

  test('the log reads back the same', () async {
    final rig = _Rig();
    addTearDown(rig.close);
    final connected = rig.recorder.connect();
    rig.advance(1000);
    await connected;
    await rig.recorder.write('ATI\r');
    rig.advance(100);

    final text = rig.recorder.log.format();

    expect(SessionLog.parse(text).format(), text);
  });

  test('a note is a line about the app, in the log at its own time', () async {
    final rig = _Rig();
    addTearDown(rig.close);
    final connected = rig.recorder.connect();
    rig.advance(1000);
    await connected;

    rig.recorder.note('trip ending');
    rig.advance(2500);
    rig.recorder.note('status waitingForIgnition');

    final notes = rig.recorder.log.entries
        .where((e) => e.direction == SessionDirection.note)
        .toList();
    expect(notes.map((e) => e.text), [
      'trip ending',
      'status waitingForIgnition',
    ]);
    expect(notes[1].at - notes[0].at, const Duration(milliseconds: 2500));
    final text = rig.recorder.log.format();
    expect(text, contains(' @ trip ending\n'));
    expect(SessionLog.parse(text).entries, rig.recorder.log.entries);
  });

  test('after dispose it records nothing more', () async {
    final rig = _Rig();
    addTearDown(rig.close);
    final connected = rig.recorder.connect();
    rig.advance(1000);
    await connected;

    await rig.recorder.dispose();
    await rig.inner.write('ATI\r');
    rig.advance(100);

    expect(rig.recorder.log.entries.map((e) => e.text), [
      'connecting',
      'connected',
    ]);
  });
}
