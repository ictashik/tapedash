import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/transport/sim_transport.dart';
import 'package:tapedash/obd/transport/transport.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/drive_scenario.dart';
import 'package:tapedash/sim/driver.dart';
import 'package:tapedash/sim/scenario_events.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/sim_route.dart';
import 'package:tapedash/sim/simulated_car.dart';

/// A running car that only idles, on a link with the given quirks and faults.
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

/// A fake clock, a car on it, and a transport to the car, with what came in.
class _Rig {
  _Rig({DriveScenario? scenario, Duration? connectDelay}) {
    car = SimulatedCar(scenario: scenario ?? _scenario(), scheduler: clock)
      ..start();
    transport = SimTransport(
      car: car,
      scheduler: clock,
      connectDelay: connectDelay ?? const Duration(milliseconds: 400),
    );
    transport.incoming.listen((text) {
      received.add((clock.monotonic(), text));
      _buffer.write(text);
    });
    transport.state.listen(states.add);
  }

  final clock = FakeClock();
  late final SimulatedCar car;
  late final SimTransport transport;
  final List<(Duration, String)> received = [];
  final List<TransportState> states = [];
  final StringBuffer _buffer = StringBuffer();

  Future<void> connect() async {
    final connected = transport.connect();
    clock.advance(const Duration(seconds: 1));
    await connected;
  }

  /// Writes a command and runs the clock until the prompt comes back.
  String send(String command, {Duration limit = const Duration(seconds: 20)}) {
    _buffer.clear();
    transport.write('$command\r');
    var waited = Duration.zero;
    const step = Duration(milliseconds: 5);
    while (!_buffer.toString().endsWith('>') && waited < limit) {
      clock.advance(step);
      waited += step;
    }
    return _buffer.toString();
  }

  void advance(Duration d) => clock.advance(d);

  void close() {
    car.stop();
    transport.dispose();
  }
}

void main() {
  group('connecting', () {
    test('it is connecting, and then connected once the delay is up', () async {
      final rig = _Rig();
      addTearDown(rig.close);
      expect(rig.transport.currentState, const TransportState.disconnected());

      final connected = rig.transport.connect();
      expect(rig.transport.currentState, TransportState.connecting);
      rig.advance(const Duration(milliseconds: 399));
      expect(rig.transport.currentState, TransportState.connecting);
      rig.advance(const Duration(milliseconds: 1));
      await connected;

      expect(rig.transport.currentState, TransportState.connected);
      expect(rig.states, [TransportState.connecting, TransportState.connected]);
    });

    test('connecting twice at once is one attempt', () async {
      final rig = _Rig();
      addTearDown(rig.close);

      final a = rig.transport.connect();
      final b = rig.transport.connect();
      rig.advance(const Duration(seconds: 1));
      await Future.wait([a, b]);

      expect(rig.states, [TransportState.connecting, TransportState.connected]);
    });

    test('connecting when connected does nothing', () async {
      final rig = _Rig();
      addTearDown(rig.close);
      await rig.connect();
      rig.states.clear();

      await rig.transport.connect();

      expect(rig.states, isEmpty);
    });

    test('writing with no link is an error', () async {
      final rig = _Rig();
      addTearDown(rig.close);

      await expectLater(
        rig.transport.write('ATZ\r'),
        throwsA(
          isA<TransportException>().having(
            (e) => e.failure,
            'failure',
            TransportFailure.notConnected,
          ),
        ),
      );
    });

    test('disconnecting while connecting cancels it', () async {
      final rig = _Rig();
      addTearDown(rig.close);

      final connecting = rig.transport.connect();
      final outcome = expectLater(
        connecting,
        throwsA(
          isA<TransportException>().having(
            (e) => e.failure,
            'failure',
            TransportFailure.cancelled,
          ),
        ),
      );
      await rig.transport.disconnect();
      rig.advance(const Duration(seconds: 2));

      await outcome;
      expect(rig.transport.currentState, const TransportState.disconnected());
    });

    test('disconnecting when there is no link is harmless', () async {
      final rig = _Rig();
      addTearDown(rig.close);

      await rig.transport.disconnect();

      expect(rig.states, isEmpty);
    });

    test('disconnecting closes the link, with no failure', () async {
      final rig = _Rig();
      addTearDown(rig.close);
      await rig.connect();

      await rig.transport.disconnect();

      expect(rig.transport.currentState, const TransportState.disconnected());
      expect(rig.states.last.failure, isNull);
    });
  });

  group('talking to the adapter', () {
    test('the usual start-up works on the simulated car', () async {
      final rig = _Rig();
      addTearDown(rig.close);
      await rig.connect();

      expect(rig.send('ATZ'), contains('ELM327 v1.5'));
      expect(rig.send('ATE0'), endsWith('OK\r\n\r\n>'));
      expect(rig.send('ATL0'), 'OK\r\r>');
      expect(rig.send('ATS0'), 'OK\r\r>');
      expect(rig.send('ATH0'), 'OK\r\r>');
      expect(rig.send('ATAT1'), 'OK\r\r>');
      expect(rig.send('ATSP0'), 'OK\r\r>');
      expect(rig.send('0100'), 'SEARCHING...\r4100983B8001\r\r>');
      expect(rig.send('ATDPN'), 'A6\r\r>');
    });

    test('an engine that is running reads sensible rpm', () async {
      final rig = _Rig();
      addTearDown(rig.close);
      await rig.connect();
      for (final c in ['ATZ', 'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP6']) {
        rig.send(c);
      }

      final reply = rig.send('010C');

      expect(reply, matches(RegExp(r'^410C[0-9A-F]{4}\r\r>$')));
      final rpm = int.parse(reply.substring(4, 8), radix: 16) / 4;
      expect(rpm, inInclusiveRange(600, 900));
    });

    test('the ignition is on, so the voltage is the running voltage', () async {
      final rig = _Rig();
      addTearDown(rig.close);
      await rig.connect();
      rig.send('ATZ');

      final reply = rig.send('ATRV');

      expect(reply, contains('V'));
      final volts = double.parse(
        reply.replaceAll('ATRV\r', '').split('V').first.trim(),
      );
      expect(volts, inInclusiveRange(13.5, 14.5));
    });

    test(
      'a slow link delivers the echo, the answer and the prompt apart',
      () async {
        final rig = _Rig(
          scenario: _scenario(
            quirks: const AdapterQuirks(latency: Duration(milliseconds: 80)),
          ),
        );
        addTearDown(rig.close);
        await rig.connect();
        for (final c in ['ATZ', 'ATE0', 'ATL0', 'ATS0', 'ATSP6', '0100']) {
          rig.send(c);
        }
        rig.received.clear();
        final start = rig.clock.monotonic();

        rig.send('010C');

        final offsets = rig.received
            .map((r) => (r.$1 - start).inMilliseconds)
            .toList();
        expect(
          rig.received.map((r) => r.$2).join(),
          matches(RegExp(r'^410C[0-9A-F]{4}\r\r>$')),
        );
        // The answer and the prompt are separate pieces, an adaptive-timing
        // wait apart.
        expect(rig.received.length, 2);
        expect(offsets[1] - offsets[0], inInclusiveRange(38, 45));
        expect(offsets[0], inInclusiveRange(100, 110));
      },
    );

    test('nothing arrives after the link is closed', () async {
      final rig = _Rig(
        scenario: _scenario(
          quirks: const AdapterQuirks(latency: Duration(milliseconds: 200)),
        ),
      );
      addTearDown(rig.close);
      await rig.connect();
      await rig.transport.write('ATI\r');
      rig.advance(const Duration(milliseconds: 50));

      await rig.transport.disconnect();
      rig.advance(const Duration(seconds: 2));

      expect(rig.received, isEmpty);
    });

    test('the adapter keeps its settings across a reconnect', () async {
      final rig = _Rig();
      addTearDown(rig.close);
      await rig.connect();
      rig.send('ATE0');
      await rig.transport.disconnect();

      await rig.connect();

      // Echo is still off: the adapter stayed powered.
      expect(rig.send('ATI'), 'ELM327 v1.5\r\n\r\n>');
    });

    test(
      'a clone that loses the first command does so on each connection',
      () async {
        final rig = _Rig(
          scenario: _scenario(
            quirks: const AdapterQuirks(dropFirstCommand: true),
          ),
        );
        addTearDown(rig.close);

        for (var i = 0; i < 2; i++) {
          await rig.connect();
          expect(rig.send('ATI', limit: const Duration(seconds: 1)), isEmpty);
          expect(rig.send('ATI'), contains('ELM327'));
          await rig.transport.disconnect();
        }
      },
    );

    test('a well-behaved exchange never overlaps commands', () async {
      final rig = _Rig();
      addTearDown(rig.close);
      await rig.connect();

      for (final c in ['ATZ', 'ATE0', 'ATSP0', '0100', '010C', '010D']) {
        rig.send(c);
      }

      expect(rig.transport.overlappedCommands, 0);
    });
  });

  group('link faults from the scenario', () {
    final scenario = _scenario(
      faults: const [
        AdapterDisconnect(
          at: Duration(seconds: 10),
          outage: Duration(seconds: 5),
        ),
      ],
    );

    test('the link drops at its time in the drive', () async {
      final rig = _Rig(scenario: scenario);
      addTearDown(rig.close);
      await rig.connect();

      rig.advance(const Duration(seconds: 8));
      expect(rig.transport.currentState, TransportState.connected);
      rig.advance(const Duration(seconds: 3));

      expect(
        rig.transport.currentState,
        const TransportState.disconnected(failure: TransportFailure.lost),
      );
    });

    test('while it is out, connecting fails after the delay', () async {
      final rig = _Rig(scenario: scenario);
      addTearDown(rig.close);
      await rig.connect();
      rig.advance(const Duration(seconds: 11));

      final attempt = rig.transport.connect();
      final outcome = expectLater(
        attempt,
        throwsA(
          isA<TransportException>().having(
            (e) => e.failure,
            'failure',
            TransportFailure.unreachable,
          ),
        ),
      );
      rig.advance(const Duration(seconds: 1));

      await outcome;
      expect(
        rig.transport.currentState,
        const TransportState.disconnected(
          failure: TransportFailure.unreachable,
        ),
      );
    });

    test('after the outage it connects again', () async {
      final rig = _Rig(scenario: scenario);
      addTearDown(rig.close);
      await rig.connect();
      rig.advance(const Duration(seconds: 16));

      await rig.connect();

      expect(rig.transport.currentState, TransportState.connected);
    });

    test(
      'a connection attempt that straddles the start of the outage fails',
      () async {
        final rig = _Rig(scenario: scenario);
        addTearDown(rig.close);
        rig.advance(const Duration(milliseconds: 9800));

        final attempt = rig.transport.connect();
        final outcome = expectLater(
          attempt,
          throwsA(isA<TransportException>()),
        );
        rig.advance(const Duration(seconds: 1));

        await outcome;
      },
    );

    test('what was on its way when the link dropped is lost', () async {
      final slow = _scenario(
        quirks: const AdapterQuirks(latency: Duration(milliseconds: 300)),
        faults: const [
          AdapterDisconnect(
            at: Duration(seconds: 10),
            outage: Duration(seconds: 5),
          ),
        ],
      );
      final rig = _Rig(scenario: slow);
      addTearDown(rig.close);
      // Connecting leaves the clock at 1 s.
      await rig.connect();
      rig.advance(const Duration(milliseconds: 8800));
      rig.received.clear();

      await rig.transport.write('ATI\r');
      rig.advance(const Duration(seconds: 2));

      // Written at 9.8 s, so the answer would arrive at 10.1 s: 0.1 s after
      // the link drops.
      expect(rig.received, isEmpty);
    });

    test('it drops once, and the adapter is fine afterwards', () async {
      final rig = _Rig(scenario: scenario);
      addTearDown(rig.close);
      await rig.connect();
      rig.advance(const Duration(seconds: 16));
      await rig.connect();

      expect(rig.send('ATI'), contains('ELM327'));
      rig.advance(const Duration(seconds: 30));

      expect(rig.transport.currentState, TransportState.connected);
    });

    test('adapter_flaky drops the link at four minutes', () async {
      final rig = _Rig(scenario: DriveScenarios.adapterFlaky);
      addTearDown(rig.close);
      await rig.connect();

      rig.advance(const Duration(minutes: 3, seconds: 59));
      expect(rig.transport.currentState, TransportState.connected);
      rig.advance(const Duration(seconds: 2));

      expect(rig.transport.currentState.failure, TransportFailure.lost);
    });
  });

  group('the quirks come from the scenario', () {
    test('the flaky scenario gives a flaky adapter', () async {
      final rig = _Rig(scenario: DriveScenarios.adapterFlaky);
      addTearDown(rig.close);

      expect(rig.transport.adapter.quirks.dropFirstCommand, isTrue);
      expect(rig.transport.adapter.quirks.noDataRate, greaterThan(0));
    });

    test('a scenario without quirks gives a perfect adapter', () async {
      final rig = _Rig();
      addTearDown(rig.close);

      expect(rig.transport.adapter.quirks.latency, Duration.zero);
    });
  });

  group('cleaning up', () {
    test('disposing leaves nothing scheduled but the car', () async {
      final rig = _Rig();
      await rig.connect();
      rig.send('ATI');

      rig.car.stop();
      await rig.transport.dispose();

      expect(rig.clock.pendingTasks, 0);
    });

    test('disposing while connecting fails the attempt', () async {
      final rig = _Rig();
      final attempt = rig.transport.connect();
      final outcome = expectLater(attempt, throwsA(isA<TransportException>()));

      rig.car.stop();
      await rig.transport.dispose();

      await outcome;
      expect(rig.clock.pendingTasks, 0);
    });
  });
}
