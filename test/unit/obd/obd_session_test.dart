import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/dtc/dtc_service.dart';
import 'package:tapedash/obd/elm327/elm327_client.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/obd/poller.dart';
import 'package:tapedash/obd/transport/sim_transport.dart';
import 'package:tapedash/obd/transport/transport.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/drive_scenario.dart';
import 'package:tapedash/sim/driver.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenario_events.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/sim_route.dart';
import 'package:tapedash/sim/simulated_car.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../../support/fake_transport.dart';
import '../../support/scripted_adapter.dart';

Duration ms(int n) => Duration(milliseconds: n);

DriveScenario _idleRunning({
  List<AdapterFault> faults = const [],
  AdapterQuirks quirks = AdapterQuirks.none,
  List<DriveLeg>? legs,
  bool engineRunningAtStart = true,
}) => DriveScenario(
  name: 'test',
  description: 'idles, warm and running',
  route: SimRoute.straight(100),
  adapterFaults: faults,
  quirks: quirks,
  startCoolantC: 90,
  engineRunningAtStart: engineRunningAtStart,
  driverBuilder: () => ScriptedDriver(legs ?? [IdleFor(100000)]),
);

/// A simulated car on a simulated link, with a session on it and a record of
/// what the session said.
class _Rig {
  _Rig(
    DriveScenario scenario, {
    AdapterMemory? memory,
    SessionConfig config = const SessionConfig(),
    int seed = 1,
    bool start = true,
  }) {
    car = SimulatedCar(scenario: scenario, scheduler: clock, seed: seed)
      ..start();
    transport = SimTransport(car: car, scheduler: clock, seed: seed);
    vehicle = VehicleState(clock: clock, scheduler: clock);
    session = ObdSession(
      transport: transport,
      scheduler: clock,
      clock: clock,
      vehicle: vehicle,
      memory: memory,
      config: config,
    );
    session.status.addListener(() {
      statuses.add((clock.monotonic(), session.status.value));
    });
    if (start) session.start();
  }

  final clock = FakeClock();
  late final SimulatedCar car;
  late final SimTransport transport;
  late final VehicleState vehicle;
  late final ObdSession session;

  /// Each change of status, with when it happened.
  final List<(Duration, ConnectionStatus)> statuses = [];

  List<ConnectionStatus> get sequence => [for (final s in statuses) s.$2];

  ConnectionStatus get status => session.status.value;

  void run(int seconds) => clock.advance(Duration(seconds: seconds));

  /// Runs until [condition] holds, and returns the time it took.
  Duration runUntil(bool Function() condition, {int limitSeconds = 120}) {
    final start = clock.monotonic();
    final limit = start + Duration(seconds: limitSeconds);
    while (!condition() && clock.monotonic() < limit) {
      clock.advance(ms(50));
    }
    expect(condition(), isTrue, reason: 'not within $limitSeconds s');
    return clock.monotonic() - start;
  }

  void close() {
    session.dispose();
    vehicle.dispose();
    car.stop();
    transport.dispose();
  }
}

void main() {
  group('connecting', () {
    test('it is searching, and then connected, with what start-up found', () {
      final rig = _Rig(_idleRunning());
      addTearDown(rig.close);
      expect(rig.status, ConnectionStatus.searching);

      rig.runUntil(() => rig.status == ConnectionStatus.connected);

      final info = rig.session.adapterInfo.value!;
      expect(info.banner, 'ELM327 v1.5');
      expect(info.protocolNumber, '6');
      expect(info.supportedPids, {
        0x01,
        ...VehicleProfiles.petrolCvtMaf.supportedPids,
      });
      expect(rig.sequence, [
        ConnectionStatus.searching,
        ConnectionStatus.connected,
      ]);
      expect(rig.session.poller!.isRunning, isTrue);
      expect(rig.session.problem.value, isNull);
    });

    test('in about five seconds: the settle, the reset and the search', () {
      final rig = _Rig(_idleRunning());
      addTearDown(rig.close);

      final took = rig.runUntil(() => rig.status == ConnectionStatus.connected);

      expect(took.inMilliseconds, inInclusiveRange(3500, 6500));
    });

    test('it starts before start() is called: stopped', () {
      final rig = _Rig(_idleRunning(), start: false);
      addTearDown(rig.close);

      expect(rig.status, ConnectionStatus.stopped);
      expect(rig.session.isRunning, isFalse);
      rig.run(5);
      expect(rig.car.elapsedSeconds, greaterThan(4));
      expect(rig.session.client.commandsSent, 0);
    });

    test('and remembers the protocol for next time', () {
      final memory = InMemoryAdapterMemory();
      final rig = _Rig(_idleRunning(), memory: memory);
      addTearDown(rig.close);

      rig.runUntil(() => rig.status == ConnectionStatus.connected);

      expect(memory.protocol, '6');
    });

    test('a remembered protocol saves the search', () {
      final first = _Rig(_idleRunning());
      addTearDown(first.close);
      final slow = first.runUntil(
        () => first.status == ConnectionStatus.connected,
      );
      final second = _Rig(_idleRunning(), memory: InMemoryAdapterMemory('6'));
      addTearDown(second.close);

      final fast = second.runUntil(
        () => second.status == ConnectionStatus.connected,
      );

      expect(fast, lessThan(slow - const Duration(seconds: 1)));
    });

    test(
      'a wrong remembered protocol is corrected, and the new one remembered',
      () {
        final memory = InMemoryAdapterMemory('3');
        final rig = _Rig(_idleRunning(), memory: memory);
        addTearDown(rig.close);

        rig.runUntil(() => rig.status == ConnectionStatus.connected);

        expect(memory.protocol, '6');
      },
    );

    test('starting twice is one session', () {
      final rig = _Rig(_idleRunning());
      addTearDown(rig.close);

      rig.session.start();
      rig.runUntil(() => rig.status == ConnectionStatus.connected);

      expect(rig.sequence, [
        ConnectionStatus.searching,
        ConnectionStatus.connected,
      ]);
    });

    test('a transport that is already connected is used as it is', () {
      final rig = _Rig(_idleRunning(), start: false);
      addTearDown(rig.close);
      rig.transport.connect().catchError((Object _) {});
      rig.run(1);
      expect(rig.transport.currentState, TransportState.connected);

      rig.session.start();
      rig.runUntil(() => rig.status == ConnectionStatus.connected);

      expect(rig.status, ConnectionStatus.connected);
    });
  });

  group('values reach the vehicle', () {
    test('every polled sensor is read, and matches the car', () {
      final rig = _Rig(_idleRunning());
      addTearDown(rig.close);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);

      rig.run(10);

      final s = rig.car.state;
      expect(rig.vehicle.rpm.value!.value, closeTo(s.rpm, 25));
      expect(rig.vehicle.coolant.value!.value, closeTo(s.coolantC, 1));
      expect(rig.vehicle.speed.value!.value, 0);
      for (final sensor in [
        Sensor.rpm,
        Sensor.speed,
        Sensor.throttle,
        Sensor.load,
        Sensor.coolant,
        Sensor.intakeAir,
        Sensor.airFlow,
        Sensor.fuelLevel,
        Sensor.voltage,
      ]) {
        expect(
          rig.vehicle.reading(sensor).value,
          isNotNull,
          reason: sensor.name,
        );
      }
      // A MAF car has no MAP or fuel rate polled by default.
      expect(rig.vehicle.manifoldPressure.value, isNull);
      expect(rig.vehicle.fuelRate.value, isNull);
    });

    test('they are fresh', () {
      final rig = _Rig(_idleRunning());
      addTearDown(rig.close);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);

      rig.run(10);

      expect(rig.vehicle.isStale(Sensor.rpm), isFalse);
      expect(rig.vehicle.isStale(Sensor.voltage), isFalse);
    });

    test('the ignition and the engine are known', () {
      final rig = _Rig(_idleRunning());
      addTearDown(rig.close);
      expect(rig.vehicle.ignition.value, IgnitionState.unknown);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);

      rig.run(3);

      expect(rig.vehicle.ignition.value, IgnitionState.on);
      expect(rig.vehicle.engineRunning.value, isTrue);
    });

    test('the sample time is a little before the arrival time', () {
      final rig = _Rig(_idleRunning());
      addTearDown(rig.close);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);
      rig.run(3);

      final r = rig.vehicle.rpm.value!;

      // A perfect link: the ECU's 20 ms, and the sample at the middle of it.
      expect((r.receivedAt - r.at).inMilliseconds, inInclusiveRange(9, 11));
    });

    test('a car with MAP and no MAF has MAP read, and no MAF', () {
      final rig = _Rig(
        DriveScenario(
          name: 'map',
          description: 'a car with no MAF',
          route: SimRoute.straight(100),
          profile: VehicleProfiles.petrolCvtMap,
          startCoolantC: 90,
          engineRunningAtStart: true,
          driverBuilder: () => ScriptedDriver([IdleFor(100000)]),
        ),
      );
      addTearDown(rig.close);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);

      rig.run(10);

      expect(rig.vehicle.manifoldPressure.value, isNotNull);
      expect(rig.vehicle.airFlow.value, isNull);
    });
  });

  group('the ignition going off and on', () {
    // Ignition off for 20 s, part way through a drive.
    DriveScenario cycle() =>
        DriveScenarios.mixedCommute(ignitionOff: const Duration(seconds: 20));

    test('the session sees the car go quiet, waits, and finds it again', () {
      final rig = _Rig(cycle());
      addTearDown(rig.close);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);

      rig.runUntil(
        () => rig.status == ConnectionStatus.waitingForIgnition,
        limitSeconds: 600,
      );
      final offAt = rig.clock.monotonic();
      expect(rig.vehicle.ignition.value, IgnitionState.off);
      expect(rig.vehicle.mode.value, DrivingMode.parked);
      expect(rig.vehicle.engineRunning.value, isFalse);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);

      expect(rig.vehicle.ignition.value, IgnitionState.on);
      expect(rig.session.reconnects, 0, reason: 'the link never went');
      expect(rig.sequence, [
        ConnectionStatus.searching,
        ConnectionStatus.connected,
        ConnectionStatus.waitingForIgnition,
        ConnectionStatus.connected,
      ]);
      // It takes a while to see, and a while to find again, but not a minute.
      expect(
        rig.clock.monotonic() - offAt,
        lessThan(const Duration(seconds: 40)),
      );
    });

    test('values freeze while it is off, and are stale', () {
      final rig = _Rig(cycle());
      addTearDown(rig.close);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);
      rig.runUntil(
        () => rig.status == ConnectionStatus.waitingForIgnition,
        limitSeconds: 600,
      );

      rig.run(3);

      expect(rig.vehicle.isStale(Sensor.rpm), isTrue);
    });

    test(
      'polling stops while it waits, and starts again with a new poller',
      () {
        final rig = _Rig(cycle());
        addTearDown(rig.close);
        rig.runUntil(() => rig.status == ConnectionStatus.connected);
        final first = rig.session.poller!;
        rig.runUntil(
          () => rig.status == ConnectionStatus.waitingForIgnition,
          limitSeconds: 600,
        );

        expect(rig.session.poller, isNull);
        expect(first.isRunning, isFalse);
        rig.runUntil(() => rig.status == ConnectionStatus.connected);

        expect(rig.session.poller, isNot(same(first)));
        expect(rig.session.poller!.isRunning, isTrue);
      },
    );

    test(
      'and while it waits, it asks the car about once a second, not in a flood',
      () {
        final rig = _Rig(cycle());
        addTearDown(rig.close);
        rig.runUntil(() => rig.status == ConnectionStatus.connected);
        rig.runUntil(
          () => rig.status == ConnectionStatus.waitingForIgnition,
          limitSeconds: 600,
        );
        final before = rig.session.client.commandsSent;

        rig.run(10);

        // Each probe is 0100 and, once in a while, the adapter's own delay.
        expect(rig.session.client.commandsSent - before, lessThan(20));
      },
    );

    test(
      'a car that is off when it connects is waited for, and then found',
      () {
        final rig = _Rig(
          _idleRunning(
            engineRunningAtStart: false,
            legs: [IgnitionOffFor(40), IdleFor(100000)],
          ),
        );
        addTearDown(rig.close);
        expect(rig.car.state.ignitionOn, isFalse);

        rig.runUntil(() => rig.status == ConnectionStatus.waitingForIgnition);
        expect(rig.vehicle.ignition.value, IgnitionState.off);
        expect(rig.vehicle.mode.value, DrivingMode.parked);
        rig.runUntil(() => rig.status == ConnectionStatus.connected);

        expect(rig.car.state.ignitionOn, isTrue);
        expect(rig.sequence, [
          ConnectionStatus.searching,
          ConnectionStatus.waitingForIgnition,
          ConnectionStatus.connected,
        ]);
        expect(rig.session.adapterInfo.value!.supportedPids, isNotEmpty);
      },
    );
  });

  group('a dropped link', () {
    DriveScenario dropping({int at = 20, int outage = 10}) => _idleRunning(
      faults: [
        AdapterDisconnect(
          at: Duration(seconds: at),
          outage: Duration(seconds: outage),
        ),
      ],
    );

    test('is lost, and then connected again', () {
      final rig = _Rig(dropping());
      addTearDown(rig.close);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);

      rig.runUntil(() => rig.status == ConnectionStatus.lost);
      expect(rig.car.elapsedSeconds, closeTo(20, 1));
      rig.runUntil(() => rig.status == ConnectionStatus.connected);

      expect(rig.sequence, [
        ConnectionStatus.searching,
        ConnectionStatus.connected,
        ConnectionStatus.lost,
        ConnectionStatus.connected,
      ]);
      expect(rig.session.reconnects, greaterThanOrEqualTo(1));
    });

    test('values hold and go stale while it is out, and resume after', () {
      final rig = _Rig(dropping());
      addTearDown(rig.close);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);
      rig.runUntil(() => rig.status == ConnectionStatus.lost);

      rig.run(3);
      expect(rig.vehicle.rpm.value, isNotNull, reason: 'the last value holds');
      expect(rig.vehicle.isStale(Sensor.rpm), isTrue);
      expect(rig.vehicle.ignition.value, IgnitionState.unknown);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);
      rig.run(3);

      expect(rig.vehicle.isStale(Sensor.rpm), isFalse);
      expect(rig.vehicle.ignition.value, IgnitionState.on);
    });

    test(
      'it tries again after 1, 2, 4 and 8 s while the adapter is out of reach',
      () {
        final rig = _Rig(dropping(outage: 30));
        addTearDown(rig.close);
        rig.runUntil(() => rig.status == ConnectionStatus.connected);
        final attempts = <Duration>[];
        rig.transport.state.listen((s) {
          if (s == TransportState.connecting) {
            attempts.add(rig.clock.monotonic());
          }
        });

        rig.runUntil(() => rig.status == ConnectionStatus.lost);
        final lostAt = rig.clock.monotonic();
        rig.run(40);

        // The first attempt 1 s after the drop, then 2, 4, 8, then every 10.
        final gaps = <int>[
          for (var i = 1; i < attempts.length; i++)
            (attempts[i] - attempts[i - 1]).inMilliseconds,
        ];
        expect((attempts.first - lostAt).inMilliseconds, closeTo(1000, 200));
        // Each gap is the wait, and the 0.4 s that a failed attempt takes.
        expect(gaps.take(4).map((g) => (g / 100).round() * 100), [
          2400,
          4400,
          8400,
          10400,
        ]);
      },
    );

    test(
      'the values it read before are not lost, and the ignition is unknown',
      () {
        final rig = _Rig(dropping(outage: 30));
        addTearDown(rig.close);
        rig.runUntil(() => rig.status == ConnectionStatus.connected);
        rig.run(5);
        final rpm = rig.vehicle.rpm.value!;

        rig.runUntil(() => rig.status == ConnectionStatus.lost);
        rig.run(10);

        expect(rig.vehicle.rpm.value!.value, closeTo(rpm.value, 100));
      },
    );

    test(
      'the second connection sets the protocol directly, so it is quicker',
      () {
        final rig = _Rig(dropping());
        addTearDown(rig.close);
        final first = rig.runUntil(
          () => rig.status == ConnectionStatus.connected,
        );
        rig.runUntil(() => rig.status == ConnectionStatus.lost);
        final lostAt = rig.clock.monotonic();

        rig.runUntil(() => rig.status == ConnectionStatus.connected);
        final again = rig.clock.monotonic() - lostAt;

        // 10 s outage, up to 10 s of backoff, and a start-up with no search.
        expect(again, lessThan(const Duration(seconds: 22)));
        expect(first, greaterThan(const Duration(seconds: 3)));
      },
    );

    test('it goes on after several drops', () {
      final rig = _Rig(
        _idleRunning(
          faults: const [
            AdapterDisconnect(
              at: Duration(seconds: 20),
              outage: Duration(seconds: 3),
            ),
            AdapterDisconnect(
              at: Duration(seconds: 60),
              outage: Duration(seconds: 3),
            ),
            AdapterDisconnect(
              at: Duration(seconds: 100),
              outage: Duration(seconds: 3),
            ),
          ],
        ),
      );
      addTearDown(rig.close);

      rig.run(140);

      expect(rig.status, ConnectionStatus.connected);
      expect(rig.sequence.where((s) => s == ConnectionStatus.lost).length, 3);
      expect(rig.session.reconnects, greaterThanOrEqualTo(3));
    });
  });

  group('an adapter that does not answer', () {
    late FakeClock clock;
    late FakeTransport transport;
    late VehicleState vehicle;
    late ObdSession session;
    late int connects;

    void setUp(Map<String, List<Say?>> script) {
      clock = FakeClock();
      transport = FakeTransport(clock: clock, connected: false);
      connects = 0;
      // A transport that can be connected, and counts how often it is asked.
      transport.onConnect = () => connects++;
      ScriptedAdapter(transport, clock, script);
      vehicle = VehicleState(clock: clock, scheduler: clock);
      session = ObdSession(
        transport: transport,
        scheduler: clock,
        clock: clock,
        vehicle: vehicle,
      );
    }

    tearDown(() {
      session.dispose();
      vehicle.dispose();
      transport.dispose();
    });

    test('is closed and tried again, and says so after three tries', () {
      setUp({
        'ATZ': [Say.silence],
      });
      session.start();

      clock.advance(const Duration(seconds: 25));
      expect(session.problem.value, isNull, reason: 'one failed run so far');
      clock.advance(const Duration(minutes: 2));

      expect(session.problem.value, ConnectionProblem.adapterSilent);
      expect(session.status.value, ConnectionStatus.searching);
      expect(connects, greaterThan(3));
    });

    test('it never floods the adapter', () {
      setUp({
        'ATZ': [Say.silence],
      });
      session.start();

      clock.advance(const Duration(minutes: 5));

      // Three ATZ a run, and a run every 12 s plus the backoff.
      expect(transport.writes.length, lessThan(90));
    });

    test(
      'an adapter that is not one it can use ends it, with no more tries',
      () {
        final script = {
          'ATZ': [Say.ok('ELM327 v1.5', afterMs: 100)],
          'ATE0': [Say.ok('OK')],
          'ATL0': [Say.ok('OK')],
          'ATS0': [Say.ok('OK')],
          'ATH0': [Say.ok('?')],
        };
        setUp(script);
        session.start();

        clock.advance(const Duration(minutes: 3));

        expect(session.problem.value, ConnectionProblem.incompatibleAdapter);
        expect(session.status.value, ConnectionStatus.searching);
        expect(connects, 1, reason: 'it did not come back for more');
      },
    );

    test('and can be started again, which tries again', () {
      setUp({
        'ATZ': [Say.ok('ELM327 v1.5', afterMs: 100)],
        'ATE0': [Say.ok('OK')],
        'ATL0': [Say.ok('OK')],
        'ATS0': [Say.ok('OK')],
        'ATH0': [Say.ok('?')],
      });
      session.start();
      clock.advance(const Duration(seconds: 30));
      expect(session.problem.value, ConnectionProblem.incompatibleAdapter);

      session.stop();
      session.start();
      clock.advance(const Duration(seconds: 30));

      expect(connects, 2);
    });
  });

  group('stopping', () {
    test('ends the traffic, closes the link and says stopped', () {
      final rig = _Rig(_idleRunning());
      addTearDown(rig.close);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);
      rig.run(3);

      rig.session.stop();
      final sent = rig.session.client.commandsSent;
      rig.run(10);

      expect(rig.status, ConnectionStatus.stopped);
      expect(rig.session.client.commandsSent, sent);
      expect(rig.transport.currentState, const TransportState.disconnected());
      expect(rig.vehicle.ignition.value, IgnitionState.unknown);
      expect(rig.session.poller, isNull);
    });

    test('it does not reconnect afterwards', () {
      final rig = _Rig(_idleRunning());
      addTearDown(rig.close);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);

      rig.session.stop();
      rig.run(60);

      expect(rig.transport.currentState, const TransportState.disconnected());
    });

    test('and it can be started again', () {
      final rig = _Rig(_idleRunning());
      addTearDown(rig.close);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);
      rig.session.stop();
      rig.run(2);

      rig.session.start();
      rig.runUntil(() => rig.status == ConnectionStatus.connected);

      expect(rig.session.poller!.isRunning, isTrue);
    });

    test('while it is still starting up, it stops', () {
      final rig = _Rig(_idleRunning());
      addTearDown(rig.close);
      rig.run(2);

      rig.session.stop();
      final sent = rig.session.client.commandsSent;
      rig.run(30);

      expect(rig.session.client.commandsSent, sent);
      expect(rig.status, ConnectionStatus.stopped);
    });

    test('disposing leaves nothing scheduled but the car', () {
      final rig = _Rig(_idleRunning());
      rig.runUntil(() => rig.status == ConnectionStatus.connected);

      rig.session.dispose();
      rig.vehicle.dispose();
      rig.car.stop();
      rig.run(1);
      rig.transport.dispose();

      expect(rig.clock.pendingTasks, 0);
    });
  });

  group('what is wanted', () {
    test('a demand is served, and can be released', () {
      final rig = _Rig(_idleRunning());
      addTearDown(rig.close);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);
      expect(rig.session.poller!.tierOf(0x10), PollTier.medium);

      final d = rig.session.demand({0x10: PollTier.fast});
      expect(rig.session.poller!.tierOf(0x10), PollTier.fast);
      d.release();

      expect(rig.session.poller!.tierOf(0x10), PollTier.medium);
    });

    test('a demand survives a reconnection', () {
      final rig = _Rig(
        _idleRunning(
          faults: const [
            AdapterDisconnect(
              at: Duration(seconds: 20),
              outage: Duration(seconds: 3),
            ),
          ],
        ),
      );
      addTearDown(rig.close);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);
      final d = rig.session.demand({0x10: PollTier.fast});

      rig.runUntil(() => rig.status == ConnectionStatus.lost);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);

      expect(rig.session.poller!.tierOf(0x10), PollTier.fast);
      d.release();
      expect(rig.session.poller!.tierOf(0x10), PollTier.medium);
    });

    test('a demand made before it connects is served once it does', () {
      final rig = _Rig(_idleRunning());
      addTearDown(rig.close);
      rig.session.demand({0x10: PollTier.fast});

      rig.runUntil(() => rig.status == ConnectionStatus.connected);

      expect(rig.session.poller!.tierOf(0x10), PollTier.fast);
    });

    test('releasing twice is harmless', () {
      final rig = _Rig(_idleRunning());
      addTearDown(rig.close);
      final d = rig.session.demand({0x10: PollTier.fast});

      d.release();
      d.release();
    });
  });

  group('the diagnostics', () {
    test('the poll rate is reported', () {
      final rig = _Rig(_idleRunning());
      addTearDown(rig.close);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);

      rig.run(10);

      expect(rig.session.pollRate.value, greaterThan(20));
    });

    test('the poll health is reported, and follows the car', () {
      final rig = _Rig(
        DriveScenarios.mixedCommute(ignitionOff: const Duration(seconds: 20)),
      );
      addTearDown(rig.close);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);
      expect(rig.session.pollHealth.value, PollHealth.ok);

      rig.runUntil(
        () => rig.status == ConnectionStatus.waitingForIgnition,
        limitSeconds: 600,
      );

      expect(rig.session.pollHealth.value, PollHealth.ecuSilent);
    });
  });

  group('fault codes through the session', () {
    test('they can be read once connected', () {
      final rig = _Rig(DriveScenarios.dtcPresent);
      addTearDown(rig.close);
      expect(rig.session.dtc, isNull);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);
      DtcReadResult? result;

      rig.session.dtc!.read((r) => result = r);
      rig.run(5);

      expect(result!.stored.map((d) => d.code), ['P0420', 'P0171']);
    });

    test(
      'clearing is refused while the car moves, by what the vehicle knows',
      () {
        final rig = _Rig(DriveScenarios.dtcPresent);
        addTearDown(rig.close);
        rig.runUntil(() => rig.status == ConnectionStatus.connected);
        rig.runUntil(() => rig.car.state.speedMs > 3);
        rig.run(2);
        DtcClearOutcome? outcome;

        rig.session.dtc!.clear((o) => outcome = o);
        rig.run(2);

        expect(outcome, DtcClearOutcome.notStationary);
        expect(rig.car.storedDtcs, isNotEmpty);
      },
    );

    test('and cleared when it is at rest', () {
      final rig = _Rig(_idleRunning());
      addTearDown(rig.close);
      rig.runUntil(() => rig.status == ConnectionStatus.connected);
      rig.run(5);
      DtcClearOutcome? outcome;

      rig.session.dtc!.clear((o) => outcome = o);
      rig.run(2);

      expect(outcome, DtcClearOutcome.cleared);
    });
  });

  group('a client that outlives the reconnections', () {
    test('is the same client throughout', () {
      final rig = _Rig(
        _idleRunning(
          faults: const [
            AdapterDisconnect(
              at: Duration(seconds: 15),
              outage: Duration(seconds: 3),
            ),
          ],
        ),
      );
      addTearDown(rig.close);
      final client = rig.session.client;

      rig.run(60);

      expect(rig.session.client, same(client));
      expect(client, isA<Elm327Client>());
      expect(rig.status, ConnectionStatus.connected);
    });
  });
}
