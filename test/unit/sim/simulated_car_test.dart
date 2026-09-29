import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/sim/drive_scenario.dart';
import 'package:tapedash/sim/drive_style.dart';
import 'package:tapedash/sim/driver.dart';
import 'package:tapedash/sim/scenario_events.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/sim_route.dart';
import 'package:tapedash/sim/simulated_car.dart';
import 'package:tapedash/sim/vehicle_model.dart';

/// A scenario that only idles, with fault codes appearing at chosen times.
DriveScenario _idleScenario({
  Duration? duration,
  List<DtcInjection> dtcs = const [],
  double idleSeconds = 100000,
}) => DriveScenario(
  name: 'test',
  description: 'test',
  route: SimRoute.straight(100),
  duration: duration,
  dtcs: dtcs,
  driverBuilder: () => ScriptedDriver([IdleFor(idleSeconds)]),
);

void main() {
  group('stopWhenFinished', () {
    // Cruising at 60 km/h for the whole of a two-minute scenario: it is cut off
    // by its time, mid-drive.
    DriveScenario cruise() => DriveScenario(
      name: 'cruise',
      description: 'cruise',
      route: SimRoute.straight(20000),
      duration: const Duration(minutes: 2),
      driverBuilder: () => ScriptedDriver([
        GoToSpeed(60, style: DriveStyle.gentle, holdSeconds: 1000),
      ]),
    );

    test('a scenario cut off mid-drive brakes to a stop, gently', () {
      final car = SimulatedCar(scenario: cruise(), stopWhenFinished: true);
      car.runToEnd();
      expect(car.isFinished, isTrue);
      expect(car.state.speedKmh, greaterThan(40));

      var hardest = 0.0;
      var before = car.state.speedMs;
      for (var i = 0; i < 20 * 60 && car.state.speedMs > 0; i++) {
        car.tick();
        hardest = hardest > before - car.state.speedMs
            ? hardest
            : before - car.state.speedMs;
        before = car.state.speedMs;
      }
      expect(car.state.speedMs, 0);
      // Under 3 m/s2 (a step is 50 ms): well short of a hard braking.
      expect(hardest / VehicleModel.stepSeconds, lessThan(3));
    });

    test('by default the plan is the ground truth, however it ends', () {
      final car = SimulatedCar(scenario: cruise());
      car.runToEnd();
      for (var i = 0; i < 20 * 20; i++) {
        car.tick();
      }
      expect(car.state.speedKmh, greaterThan(40));
    });
  });

  group('running on a scheduler', () {
    test('one step every 50 ms of scheduled time', () {
      final clock = FakeClock();
      final car = SimulatedCar(scenario: _idleScenario(), scheduler: clock)
        ..start();

      clock.advance(const Duration(seconds: 1));
      expect(car.elapsedSeconds, closeTo(1.0, 1e-9));

      clock.advance(const Duration(milliseconds: 40));
      expect(
        car.elapsedSeconds,
        closeTo(1.0, 1e-9),
        reason: 'not yet another step',
      );

      clock.advance(const Duration(milliseconds: 10));
      expect(car.elapsedSeconds, closeTo(1.05, 1e-9));
    });

    test('starting twice does not double the pace', () {
      final clock = FakeClock();
      final car = SimulatedCar(scenario: _idleScenario(), scheduler: clock)
        ..start()
        ..start();

      clock.advance(const Duration(seconds: 2));

      expect(car.elapsedSeconds, closeTo(2.0, 1e-9));
      expect(clock.pendingTasks, 1);
    });

    test('stop ends the stepping, and it can start again', () {
      final clock = FakeClock();
      final car = SimulatedCar(scenario: _idleScenario(), scheduler: clock)
        ..start();
      clock.advance(const Duration(seconds: 1));
      expect(car.isRunning, isTrue);

      car.stop();
      clock.advance(const Duration(seconds: 5));

      expect(car.isRunning, isFalse);
      expect(car.elapsedSeconds, closeTo(1.0, 1e-9));
      expect(clock.pendingTasks, 0);

      car.start();
      clock.advance(const Duration(seconds: 1));
      expect(car.elapsedSeconds, closeTo(2.0, 1e-9));
    });

    test('starting needs a scheduler', () {
      expect(
        () => SimulatedCar(scenario: _idleScenario()).start(),
        throwsStateError,
      );
    });

    test('a scheduled run and a direct run give the same drive', () {
      final clock = FakeClock();
      final scheduled = SimulatedCar(
        scenario: DriveScenarios.cityStopGo,
        scheduler: clock,
      )..start();
      clock.advance(const Duration(minutes: 20));
      final direct = SimulatedCar(scenario: DriveScenarios.cityStopGo)
        ..runToEnd();

      expect(
        scheduled.truth.distanceKm,
        closeTo(direct.truth.distanceKm, 0.01),
      );
      expect(
        scheduled.truth.fuelLitres,
        closeTo(direct.truth.fuelLitres, 0.001),
      );
    });

    test('30 minutes of scheduled time run in a few seconds', () {
      final clock = FakeClock();
      SimulatedCar(
        scenario: DriveScenarios.highwayCruise,
        scheduler: clock,
      ).start();
      final watch = Stopwatch()..start();

      clock.advance(const Duration(minutes: 30));

      expect(watch.elapsed.inSeconds, lessThan(30));
    });
  });

  group('when the scenario is over', () {
    test('a timed scenario is finished when its time is up', () {
      final car = SimulatedCar(
        scenario: _idleScenario(duration: const Duration(seconds: 10)),
      );
      for (var i = 0; i < 199; i++) {
        car.tick();
      }
      expect(car.isFinished, isFalse);

      car.tick();

      expect(car.isFinished, isTrue);
    });

    test('an untimed scenario is finished when its driver has finished', () {
      final car = SimulatedCar(scenario: DriveScenarios.aggressiveCity);
      expect(car.isFinished, isFalse);

      car.runToEnd();

      expect(car.isFinished, isTrue);
    });

    test('the car carries on idling after the end', () {
      final car = SimulatedCar(scenario: DriveScenarios.aggressiveCity)
        ..runToEnd();
      final end = car.elapsedSeconds;

      for (var i = 0; i < 200; i++) {
        car.tick();
      }

      expect(car.elapsedSeconds, closeTo(end + 10, 1e-6));
      expect(car.state.speedMs, 0);
      expect(car.state.engineRunning, isTrue);
    });

    test(
      'runToEnd stops at its limit if the scenario would go on for ever',
      () {
        final car = SimulatedCar(scenario: _idleScenario());

        final ran = car.runToEnd(limit: const Duration(seconds: 30));

        expect(ran, closeTo(30, 0.1));
        expect(car.isFinished, isFalse);
      },
    );

    test('runToEnd returns the seconds run', () {
      final car = SimulatedCar(
        scenario: _idleScenario(duration: const Duration(seconds: 12)),
      );

      expect(car.runToEnd(), closeTo(12, 0.1));
    });
  });

  group('restarting', () {
    test('goes back to the beginning, with a fresh car and driver', () {
      final car = SimulatedCar(scenario: DriveScenarios.cityStopGo);
      while (car.elapsedSeconds < 200) {
        car.tick();
      }
      expect(car.truth.distanceKm, greaterThan(0.1));

      car.restart();

      expect(car.elapsedSeconds, 0);
      expect(car.truth.distanceKm, 0);
      expect(car.state.engineState, EngineState.off);
    });

    test('a restarted drive is the same drive again', () {
      final car = SimulatedCar(scenario: DriveScenarios.cityStopGo);
      while (car.elapsedSeconds < 300) {
        car.tick();
      }
      final firstDistance = car.truth.distanceKm;
      final firstFuel = car.truth.fuelLitres;

      car.restart();
      while (car.elapsedSeconds < 300) {
        car.tick();
      }

      expect(car.truth.distanceKm, firstDistance);
      expect(car.truth.fuelLitres, firstFuel);
    });

    test('forgets fault codes', () {
      final car = SimulatedCar(scenario: DriveScenarios.dtcPresent)..tick();
      expect(car.storedDtcs, isNotEmpty);

      car.restart();

      expect(car.storedDtcs, isEmpty);
    });
  });

  group('how the scenario starts the car', () {
    test('a cold start begins with the engine at ambient temperature', () {
      final car = SimulatedCar(scenario: DriveScenarios.cityStopGo);

      expect(car.state.coolantC, 30);
      expect(car.state.engineState, EngineState.off);
    });

    test('a scenario can start with the engine already warm and running', () {
      final car = SimulatedCar(scenario: DriveScenarios.spiritedRevs);

      expect(car.state.engineRunning, isTrue);
      expect(car.state.coolantC, 90);
    });

    test('the profile can be overridden', () {
      final car = SimulatedCar(
        scenario: DriveScenarios.cityStopGo,
        profile: DriveScenarios.spiritedRevs.profile,
      );

      expect(car.model.profile.name, 'petrol_manual_sporty');
    });

    test('a different seed changes only the reported wobble', () {
      final a = SimulatedCar(scenario: DriveScenarios.coldStartIdle, seed: 1);
      final b = SimulatedCar(scenario: DriveScenarios.coldStartIdle, seed: 2);
      for (var i = 0; i < 400; i++) {
        a.tick();
        b.tick();
      }

      expect(a.state.rpm, isNot(b.state.rpm));
      expect(a.truth.fuelLitres, b.truth.fuelLitres);
    });
  });

  group('fault codes', () {
    test('appear at their time, in order', () {
      final car = SimulatedCar(
        scenario: _idleScenario(
          dtcs: const [
            DtcInjection(at: Duration(seconds: 5), code: 'P0420'),
            DtcInjection(at: Duration(seconds: 10), code: 'P0171'),
          ],
        ),
      );

      while (car.elapsedSeconds < 4.9) {
        car.tick();
      }
      expect(car.storedDtcs, isEmpty);
      expect(car.milOn, isFalse);

      while (car.elapsedSeconds < 5.1) {
        car.tick();
      }
      expect(car.storedDtcs, ['P0420']);
      expect(car.milOn, isTrue);

      while (car.elapsedSeconds < 10.1) {
        car.tick();
      }
      expect(car.storedDtcs, ['P0420', 'P0171']);
    });

    test(
      'a pending code does not light the check-engine light, and becomes stored later',
      () {
        final car = SimulatedCar(
          scenario: _idleScenario(
            dtcs: const [
              DtcInjection(
                at: Duration(seconds: 2),
                code: 'P0300',
                kind: DtcKind.pending,
              ),
              DtcInjection(at: Duration(seconds: 8), code: 'P0300'),
            ],
          ),
        );

        while (car.elapsedSeconds < 3) {
          car.tick();
        }
        expect(car.pendingDtcs, ['P0300']);
        expect(car.storedDtcs, isEmpty);
        expect(car.milOn, isFalse);

        while (car.elapsedSeconds < 9) {
          car.tick();
        }
        expect(
          car.pendingDtcs,
          isEmpty,
          reason: 'it moved from pending to stored',
        );
        expect(car.storedDtcs, ['P0300']);
        expect(car.milOn, isTrue);
      },
    );

    test('the same code is never stored twice', () {
      final car = SimulatedCar(
        scenario: _idleScenario(
          dtcs: const [
            DtcInjection(at: Duration.zero, code: 'P0420'),
            DtcInjection(at: Duration(seconds: 1), code: 'P0420'),
          ],
        ),
      );

      for (var i = 0; i < 100; i++) {
        car.tick();
      }

      expect(car.storedDtcs, ['P0420']);
    });

    test('a code that is already stored is not made pending', () {
      final car = SimulatedCar(
        scenario: _idleScenario(
          dtcs: const [
            DtcInjection(at: Duration.zero, code: 'P0420'),
            DtcInjection(
              at: Duration(seconds: 1),
              code: 'P0420',
              kind: DtcKind.pending,
            ),
          ],
        ),
      );

      for (var i = 0; i < 100; i++) {
        car.tick();
      }

      expect(car.pendingDtcs, isEmpty);
    });

    test(
      'clearing removes stored and pending codes, and they do not come back',
      () {
        final car = SimulatedCar(
          scenario: _idleScenario(
            dtcs: const [
              DtcInjection(at: Duration.zero, code: 'P0420'),
              DtcInjection(
                at: Duration.zero,
                code: 'P0300',
                kind: DtcKind.pending,
              ),
            ],
          ),
        )..tick();
        expect(car.storedDtcs, isNotEmpty);
        expect(car.pendingDtcs, isNotEmpty);

        car.clearDtcs();
        for (var i = 0; i < 100; i++) {
          car.tick();
        }

        expect(car.storedDtcs, isEmpty);
        expect(car.pendingDtcs, isEmpty);
        expect(car.milOn, isFalse);
      },
    );

    test('the lists cannot be changed from outside', () {
      final car = SimulatedCar(scenario: DriveScenarios.dtcPresent)..tick();

      expect(() => car.storedDtcs.add('P9999'), throwsUnsupportedError);
      expect(() => car.pendingDtcs.add('P9999'), throwsUnsupportedError);
    });
  });
}
