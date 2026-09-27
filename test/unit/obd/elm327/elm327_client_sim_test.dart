// The client against the simulated adapter: the real timing of a link with
// latency, an adapter that ignores adaptive timing, and one that loses
// commands, drops prompts and sends noise.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/elm327/elm327_client.dart';
import 'package:tapedash/obd/elm327/elm327_failure.dart';
import 'package:tapedash/obd/transport/sim_transport.dart';
import 'package:tapedash/obd/transport/transport.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/drive_scenario.dart';
import 'package:tapedash/sim/driver.dart';
import 'package:tapedash/sim/elm327_simulator.dart';
import 'package:tapedash/sim/scenario_events.dart';
import 'package:tapedash/sim/sim_route.dart';
import 'package:tapedash/sim/simulated_car.dart';

import '../../../support/scripted_ecu.dart';

DriveScenario _scenario({List<AdapterFault> faults = const []}) =>
    DriveScenario(
      name: 'test',
      description: 'idles',
      route: SimRoute.straight(100),
      adapterFaults: faults,
      startCoolantC: 90,
      engineRunningAtStart: true,
      driverBuilder: () => ScriptedDriver([IdleFor(100000)]),
    );

/// An adapter with a scripted ECU, behind a simulated link.
class _Rig {
  _Rig({
    AdapterQuirks quirks = AdapterQuirks.none,
    List<AdapterFault> faults = const [],
    Map<String, List<int>>? answers,
    int seed = 1,
  }) {
    car = SimulatedCar(
      scenario: _scenario(faults: faults),
      scheduler: clock,
    )..start();
    ecu = ScriptedEcu(
      answers ??
          {
            '010C': [0x41, 0x0C, 0x1A, 0xF8],
          },
      onRespond: (_) => asked.add(clock.monotonic()),
    );
    transport = SimTransport(
      car: car,
      scheduler: clock,
      adapter: Elm327Simulator(ecu: ecu, quirks: quirks, seed: seed),
      quirks: quirks,
      seed: seed,
    );
    transport.connect().catchError((Object _) {});
    clock.advance(const Duration(seconds: 1));
    client = Elm327Client(transport: transport, scheduler: clock, clock: clock);
  }

  final clock = FakeClock();
  late final SimulatedCar car;
  late final ScriptedEcu ecu;
  late final SimTransport transport;
  late final Elm327Client client;
  final List<Duration> asked = [];

  void setUp() {
    for (final c in ['ATZ', 'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP6']) {
      client.command(c, (_) {}, timeout: const Duration(seconds: 5));
      clock.advance(const Duration(seconds: 2));
    }
  }

  void close() {
    client.dispose();
    car.stop();
    transport.dispose();
  }
}

void main() {
  group('the start-up commands, on a perfect link', () {
    test('each is answered as the adapter answers it', () {
      final rig = _Rig();
      addTearDown(rig.close);
      final replies = <Elm327Reply>[];

      for (final c in [
        'ATZ',
        'ATE0',
        'ATL0',
        'ATS0',
        'ATH0',
        'ATAT1',
        'ATSP6',
      ]) {
        rig.client.command(c, replies.add, timeout: const Duration(seconds: 5));
        rig.clock.advance(const Duration(seconds: 2));
      }

      expect(replies.map((r) => r.ok), everyElement(isTrue));
      expect(replies[0].lines, ['ELM327 v1.5']);
      expect(replies.skip(1).map((r) => r.lines), everyElement(['OK']));
    });

    test('a request is answered in bytes', () {
      final rig = _Rig()..setUp();
      addTearDown(rig.close);
      Elm327Reply? reply;

      rig.client.request([0x01, 0x0C], (r) => reply = r);
      rig.clock.advance(const Duration(seconds: 1));

      expect(reply!.messages, [
        [0x41, 0x0C, 0x1A, 0xF8],
      ]);
    });

    test('a request for a PID the car does not have is NO DATA', () {
      final rig = _Rig()..setUp();
      addTearDown(rig.close);
      Elm327Reply? reply;

      rig.client.request([0x01, 0x5E], (r) => reply = r);
      rig.clock.advance(const Duration(seconds: 1));

      expect(reply!.failure, Elm327Failure.noData);
    });
  });

  group('the time of a reply, on a link with latency', () {
    const clone = AdapterQuirks(
      latency: Duration(milliseconds: 80),
      jitter: Duration(milliseconds: 40),
    );

    test('the sample time is within a few ms of when the ECU was asked', () {
      final rig = _Rig(quirks: clone)..setUp();
      addTearDown(rig.close);
      final replies = <Elm327Reply>[];
      rig.asked.clear();

      void next() {
        if (replies.length >= 100) return;
        rig.client.request([0x01, 0x0C], (r) {
          replies.add(r);
          next();
        }, responses: 1);
      }

      next();
      rig.clock.advance(const Duration(seconds: 30));

      expect(replies.length, 100);
      expect(rig.asked.length, 100);
      var worst = 0;
      for (var i = 0; i < 100; i++) {
        final error = (replies[i].sampleTime! - rig.asked[i]).inMicroseconds
            .abs();
        if (error > worst) worst = error;
        // The ECU's own 20 ms is on the way back only: half of it is the error.
        expect(error, closeTo(10000, 1000), reason: 'request $i');
      }
      expect(worst, lessThan(11000));
    });

    test(
      'the latency is the round trip and the ECU\'s time, 100 ms on average',
      () {
        final rig = _Rig(quirks: clone)..setUp();
        addTearDown(rig.close);
        final latencies = <int>[];

        void next() {
          if (latencies.length >= 200) return;
          rig.client.request([0x01, 0x0C], (r) {
            latencies.add(r.latency!.inMilliseconds);
            next();
          }, responses: 1);
        }

        next();
        rig.clock.advance(const Duration(minutes: 2));

        final mean = latencies.reduce((a, b) => a + b) / latencies.length;
        expect(mean, closeTo(100, 6));
        expect(
          latencies.reduce((a, b) => a < b ? a : b),
          greaterThanOrEqualTo(58),
        );
        expect(
          latencies.reduce((a, b) => a > b ? a : b),
          lessThanOrEqualTo(142),
        );
      },
    );
  });

  group('an adapter that ignores adaptive timing', () {
    const clone = AdapterQuirks(ignoreAdaptiveTiming: true);

    test('without the count digit the prompt comes 200 ms after the data', () {
      final rig = _Rig(quirks: clone)..setUp();
      addTearDown(rig.close);
      Elm327Reply? reply;

      rig.client.request([0x01, 0x0C], (r) => reply = r);
      rig.clock.advance(const Duration(seconds: 1));

      expect(
        reply!.completedAt - reply!.dataAt!,
        const Duration(milliseconds: 200),
      );
      // ... but the latency is that of the data, not of the prompt.
      expect(reply!.latency, const Duration(milliseconds: 20));
    });

    test('with the count digit it does not wait', () {
      final rig = _Rig(quirks: clone)..setUp();
      addTearDown(rig.close);
      Elm327Reply? reply;

      rig.client.request([0x01, 0x0C], (r) => reply = r, responses: 1);
      rig.clock.advance(const Duration(seconds: 1));

      expect(reply!.completedAt - reply!.dataAt!, Duration.zero);
    });

    test('so requests with the digit go four times as fast', () {
      int count(int? responses) {
        final rig = _Rig(quirks: clone)..setUp();
        var n = 0;
        void next() {
          rig.client.request([0x01, 0x0C], (r) {
            n++;
            next();
          }, responses: responses);
        }

        next();
        rig.clock.advance(const Duration(seconds: 10));
        rig.close();
        return n;
      }

      final without = count(null);
      final withDigit = count(1);

      expect(without, closeTo(10 / 0.22, 2));
      expect(withDigit, closeTo(10 / 0.02, 5));
    });
  });

  group('an adapter that loses the first command', () {
    test('the first command times out, and the second works', () {
      final rig = _Rig(quirks: const AdapterQuirks(dropFirstCommand: true));
      addTearDown(rig.close);
      final replies = <Elm327Reply>[];

      rig.client.command(
        'ATZ',
        replies.add,
        timeout: const Duration(seconds: 3),
      );
      rig.clock.advance(const Duration(seconds: 3));
      expect(replies.single.failure, Elm327Failure.timeout);

      rig.client.command(
        'ATZ',
        replies.add,
        timeout: const Duration(seconds: 3),
      );
      rig.clock.advance(const Duration(seconds: 3));

      expect(replies.last.ok, isTrue);
      expect(replies.last.lines, ['ELM327 v1.5']);
    });
  });

  group('a flaky adapter', () {
    test('no crash, and never a wrong value: right, or a failure', () {
      final rig = _Rig(quirks: AdapterQuirks.flaky)..setUp();
      addTearDown(rig.close);
      final outcomes = <Elm327Failure?>[];
      var wrong = 0;
      const right = [0x41, 0x0C, 0x1A, 0xF8];

      void next() {
        if (outcomes.length >= 3000) return;
        rig.client.request(
          [0x01, 0x0C],
          (r) {
            outcomes.add(r.failure);
            if (r.ok && r.messages.single.join(',') != right.join(',')) wrong++;
            next();
          },
          responses: 1,
          expectPrefix: [0x41, 0x0C],
        );
      }

      next();
      rig.clock.advance(const Duration(hours: 1));

      expect(outcomes.length, 3000);
      expect(wrong, 0);
      final ok = outcomes.where((f) => f == null).length;
      final noData = outcomes.where((f) => f == Elm327Failure.noData).length;
      expect(ok / 3000, greaterThan(0.9));
      expect(noData / 3000, closeTo(0.04, 0.015));
      // Noise and missing prompts are rare, and every one is accounted for.
      expect(rig.client.garbledReplies + rig.client.timeouts, lessThan(150));
    });

    test('a missing prompt costs the grace, not the whole timeout', () {
      // Every reply loses its prompt. The first request also has the adapter
      // search for a protocol, which takes 2.4 s.
      final rig = _Rig(quirks: const AdapterQuirks(missingPromptRate: 1));
      addTearDown(rig.close);
      Elm327Reply? reply;

      rig.client.request(
        [0x01, 0x0C],
        (r) => reply = r,
        responses: 1,
        timeout: const Duration(seconds: 12),
      );
      rig.clock.advance(const Duration(seconds: 6));

      expect(reply!.ok, isTrue);
      expect(reply!.gotPrompt, isFalse);
      expect(
        reply!.completedAt - reply!.dataAt!,
        const Duration(milliseconds: 250),
      );
    });
  });

  group('the link dropping', () {
    test('a command waiting when the link drops fails as disconnected', () {
      final rig = _Rig(
        quirks: const AdapterQuirks(latency: Duration(milliseconds: 300)),
        faults: const [
          AdapterDisconnect(
            at: Duration(seconds: 10),
            outage: Duration(seconds: 5),
          ),
        ],
      );
      addTearDown(rig.close);
      rig.clock.advance(const Duration(milliseconds: 8800));
      final states = <TransportState>[];
      rig.transport.state.listen(states.add);
      Elm327Reply? reply;

      rig.client.request([0x01, 0x0C], (r) => reply = r);
      rig.clock.advance(const Duration(seconds: 3));

      expect(reply!.failure, Elm327Failure.disconnected);
      expect(states.last.failure, TransportFailure.lost);
      expect(rig.client.isIdle, isTrue);
    });
  });
}
