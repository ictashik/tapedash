import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/dtc/dtc.dart';
import 'package:tapedash/obd/dtc/dtc_service.dart';
import 'package:tapedash/obd/elm327/elm327_client.dart';
import 'package:tapedash/obd/elm327/elm327_failure.dart';
import 'package:tapedash/obd/transport/sim_transport.dart';
import 'package:tapedash/sim/drive_scenario.dart';
import 'package:tapedash/sim/driver.dart';
import 'package:tapedash/sim/scenario_events.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/sim_route.dart';
import 'package:tapedash/sim/simulated_car.dart';

import '../../../support/fake_transport.dart';
import '../../../support/scripted_adapter.dart';

List<String> _codes(List<Dtc> dtcs) => dtcs.map((d) => d.code).toList();

/// The real simulated car and adapter, set up as start-up leaves them.
class _SimRig {
  _SimRig(DriveScenario scenario, {bool Function()? stationary}) {
    car = SimulatedCar(scenario: scenario, scheduler: clock)..start();
    transport = SimTransport(car: car, scheduler: clock);
    transport.connect().catchError((Object _) {});
    clock.advance(const Duration(seconds: 1));
    client = Elm327Client(transport: transport, scheduler: clock, clock: clock);
    for (final c in ['ATZ', 'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP6']) {
      client.command(c, (_) {}, timeout: const Duration(seconds: 5));
      clock.advance(const Duration(seconds: 2));
    }
    // Let the car get going: ignition on.
    clock.advance(const Duration(seconds: 3));
    service = DtcService(
      client: client,
      scheduler: clock,
      isCan: true,
      isStationary: stationary ?? () => car.state.speedMs == 0,
    );
  }

  final clock = FakeClock();
  late final SimulatedCar car;
  late final SimTransport transport;
  late final Elm327Client client;
  late final DtcService service;

  DtcReadResult read() {
    DtcReadResult? result;
    service.read((r) => result = r);
    clock.advance(const Duration(seconds: 5));
    return result!;
  }

  DtcClearOutcome clear() {
    DtcClearOutcome? result;
    service.clear((r) => result = r);
    clock.advance(const Duration(seconds: 3));
    return result!;
  }

  void close() {
    client.dispose();
    car.stop();
    transport.dispose();
  }
}

DriveScenario _idle({List<DtcInjection> dtcs = const []}) => DriveScenario(
  name: 'test',
  description: 'idles, running',
  route: SimRoute.straight(100),
  dtcs: dtcs,
  startCoolantC: 90,
  engineRunningAtStart: true,
  driverBuilder: () => ScriptedDriver([IdleFor(100000)]),
);

/// A car standing still with the engine running and two codes stored.
DriveScenario _stillWithCodes() => _idle(
  dtcs: const [
    DtcInjection(at: Duration.zero, code: 'P0420'),
    DtcInjection(at: Duration.zero, code: 'P0171'),
  ],
);

void main() {
  group('reading, against the simulated car', () {
    test('dtc_present: P0420 and P0171 are stored, and nothing is pending', () {
      final rig = _SimRig(DriveScenarios.dtcPresent);
      addTearDown(rig.close);

      final result = rig.read();

      expect(result.ok, isTrue);
      expect(_codes(result.stored), ['P0420', 'P0171']);
      expect(result.pending, isEmpty);
    });

    test('a car with no codes has none', () {
      final rig = _SimRig(_idle());
      addTearDown(rig.close);

      final result = rig.read();

      expect(result.ok, isTrue);
      expect(result.stored, isEmpty);
      expect(result.pending, isEmpty);
    });

    test('a pending code is read as pending', () {
      final rig = _SimRig(
        _idle(
          dtcs: const [
            DtcInjection(
              at: Duration.zero,
              code: 'P0300',
              kind: DtcKind.pending,
            ),
          ],
        ),
      );
      addTearDown(rig.close);

      final result = rig.read();

      expect(result.stored, isEmpty);
      expect(_codes(result.pending), ['P0300']);
    });

    test('stored and pending together', () {
      final rig = _SimRig(
        _idle(
          dtcs: const [
            DtcInjection(at: Duration.zero, code: 'P0420'),
            DtcInjection(
              at: Duration.zero,
              code: 'P0300',
              kind: DtcKind.pending,
            ),
          ],
        ),
      );
      addTearDown(rig.close);

      final result = rig.read();

      expect(_codes(result.stored), ['P0420']);
      expect(_codes(result.pending), ['P0300']);
    });

    test(
      'many codes come in a message of several frames, and are all read',
      () {
        final codes = [
          'P0420',
          'P0171',
          'P0300',
          'C0300',
          'B1000',
          'U0100',
          'P2002',
        ];
        final rig = _SimRig(
          _idle(
            dtcs: [
              for (final c in codes) DtcInjection(at: Duration.zero, code: c),
            ],
          ),
        );
        addTearDown(rig.close);

        final result = rig.read();

        // 2 + 14 bytes: a first frame and two consecutive ones.
        expect(_codes(result.stored), codes);
      },
    );
  });

  group('reading, with scripted answers', () {
    late FakeClock clock;
    late FakeTransport transport;
    late Elm327Client client;
    late DtcService service;

    void setUp(Map<String, List<Say?>> script) {
      clock = FakeClock();
      transport = FakeTransport(clock: clock);
      client = Elm327Client(
        transport: transport,
        scheduler: clock,
        clock: clock,
      );
      ScriptedAdapter(transport, clock, script);
      service = DtcService(
        client: client,
        scheduler: clock,
        isCan: true,
        isStationary: () => true,
      );
    }

    tearDown(() {
      client.dispose();
      transport.dispose();
    });

    DtcReadResult read() {
      DtcReadResult? result;
      service.read((r) => result = r);
      clock.advance(const Duration(seconds: 10));
      return result!;
    }

    test('the commands are 03 and then 07, with no count digit', () {
      setUp({
        '03': [Say.ok('43 00')],
        '07': [Say.ok('47 00')],
      });

      read();

      expect(transport.writes, ['03\r', '07\r']);
    });

    test('two ECUs give the union', () {
      setUp({
        '03': [Say.ok('43 02 04 20 01 71\r43 01 07 00')],
        '07': [Say.ok('47 00')],
      });

      final result = read();

      expect(_codes(result.stored), ['P0420', 'P0171', 'P0700']);
    });

    test(
      'a failure reading the stored codes is reported, and the pending are still read',
      () {
        setUp({
          '03': [Say.ok('NO DATA')],
          '07': [Say.ok('47 01 03 00')],
        });

        final result = read();

        expect(result.ok, isFalse);
        expect(result.failure, Elm327Failure.noData);
        expect(result.stored, isEmpty);
        expect(_codes(result.pending), ['P0300']);
      },
    );

    test(
      'a negative response is a failure, not "no codes", and comes at once',
      () {
        setUp({
          '03': [Say.ok('7F 03 11')],
          '07': [Say.ok('47 00')],
        });
        DtcReadResult? result;

        service.read((r) => result = r);
        clock.advance(const Duration(milliseconds: 100));

        // Not the 1.5 s of a timeout: the refusal is an answer.
        expect(result, isNotNull);
        expect(result!.failure, Elm327Failure.noData);
        expect(result!.stored, isEmpty);
      },
    );

    test('a late answer to a poll is not taken for the codes', () {
      setUp({
        '03': [
          Say(
            '41 0C 1A F8\r\r>',
            afterMs: 10,
            then: [Say.ok('43 01 04 20', afterMs: 30)],
          ),
        ],
        '07': [Say.ok('47 00')],
      });

      final result = read();

      expect(_codes(result.stored), ['P0420']);
    });

    test('an ECU that says nothing is a timeout', () {
      setUp({
        '03': [Say.silence],
        '07': [Say.silence],
      });

      final result = read();

      expect(result.failure, Elm327Failure.timeout);
    });

    test('noise in the answer is a failure, not wrong codes', () {
      setUp({
        '03': [Say.ok('43 01 04 2\x7F')],
        '07': [Say.ok('47 00')],
      });

      final result = read();

      expect(result.failure, Elm327Failure.garbled);
      expect(result.stored, isEmpty);
    });
  });

  group('clearing', () {
    test('at a standstill it clears the codes, and the light', () {
      final rig = _SimRig(_stillWithCodes());
      addTearDown(rig.close);
      expect(rig.car.milOn, isTrue);

      final outcome = rig.clear();

      expect(outcome, DtcClearOutcome.cleared);
      expect(rig.car.storedDtcs, isEmpty);
      expect(rig.car.milOn, isFalse);
      expect(_codes(rig.read().stored), isEmpty);
    });

    test(
      'while moving, it is refused before the ECU is asked (CLAUDE.md 8.10)',
      () {
        final rig = _SimRig(DriveScenarios.dtcPresent, stationary: () => false);
        addTearDown(rig.close);
        final sent = rig.client.commandsSent;

        final outcome = rig.clear();

        expect(outcome, DtcClearOutcome.notStationary);
        expect(rig.client.commandsSent, sent, reason: 'nothing was sent');
        expect(rig.car.storedDtcs, isNotEmpty);
      },
    );

    test('and never by calling back from inside the call', () {
      final rig = _SimRig(DriveScenarios.dtcPresent, stationary: () => false);
      addTearDown(rig.close);
      var called = false;

      rig.service.clear((_) => called = true);

      expect(called, isFalse);
      rig.clock.advance(Duration.zero);
      expect(called, isTrue);
    });

    test('an ECU that is asked while the car is moving says no, 7F 04 22', () {
      // The service is told the car is still; the ECU knows better.
      final rig = _SimRig(DriveScenarios.dtcPresent, stationary: () => true);
      addTearDown(rig.close);
      while (rig.car.state.speedMs < 3) {
        rig.clock.advance(const Duration(milliseconds: 200));
      }

      final outcome = rig.clear();

      expect(outcome, DtcClearOutcome.refusedByEcu);
      expect(rig.car.storedDtcs, isNotEmpty);
      expect(rig.car.milOn, isTrue);
    });

    test(
      'with the car known to be at 0 and really at rest, it works: the two agree',
      () {
        final rig = _SimRig(_stillWithCodes());
        addTearDown(rig.close);
        expect(rig.car.state.speedMs, 0);

        expect(rig.clear(), DtcClearOutcome.cleared);
      },
    );
  });

  group('clearing, with scripted answers', () {
    late FakeClock clock;
    late FakeTransport transport;
    late Elm327Client client;
    late DtcService service;

    void setUp(Map<String, List<Say?>> script, {bool stationary = true}) {
      clock = FakeClock();
      transport = FakeTransport(clock: clock);
      client = Elm327Client(
        transport: transport,
        scheduler: clock,
        clock: clock,
      );
      ScriptedAdapter(transport, clock, script);
      service = DtcService(
        client: client,
        scheduler: clock,
        isCan: true,
        isStationary: () => stationary,
      );
    }

    tearDown(() {
      client.dispose();
      transport.dispose();
    });

    DtcClearOutcome clear() {
      DtcClearOutcome? result;
      service.clear((r) => result = r);
      clock.advance(const Duration(seconds: 5));
      return result!;
    }

    test('44 is cleared', () {
      setUp({
        '04': [Say.ok('44')],
      });

      expect(clear(), DtcClearOutcome.cleared);
      expect(transport.writes, ['04\r']);
    });

    test('7F 04 22 is refused by the ECU', () {
      setUp({
        '04': [Say.ok('7F 04 22')],
      });

      expect(clear(), DtcClearOutcome.refusedByEcu);
    });

    test('any negative response to 04 is a refusal', () {
      setUp({
        '04': [Say.ok('7F 04 12')],
      });

      expect(clear(), DtcClearOutcome.refusedByEcu);
    });

    test('no answer is a failure', () {
      setUp({
        '04': [Say.silence],
      });

      expect(clear(), DtcClearOutcome.failed);
    });

    test('NO DATA is a failure', () {
      setUp({
        '04': [Say.ok('NO DATA')],
      });

      expect(clear(), DtcClearOutcome.failed);
    });

    test('a late poll answer is not taken for the reply', () {
      setUp({
        '04': [
          Say(
            '41 0C 1A F8\r\r>',
            afterMs: 10,
            then: [Say.ok('44', afterMs: 30)],
          ),
        ],
      });

      expect(clear(), DtcClearOutcome.cleared);
    });

    test('a car that is not known to be at rest is never asked', () {
      setUp({
        '04': [Say.ok('44')],
      }, stationary: false);

      expect(clear(), DtcClearOutcome.notStationary);
      expect(transport.writes, isEmpty);
    });
  });
}
