import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/sim/driver_inputs.dart';
import 'package:tapedash/sim/ground_truth.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/sim_random.dart';
import 'package:tapedash/sim/sim_route.dart';
import 'package:tapedash/sim/vehicle_model.dart';
import 'package:tapedash/sim/vehicle_profile.dart';

const _dt = VehicleModel.stepSeconds;

/// A car that is already running and warm.
VehicleModel _warm({VehicleProfile? profile, int seed = 1, SimRoute? route}) =>
    VehicleModel(
      profile: profile ?? VehicleProfiles.petrolCvtMaf,
      seed: seed,
      route: route,
      engineRunning: true,
      coolantC: 90,
    );

void _run(VehicleModel car, DriverInputs inputs, double seconds) {
  for (var i = 0; i < (seconds / _dt).round(); i++) {
    car.step(inputs);
  }
}

/// Drives to [kmh] and holds it for [seconds], like a steady driver.
void _cruise(VehicleModel car, double kmh, double seconds) {
  final target = kmh / 3.6;
  for (var i = 0; i < (seconds / _dt).round(); i++) {
    final wanted = ((target - car.state.speedMs) * 0.8).clamp(-1.5, 1.5);
    car.step(DriverInputs(throttle: car.pedalForAcceleration(wanted)));
  }
}

/// A manual car at about [kmh] with its gear settled, made without asking any
/// what-ifs so that the state does not depend on them.
VehicleModel _manualAt(VehicleProfile profile, double kmh) {
  final car = _warm(profile: profile);
  while (car.state.speedKmh < kmh) {
    car.step(const DriverInputs(throttle: 0.6));
  }
  _run(car, const DriverInputs(throttle: 0.25), 4);
  return car;
}

/// Every number in a snapshot, to compare runs exactly.
List<Object> _fingerprint(VehicleSnapshot s) => [
  s.timeSeconds,
  s.speedMs,
  s.distanceM,
  s.accelerationMs2,
  s.lateralAccelerationMs2,
  s.rpm,
  s.throttleFraction,
  s.loadFraction,
  s.manifoldKpa,
  s.airGramsPerSecond,
  s.fuelGramsPerSecond,
  s.coolantC,
  s.intakeAirC,
  s.voltage,
  s.fuelLevelFraction,
  s.fuelCut,
  s.gear,
  s.engineState,
];

void main() {
  group('starting the engine', () {
    test('a new car is parked with the ignition off, and the engine cold', () {
      final car = VehicleModel(profile: VehicleProfiles.petrolCvtMaf);
      final s = car.state;

      expect(s.ignitionOn, isFalse);
      expect(s.engineState, EngineState.off);
      expect(s.rpm, 0);
      expect(s.speedMs, 0);
      expect(s.coolantC, 30);
      expect(s.voltage, 12.4);
      expect(s.fuelRateLitresPerHour, 0);
    });

    test(
      'ignition on runs key-on, cranking and then running, in that order',
      () {
        final car = VehicleModel(profile: VehicleProfiles.petrolCvtMaf);
        final seen = <EngineState>[];
        for (var i = 0; i < 100; i++) {
          car.step(DriverInputs.idle);
          if (seen.isEmpty || seen.last != car.state.engineState) {
            seen.add(car.state.engineState);
          }
        }

        expect(seen, [
          EngineState.keyOn,
          EngineState.cranking,
          EngineState.running,
        ]);
      },
    );

    test('key-on lasts 1.5 s and cranking 0.9 s', () {
      final car = VehicleModel(profile: VehicleProfiles.petrolCvtMaf);
      double? crankAt;
      double? runAt;
      for (var i = 0; i < 100; i++) {
        car.step(DriverInputs.idle);
        final s = car.state;
        if (crankAt == null && s.engineState == EngineState.cranking) {
          crankAt = s.timeSeconds;
        }
        if (runAt == null && s.engineState == EngineState.running) {
          runAt = s.timeSeconds;
        }
      }

      expect(crankAt, closeTo(1.5, 0.1));
      expect(runAt! - crankAt!, closeTo(0.9, 0.1));
    });

    test(
      'battery voltage is 12.4 V with the ignition on, dips when cranking, and is about 14.1 V running',
      () {
        final car = VehicleModel(profile: VehicleProfiles.petrolCvtMaf);
        final volts = <EngineState, double>{};
        for (var i = 0; i < 100; i++) {
          car.step(DriverInputs.idle);
          volts[car.state.engineState] = car.state.voltage;
        }

        expect(volts[EngineState.keyOn], 12.4);
        expect(volts[EngineState.cranking], lessThan(11));
        expect(volts[EngineState.running], closeTo(14.1, 0.3));
      },
    );

    test(
      'the revs are 0 until cranking, about 200 while cranking, then rise to the idle',
      () {
        final car = VehicleModel(profile: VehicleProfiles.petrolCvtMaf);
        double rpmKeyOn = -1;
        double rpmCranking = -1;
        for (var i = 0; i < 200; i++) {
          car.step(DriverInputs.idle);
          final s = car.state;
          if (s.engineState == EngineState.keyOn) rpmKeyOn = s.rpm;
          if (s.engineState == EngineState.cranking) rpmCranking = s.rpm;
        }

        expect(rpmKeyOn, 0);
        expect(rpmCranking, inInclusiveRange(150, 260));
        expect(car.state.rpm, greaterThan(700));
      },
    );

    test('a cold engine idles fast at first and settles to the warm idle', () {
      final car = VehicleModel(
        profile: VehicleProfiles.petrolCvtMaf,
        coolantC: 25,
      );
      _run(car, DriverInputs.idle, 6);
      final cold = car.state.rpm;
      final coldTarget = car.state.rpm;
      _run(car, const DriverInputs(brake: 0.5), 400);

      expect(cold, greaterThan(1000));
      expect(coldTarget, greaterThan(car.state.rpm));
      expect(car.state.rpm, closeTo(750, 60));
    });

    test('a warm engine idles at the profile idle speed', () {
      final car = _warm();
      _run(car, const DriverInputs(brake: 0.5), 5);

      expect(car.state.rpm, closeTo(750, 20));
    });

    test('the ignition off stops the engine and the revs fall to 0', () {
      final car = _warm();
      _run(car, const DriverInputs(brake: 0.5), 3);
      _run(car, DriverInputs.off, 3);

      expect(car.state.engineState, EngineState.off);
      expect(car.state.rpm, 0);
      expect(car.state.voltage, 12.4);
      expect(car.state.fuelRateLitresPerHour, 0);
    });

    test('turning the ignition back on restarts the engine', () {
      final car = _warm();
      _run(car, DriverInputs.off, 3);
      _run(car, DriverInputs.idle, 5);

      expect(car.state.engineState, EngineState.running);
    });

    test('pressing the pedal before the engine runs does nothing', () {
      final car = VehicleModel(profile: VehicleProfiles.petrolCvtMaf);
      _run(car, const DriverInputs(throttle: 1), 1);

      expect(car.state.speedMs, 0);
      expect(car.state.engineState, isNot(EngineState.running));
    });
  });

  group('idling', () {
    test(
      'a warm petrol engine idles at about 30 kPa on 0.6 to 1.1 litres an hour',
      () {
        final car = _warm();
        _run(car, const DriverInputs(brake: 0.5), 10);
        final s = car.state;

        expect(s.speedMs, 0);
        expect(s.manifoldKpa, inInclusiveRange(28, 38));
        expect(s.fuelRateLitresPerHour, inInclusiveRange(0.6, 1.3));
        expect(s.fuelCut, isFalse);
      },
    );

    test(
      'a CVT car in drive creeps with the pedals up, and stops on the brake',
      () {
        final creeping = _warm();
        _run(creeping, DriverInputs.idle, 20);
        final held = _warm();
        _run(held, const DriverInputs(brake: 0.3), 20);

        expect(creeping.state.speedMs * 3.6, inInclusiveRange(2, 8));
        expect(held.state.speedMs, 0);
      },
    );

    test('a manual car does not creep', () {
      final car = _warm(profile: VehicleProfiles.petrolManualSporty);
      _run(car, DriverInputs.idle, 20);

      expect(car.state.speedMs, 0);
    });

    test(
      'a CVT car burns a little more in drive than a manual does in neutral',
      () {
        final cvt = _warm();
        final manual = _warm(profile: VehicleProfiles.petrolManualSporty);
        _run(cvt, const DriverInputs(brake: 0.5), 10);
        _run(manual, const DriverInputs(brake: 0.5), 10);

        expect(cvt.state.fuelRateLitresPerHour, greaterThan(0.5));
        expect(manual.state.fuelRateLitresPerHour, greaterThan(0.5));
      },
    );

    test('idle wobble is small', () {
      final car = _warm();
      _run(car, const DriverInputs(brake: 0.5), 5);
      final rpms = <double>[];
      for (var i = 0; i < 200; i++) {
        car.step(const DriverInputs(brake: 0.5));
        rpms.add(car.state.rpm);
      }

      expect(
        rpms.reduce(math.max) - rpms.reduce(math.min),
        inInclusiveRange(1, 30),
      );
    });
  });

  group('accelerating', () {
    test(
      'full throttle from a standstill gives more than 2.5 m/s2 for over a second, so a hard acceleration can be detected',
      () {
        final car = _warm();
        var secondsAbove = 0.0;
        for (var i = 0; i < 100; i++) {
          car.step(const DriverInputs(throttle: 1));
          if (car.state.accelerationMs2 > 2.5) secondsAbove += _dt;
        }

        expect(secondsAbove, greaterThan(3));
      },
    );

    test('0 to 100 km/h takes 8 to 12 seconds for the CVT hatch', () {
      final car = _warm();
      double? at100;
      for (var i = 0; i < 400 && at100 == null; i++) {
        car.step(const DriverInputs(throttle: 1));
        if (car.state.speedKmh >= 100) at100 = car.state.timeSeconds;
      }

      expect(at100, inInclusiveRange(8, 12));
    });

    test('a hard pull is limited by grip at first, and by power later', () {
      final car = _warm();
      _run(car, const DriverInputs(throttle: 1), 1);
      final early = car.state.accelerationMs2;
      _run(car, const DriverInputs(throttle: 1), 8);
      final late = car.state.accelerationMs2;

      expect(early, closeTo(0.36 * 9.81, 0.4));
      expect(late, lessThan(early));
      expect(late, greaterThan(0.5));
    });

    test('the top speed at full throttle is 150 to 230 km/h', () {
      final car = _warm();
      _run(car, const DriverInputs(throttle: 1), 90);

      expect(car.state.speedKmh, inInclusiveRange(150, 230));
    });

    test('a light pedal accelerates gently', () {
      final car = _warm();
      _run(car, const DriverInputs(throttle: 0.2), 5);

      expect(car.state.speedMs, greaterThan(0));
      expect(car.state.accelerationMs2, inInclusiveRange(0, 2));
    });

    test(
      'the fuel burnt in a full-throttle pull is more than the kinetic energy it gives, by energy conservation',
      () {
        final car = _warm();
        var fuelJoules = 0.0;
        for (var i = 0; i < 200; i++) {
          car.step(const DriverInputs(throttle: 1));
          fuelJoules += car.state.fuelGramsPerSecond * 44000 * _dt;
        }
        final speed = car.state.speedMs;
        final kinetic = 0.5 * 1150 * speed * speed;

        // Even a perfect petrol engine turns at most about 40% of the fuel's energy
        // into work.
        expect(kinetic, lessThan(0.40 * fuelJoules));
        // And a real one is not wildly inefficient either.
        expect(kinetic, greaterThan(0.05 * fuelJoules));
      },
    );

    test('the revs of a CVT car follow the pedal more than the speed', () {
      final gentle = _warm();
      final hard = _warm();
      _cruise(gentle, 50, 12);
      _run(hard, const DriverInputs(throttle: 1), 3);

      expect(gentle.state.rpm, inInclusiveRange(1200, 2200));
      expect(hard.state.rpm, greaterThan(4000));
    });

    test(
      'a hard pull reaches the CVT top revs but never passes the redline',
      () {
        final car = _warm();
        var top = 0.0;
        for (var i = 0; i < 400; i++) {
          car.step(const DriverInputs(throttle: 1));
          top = math.max(top, car.state.rpm);
        }

        expect(top, greaterThan(5000));
        expect(top, lessThanOrEqualTo(6500 + 20));
      },
    );
  });

  group('braking and coasting', () {
    test('full braking from 100 km/h is about 8 m/s2 at most', () {
      final car = _warm();
      _cruise(car, 100, 25);
      var peak = 0.0;
      while (car.state.speedMs > 0) {
        car.step(const DriverInputs(brake: 1));
        peak = math.max(peak, -car.state.accelerationMs2);
      }

      expect(peak, inInclusiveRange(7, 8.6));
    });

    test('100 to 0 km/h takes about 40 to 60 metres', () {
      final car = _warm();
      _cruise(car, 100, 25);
      final start = car.state.distanceM;
      while (car.state.speedMs > 0) {
        car.step(const DriverInputs(brake: 1));
      }

      expect(car.state.distanceM - start, inInclusiveRange(38, 62));
    });

    test('the speed is never negative, and the car stays put once stopped', () {
      final car = _warm();
      _cruise(car, 30, 10);
      for (var i = 0; i < 400; i++) {
        car.step(const DriverInputs(brake: 1));
        expect(car.state.speedMs, greaterThanOrEqualTo(0));
      }

      expect(car.state.speedMs, 0);
      final distance = car.state.distanceM;
      _run(car, const DriverInputs(brake: 1), 5);
      expect(car.state.distanceM, distance);
    });

    test('coasting with the pedals up slows the car by 0.2 to 0.9 m/s2', () {
      final car = _warm();
      _cruise(car, 60, 15);
      _run(car, DriverInputs.idle, 3);

      expect(-car.state.accelerationMs2, inInclusiveRange(0.2, 0.9));
    });

    test(
      'coasting above 1,500 rpm cuts the fuel, but the air keeps flowing',
      () {
        final car = _warm();
        _cruise(car, 60, 15);
        _run(car, DriverInputs.idle, 2);
        final s = car.state;

        expect(s.rpm, greaterThan(1400));
        expect(s.fuelCut, isTrue);
        expect(s.fuelGramsPerSecond, 0);
        expect(s.fuelRateLitresPerHour, 0);
        expect(
          s.airGramsPerSecond,
          greaterThan(1),
          reason: 'MAF stays non-zero with no fuel: the trap for estimators',
        );
      },
    );

    test('the fuel comes back when the revs fall below the cut-off', () {
      final car = _warm();
      _cruise(car, 60, 15);
      var cutAt = -1.0;
      var backAt = -1.0;
      for (var i = 0; i < 1200; i++) {
        car.step(DriverInputs.idle);
        final s = car.state;
        if (cutAt < 0 && s.fuelCut) cutAt = s.timeSeconds;
        if (cutAt > 0 && backAt < 0 && !s.fuelCut) backAt = s.timeSeconds;
      }

      expect(cutAt, greaterThan(0));
      expect(backAt, greaterThan(cutAt));
    });

    test('pressing the pedal ends the fuel cut at once', () {
      final car = _warm();
      _cruise(car, 60, 15);
      _run(car, DriverInputs.idle, 2);
      expect(car.state.fuelCut, isTrue);

      _run(car, const DriverInputs(throttle: 0.3), 0.2);

      expect(car.state.fuelCut, isFalse);
      expect(car.state.fuelGramsPerSecond, greaterThan(0));
    });

    test('harder braking slows the car faster', () {
      double decel(double brake) {
        final car = _warm();
        _cruise(car, 80, 20);
        _run(car, DriverInputs(brake: brake), 1);
        return -car.state.accelerationMs2;
      }

      expect(decel(0.5), greaterThan(decel(0.2)));
      expect(decel(1.0), greaterThan(decel(0.5)));
    });
  });

  group('physical consistency of the PIDs', () {
    test(
      'MAF is the speed-density formula of CLAUDE.md 8.4 throughout a mixed drive',
      () {
        final car = _warm();
        final profile = car.profile;
        for (var i = 0; i < 1500; i++) {
          final wanted = 1.5 * math.sin(i / 90);
          car.step(DriverInputs(throttle: car.pedalForAcceleration(wanted)));
          final s = car.state;
          final ve = profile.engine.volumetricEfficiency.at(s.rpm);
          final expected =
              1000 *
              s.manifoldKpa *
              1.5 *
              (s.rpm / 120) *
              ve /
              (287.05 * (s.intakeAirC + 273.15));

          // The reported RPM carries an idle wobble the engine did not see.
          expect(
            s.airGramsPerSecond,
            closeTo(expected, expected * 0.02 + 0.05),
            reason: 'step $i',
          );
        }
      },
    );

    test(
      'fuel is air over 14.7 whenever the fuel is on, and 5E matches the fuel',
      () {
        final car = _warm();
        for (var i = 0; i < 1500; i++) {
          final wanted = 1.5 * math.sin(i / 70);
          car.step(DriverInputs(throttle: car.pedalForAcceleration(wanted)));
          final s = car.state;
          if (s.fuelCut) {
            expect(s.fuelGramsPerSecond, 0);
          } else {
            expect(
              s.fuelGramsPerSecond,
              closeTo(s.airGramsPerSecond / 14.7, 1e-9),
            );
          }
          expect(
            s.fuelRateLitresPerHour,
            closeTo(s.fuelGramsPerSecond * 3600 / 740, 1e-9),
          );
        }
      },
    );

    test(
      'a diesel burns fuel that is not air over 14.5, so MAF cannot give it',
      () {
        final car = _warm(profile: VehicleProfiles.dieselManual);
        _cruise(car, 90, 30);
        final s = car.state;

        expect(s.airGramsPerSecond / s.fuelGramsPerSecond, greaterThan(25));
      },
    );

    test('MAP rises with the pedal at the same speed', () {
      double mapAt(double pedal) {
        final car = _warm();
        _cruise(car, 50, 15);
        _run(car, DriverInputs(throttle: pedal), 0.3);
        return car.state.manifoldKpa;
      }

      expect(mapAt(0.6), greaterThan(mapAt(0.3)));
      expect(mapAt(1.0), greaterThan(mapAt(0.6)));
    });

    test(
      'the throttle position PID never reads below 12%, and reads about 100% flat out',
      () {
        final car = _warm();
        _run(car, const DriverInputs(brake: 0.5), 3);
        expect(car.state.throttleFraction, greaterThanOrEqualTo(0.12));

        _run(car, const DriverInputs(throttle: 1), 1);
        expect(car.state.throttleFraction, closeTo(1, 0.02));
      },
    );

    test('engine load is about 30% at idle and near 100% flat out', () {
      final car = _warm();
      _run(car, const DriverInputs(brake: 0.5), 3);
      expect(car.state.loadFraction, inInclusiveRange(0.25, 0.45));

      _run(car, const DriverInputs(throttle: 1), 4);
      expect(car.state.loadFraction, greaterThan(0.9));
    });

    test('fuel economy at steady speeds is plausible', () {
      double litresPer100km(double kmh) {
        final car = _warm();
        _cruise(car, kmh, 40);
        final before = car.truth;
        _cruise(car, kmh, 60);
        final after = car.truth;
        return (after.fuelLitres - before.fuelLitres) /
            (after.distanceKm - before.distanceKm) *
            100;
      }

      expect(litresPer100km(60), inInclusiveRange(4, 6.5));
      expect(litresPer100km(100), inInclusiveRange(4.8, 7.5));
    });
  });

  group('heat and electrics', () {
    test(
      'coolant warms from ambient to about 90 C in 8 to 12 minutes of driving, then is held',
      () {
        final car = VehicleModel(profile: VehicleProfiles.petrolCvtMaf);
        double? at85;
        for (var i = 0; i < 16000; i++) {
          final wanted = ((13.9 - car.state.speedMs) * 0.8).clamp(-1.0, 1.5);
          car.step(DriverInputs(throttle: car.pedalForAcceleration(wanted)));
          if (at85 == null && car.state.coolantC >= 85) {
            at85 = car.state.timeSeconds / 60;
          }
        }

        expect(at85, inInclusiveRange(6, 12));
        expect(car.state.coolantC, inInclusiveRange(86, 92));
      },
    );

    test(
      'the thermostat holds the coolant near 90 C, however hard it is driven',
      () {
        final car = _warm();
        var hottest = 0.0;
        for (var i = 0; i < 12000; i++) {
          car.step(const DriverInputs(throttle: 0.8));
          hottest = math.max(hottest, car.state.coolantC);
        }

        expect(hottest, lessThan(100));
      },
    );

    test('idling warms the engine far more slowly than driving', () {
      final idling = VehicleModel(profile: VehicleProfiles.petrolCvtMaf);
      _run(idling, const DriverInputs(brake: 0.5), 300);

      expect(idling.state.coolantC, inInclusiveRange(35, 55));
    });

    test('a hot engine cools slowly with the ignition off', () {
      final car = _warm();
      _run(car, const DriverInputs(brake: 0.5), 5);
      _run(car, DriverInputs.off, 600);

      expect(car.state.coolantC, lessThan(90));
      expect(car.state.coolantC, greaterThan(60));
    });

    test(
      'intake air is a few degrees above ambient once the engine is hot',
      () {
        final car = _warm();
        _run(car, const DriverInputs(brake: 0.5), 30);

        expect(car.state.intakeAirC - car.ambientC, inInclusiveRange(2, 12));
      },
    );

    test('the ambient temperature sets the starting point', () {
      final cold = VehicleModel(
        profile: VehicleProfiles.petrolCvtMaf,
        ambientC: 5,
      );

      expect(cold.state.coolantC, 5);
      expect(cold.state.intakeAirC, 5);
    });

    test('the fuel level falls by exactly the fuel burnt', () {
      final car = _warm();
      final before = car.state.fuelLevelFraction;
      _cruise(car, 50, 120);

      expect(
        before - car.state.fuelLevelFraction,
        closeTo(car.truth.fuelLitres / car.profile.tankLitres, 1e-9),
      );
      expect(car.state.fuelLevelFraction, lessThan(before));
    });

    test('an empty tank stops the engine', () {
      final car = VehicleModel(
        profile: VehicleProfiles.petrolCvtMaf,
        engineRunning: true,
        coolantC: 90,
        fuelLevelFraction: 0.0002,
      );
      _run(car, const DriverInputs(throttle: 0.5), 60);

      expect(car.state.engineState, isNot(EngineState.running));
      expect(car.state.fuelLevelFraction, 0);
    });
  });

  group('lateral acceleration', () {
    test('is v squared over the radius, and positive in a left bend', () {
      final route = SimRoute([
        const Straight(200),
        const Arc(radiusM: 50, turnDegrees: 90),
      ]);
      final car = _warm(route: route);
      _cruise(car, 36, 30);
      while (car.state.distanceM < 200 + 5) {
        final wanted = ((10 - car.state.speedMs) * 0.8).clamp(-1.5, 1.5);
        car.step(DriverInputs(throttle: car.pedalForAcceleration(wanted)));
      }
      final speed = car.state.speedMs;

      expect(
        car.state.lateralAccelerationMs2,
        closeTo(speed * speed / 50, 1e-9),
      );
      expect(car.state.lateralAccelerationMs2, greaterThan(1));
    });

    test('is negative in a right bend and zero on a straight', () {
      final right = _warm(
        route: SimRoute([
          const Straight(100),
          const Arc(radiusM: 60, turnDegrees: -90),
        ]),
      );
      final straight = _warm();
      _cruise(straight, 40, 10);
      while (right.state.distanceM < 110) {
        final wanted = ((10 - right.state.speedMs) * 0.8).clamp(-1.5, 1.5);
        right.step(DriverInputs(throttle: right.pedalForAcceleration(wanted)));
      }

      expect(right.state.lateralAccelerationMs2, lessThan(-1));
      expect(straight.state.lateralAccelerationMs2, 0);
    });

    test('is zero when the car is stopped in a bend', () {
      final route = SimRoute([const Arc(radiusM: 20, turnDegrees: 180)]);
      final car = _warm(route: route);
      _run(car, const DriverInputs(brake: 0.5), 3);

      expect(car.state.lateralAccelerationMs2, 0);
    });
  });

  group('ground truth', () {
    test('distance is the integral of speed', () {
      final car = _warm();
      var sum = 0.0;
      var previous = 0.0;
      for (var i = 0; i < 2000; i++) {
        final wanted = 1.8 * math.sin(i / 100);
        car.step(DriverInputs(throttle: car.pedalForAcceleration(wanted)));
        sum += (previous + car.state.speedMs) / 2 * _dt;
        previous = car.state.speedMs;
      }

      expect(car.state.distanceM, closeTo(sum, 1e-6));
      expect(car.truth.distanceKm, closeTo(sum / 1000, 1e-9));
    });

    test('fuel is the integral of the fuel rate', () {
      final car = _warm();
      var litres = 0.0;
      for (var i = 0; i < 3000; i++) {
        final wanted = 1.6 * math.sin(i / 120);
        car.step(DriverInputs(throttle: car.pedalForAcceleration(wanted)));
        litres += car.state.fuelRateLitresPerHour / 3600 * _dt;
      }

      expect(car.truth.fuelLitres, closeTo(litres, 1e-9));
      expect(car.truth.fuelLitres, greaterThan(0.05));
    });

    test(
      'engine-on and idle time count only the running engine, and idle only below 2 km/h',
      () {
        final car = VehicleModel(profile: VehicleProfiles.petrolCvtMaf);
        _run(car, DriverInputs.idle, 10);
        final onAfterStart = car.truth.engineOnSeconds;
        _run(car, const DriverInputs(brake: 0.5), 30);
        _cruise(car, 50, 30);
        final truth = car.truth;

        expect(onAfterStart, greaterThan(6));
        expect(truth.engineOnSeconds, closeTo(onAfterStart + 60, 0.2));
        expect(truth.idleSeconds, inInclusiveRange(28, 38));
        expect(truth.idleFuelLitres, greaterThan(0));
        expect(truth.idleFuelLitres, lessThan(truth.fuelLitres));
      },
    );

    test('idle fuel per hour matches the idle fuel rate', () {
      final car = _warm();
      _run(car, const DriverInputs(brake: 0.5), 120);
      final truth = car.truth;

      expect(truth.idleSeconds, closeTo(120, 0.1));
      expect(
        truth.idleFuelLitres / truth.idleSeconds * 3600,
        closeTo(car.state.fuelRateLitresPerHour, 0.05),
      );
    });

    test('a car that only creeps at 4 km/h is not idling', () {
      final car = _warm();
      _run(car, DriverInputs.idle, 60);

      expect(car.truth.idleSeconds, lessThan(10));
    });

    test('nothing is counted while the engine is off', () {
      final car = VehicleModel(profile: VehicleProfiles.petrolCvtMaf);
      _run(car, DriverInputs.off, 30);

      expect(car.truth.engineOnSeconds, 0);
      expect(car.truth.fuelLitres, 0);
    });

    test(
      'a scripted hard acceleration is logged with its start, end and peak',
      () {
        final car = _warm();
        _run(car, const DriverInputs(brake: 0.5), 2);
        _run(
          car,
          const DriverInputs(
            throttle: 1,
            intent: DriverIntent.hardAcceleration,
          ),
          4,
        );
        _run(car, const DriverInputs(throttle: 0.2), 2);

        final events = car.truth.events;
        expect(events, hasLength(1));
        expect(events.single.type, TruthEventType.hardAcceleration);
        expect(events.single.startSeconds, closeTo(2.0, 1e-9));
        expect(events.single.endSeconds, closeTo(6.0, 1e-9));
        expect(events.single.durationSeconds, closeTo(4, 1e-9));
        expect(events.single.startSpeedKmh, closeTo(0, 1e-9));
        expect(events.single.endSpeedKmh, greaterThan(40));
        expect(events.single.peakAccelerationMs2, greaterThan(2.5));
      },
    );

    test(
      'hard braking events are logged separately from hard accelerations',
      () {
        final car = _warm();
        _cruise(car, 60, 15);
        _run(
          car,
          const DriverInputs(
            throttle: 1,
            intent: DriverIntent.hardAcceleration,
          ),
          2,
        );
        _run(
          car,
          const DriverInputs(brake: 0.6, intent: DriverIntent.hardBraking),
          3,
        );
        _run(car, DriverInputs.idle, 1);

        final truth = car.truth;
        expect(truth.events.map((e) => e.type), [
          TruthEventType.hardAcceleration,
          TruthEventType.hardBraking,
        ]);
        expect(truth.hardAccelerationCount, 1);
        expect(truth.hardBrakingCount, 1);
        expect(truth.events.last.peakAccelerationMs2, greaterThan(3.5));
      },
    );

    test(
      'switching straight from one intent to the other closes the first',
      () {
        final car = _warm();
        _run(
          car,
          const DriverInputs(
            throttle: 1,
            intent: DriverIntent.hardAcceleration,
          ),
          2,
        );
        _run(
          car,
          const DriverInputs(brake: 1, intent: DriverIntent.hardBraking),
          2,
        );

        final events = car.truth.events;
        expect(events, hasLength(2));
        expect(events.first.endSeconds, isNotNull);
        expect(events.last.endSeconds, isNull, reason: 'still going on');
      },
    );

    test('an event that is still open is visible, without an end', () {
      final car = _warm();
      _run(
        car,
        const DriverInputs(throttle: 1, intent: DriverIntent.hardAcceleration),
        2,
      );

      expect(car.truth.events.single.endSeconds, isNull);
      expect(car.truth.events.single.durationSeconds, isNull);
    });

    test('normal driving logs no events', () {
      final car = _warm();
      _cruise(car, 60, 60);

      expect(car.truth.events, isEmpty);
    });
  });

  group('determinism', () {
    List<List<Object>> trace(int seed, {int steps = 1200}) {
      final car = _warm(seed: seed);
      final out = <List<Object>>[];
      for (var i = 0; i < steps; i++) {
        final wanted = 1.5 * math.sin(i / 60);
        car.step(
          DriverInputs(
            throttle: car.pedalForAcceleration(wanted),
            brake: wanted < -1 ? 0.3 : 0,
          ),
        );
        out.add(_fingerprint(car.state));
      }
      return out;
    }

    test('the same seed and inputs give exactly the same run', () {
      expect(trace(5), trace(5));
    });

    test('the seed only changes the reported wobble, not the physics', () {
      final a = trace(1);
      final b = trace(2);

      expect(
        a,
        isNot(b),
        reason: 'the idle wobble and the electrical ripple differ',
      );
      for (var i = 0; i < a.length; i++) {
        // Speed, distance, fuel and gearing are identical whatever the seed.
        expect(a[i][1], b[i][1]);
        expect(a[i][2], b[i][2]);
        expect(a[i][10], b[i][10]);
      }
    });

    test('asking what-if questions never changes the run', () {
      final plain = _warm();
      final curious = _warm();
      for (var i = 0; i < 1500; i++) {
        final wanted = 1.5 * math.sin(i / 60);
        final pedal = plain.pedalForAcceleration(wanted);
        plain.step(DriverInputs(throttle: pedal));

        curious.accelerationFor(pedal: 1);
        curious.brakeForDeceleration(3);
        curious.pedalForAcceleration(2);
        curious.step(
          DriverInputs(throttle: curious.pedalForAcceleration(wanted)),
        );

        expect(
          _fingerprint(curious.state),
          _fingerprint(plain.state),
          reason: 'step $i',
        );
      }
    });

    test('the ground truth does not depend on the seed', () {
      GroundTruth truthFor(int seed) {
        final car = _warm(seed: seed);
        _cruise(car, 70, 60);
        return car.truth;
      }

      expect(truthFor(1).fuelLitres, truthFor(99).fuelLitres);
      expect(truthFor(1).distanceKm, truthFor(99).distanceKm);
    });
  });

  group('the what-if questions', () {
    test('accelerationFor is the acceleration the next step then has', () {
      final car = _warm();
      _cruise(car, 40, 10);
      for (final pedal in [0.0, 0.2, 0.5, 0.9]) {
        final predicted = car.accelerationFor(pedal: pedal);
        final other = _warm();
        _cruise(other, 40, 10);
        other.step(DriverInputs(throttle: pedal));

        expect(
          other.state.accelerationMs2,
          closeTo(predicted, 1e-9),
          reason: 'pedal $pedal',
        );
      }
    });

    test(
      'pedalForAcceleration finds the pedal for an acceleration, at several speeds',
      () {
        for (final kmh in [10.0, 30.0, 60.0, 90.0]) {
          // What the next step can give is bounded, since a CVT's revs take a
          // moment to rise, so ask for shares of what is reachable.
          for (final share in [0.25, 0.5, 0.75]) {
            final car = _warm();
            _cruise(car, kmh, 20);
            final coast = car.accelerationFor(pedal: 0);
            final best = car.accelerationFor(pedal: 1);
            final wanted = coast + share * (best - coast);
            final pedal = car.pedalForAcceleration(wanted);
            car.step(DriverInputs(throttle: pedal));

            expect(
              car.state.accelerationMs2,
              closeTo(wanted, 0.03),
              reason: '$kmh km/h, share $share',
            );
          }
        }
      },
    );

    test(
      'pedalForAcceleration is 0 below what coasting gives, and full if it is out of reach',
      () {
        final car = _warm();
        _cruise(car, 60, 15);

        expect(car.pedalForAcceleration(-3), 0);
        expect(car.pedalForAcceleration(9), 1);
        expect(car.pedalForAcceleration(9, maxPedal: 0.5), 0.5);
      },
    );

    test('pedalForAcceleration rises with the acceleration wanted', () {
      final car = _warm();
      _cruise(car, 50, 15);
      var previous = -1.0;
      for (var a = 0.2; a <= 2.0; a += 0.2) {
        final pedal = car.pedalForAcceleration(a);

        // It saturates at full pedal once the target is out of reach.
        expect(pedal, greaterThanOrEqualTo(previous));
        previous = pedal;
      }
      expect(
        car.pedalForAcceleration(0.2),
        lessThan(car.pedalForAcceleration(0.8)),
      );
      expect(car.pedalForAcceleration(0.2), greaterThan(0));
    });

    test('brakeForDeceleration gives the deceleration asked for', () {
      for (final wanted in [1.0, 2.5, 4.0, 6.0]) {
        final car = _warm();
        _cruise(car, 80, 20);
        final brake = car.brakeForDeceleration(wanted);
        car.step(DriverInputs(brake: brake));

        expect(
          -car.state.accelerationMs2,
          closeTo(wanted, 0.05),
          reason: '$wanted m/s2',
        );
      }
    });

    test(
      'brakeForDeceleration is 0 when coasting already slows the car enough, and 1 when out of reach',
      () {
        final car = _warm();
        _cruise(car, 80, 20);

        expect(car.brakeForDeceleration(0.1), 0);
        expect(car.brakeForDeceleration(20), 1);
      },
    );

    test('with the engine off there is no drive, only resistance', () {
      final car = VehicleModel(profile: VehicleProfiles.petrolCvtMaf);

      expect(car.accelerationFor(pedal: 1), 0);
      expect(car.pedalForAcceleration(1), 1);
    });
  });

  group('a manual gearbox', () {
    VehicleModel sporty() => _warm(profile: VehicleProfiles.petrolManualSporty);

    test('starts in first', () {
      final car = sporty();
      _run(car, const DriverInputs(brake: 0.5), 1);

      expect(car.state.gear, 1);
    });

    test(
      'changes up as the car accelerates, one gear at a time, and never hunts',
      () {
        final car = sporty();
        final gears = <int>[];
        for (var i = 0; i < 700; i++) {
          car.step(const DriverInputs(throttle: 1));
          final g = car.state.gear;
          if (g != 0 && (gears.isEmpty || gears.last != g)) gears.add(g);
        }

        expect(gears.take(4), [1, 2, 3, 4]);
        for (var i = 1; i < gears.length; i++) {
          expect(
            gears[i],
            gears[i - 1] + 1,
            reason: 'one gear at a time, only up',
          );
        }
      },
    );

    test('the revs fall at each upshift', () {
      final car = sporty();
      var lastGear = 1;
      var before = 0.0;
      final drops = <double>[];
      for (var i = 0; i < 600; i++) {
        final rpmBefore = car.state.rpm;
        car.step(const DriverInputs(throttle: 1));
        final g = car.state.gear;
        if (g == 0 && lastGear != 0) before = rpmBefore;
        if (g != 0 && lastGear == 0 && before > 0) {
          drops.add(before - car.state.rpm);
          before = 0;
        }
        lastGear = g;
      }

      expect(drops, isNotEmpty);
      for (final d in drops) {
        expect(d, greaterThan(500));
      }
    });

    test('the gear reads 0 while the clutch is out during a shift', () {
      final car = sporty();
      var sawClutchOut = false;
      for (var i = 0; i < 300; i++) {
        car.step(const DriverInputs(throttle: 1));
        if (car.state.gear == 0) sawClutchOut = true;
      }

      expect(sawClutchOut, isTrue);
    });

    test(
      'the pull reaches near the 7,000 rpm redline in each gear, and never far above it',
      () {
        final car = sporty();
        var top = 0.0;
        for (var i = 0; i < 500; i++) {
          car.step(const DriverInputs(throttle: 1));
          top = math.max(top, car.state.rpm);
        }

        expect(top, inInclusiveRange(6000, 7100));
      },
    );

    test('a steady speed does not change gear back and forth', () {
      for (final profile in [
        VehicleProfiles.petrolManualSporty,
        VehicleProfiles.dieselManual,
      ]) {
        final car = _warm(profile: profile);
        _cruise(car, 60, 30);
        var changes = 0;
        var last = car.state.gear;
        for (var i = 0; i < 1200; i++) {
          final wanted = ((16.7 - car.state.speedMs) * 0.8).clamp(-1.5, 1.5);
          car.step(DriverInputs(throttle: car.pedalForAcceleration(wanted)));
          final g = car.state.gear;
          if (g != 0 && g != last) {
            changes++;
            last = g;
          }
        }

        expect(changes, lessThanOrEqualTo(1), reason: profile.name);
      }
    });

    test(
      'no two gear changes come within a second of each other in a mixed drive',
      () {
        for (final profile in [
          VehicleProfiles.petrolManualSporty,
          VehicleProfiles.dieselManual,
        ]) {
          final car = _warm(profile: profile);
          var lastChange = -10.0;
          var lastGear = 1;
          for (var i = 0; i < 4000; i++) {
            final wanted = 1.6 * math.sin(i / 150);
            car.step(
              DriverInputs(
                throttle: car.pedalForAcceleration(wanted),
                brake: wanted < -1.0 ? 0.4 : 0,
              ),
            );
            final g = car.state.gear;
            if (g != 0 && g != lastGear) {
              expect(
                car.state.timeSeconds - lastChange,
                greaterThan(0.9),
                reason: profile.name,
              );
              lastChange = car.state.timeSeconds;
              lastGear = g;
            }
          }
        }
      },
    );

    test('a diesel pulls away gently from a standstill without stalling', () {
      final car = _warm(profile: VehicleProfiles.dieselManual);
      _run(car, const DriverInputs(throttle: 0.3), 10);

      expect(car.state.speedKmh, greaterThan(20));
      expect(car.state.rpm, greaterThan(800));
    });

    test('kickdown: flat out in a high gear drops to a lower gear', () {
      final car = sporty();
      _cruise(car, 90, 40);
      final before = car.state.gear;
      _run(car, const DriverInputs(throttle: 1), 1.5);
      var lowest = before;
      for (var i = 0; i < 40; i++) {
        car.step(const DriverInputs(throttle: 1));
        if (car.state.gear != 0) lowest = math.min(lowest, car.state.gear);
      }

      expect(before, greaterThanOrEqualTo(3));
      expect(lowest, lessThan(before));
    });

    test(
      'the what-if never shifts the gear, even where a real full pedal would kick down',
      () {
        for (final profile in [
          VehicleProfiles.petrolManualSporty,
          VehicleProfiles.dieselManual,
        ]) {
          final car = _manualAt(profile, 90);
          final gear = car.state.gear;
          expect(gear, greaterThanOrEqualTo(3), reason: profile.name);

          // In this state a real full pedal does kick down...
          final kicker = _manualAt(profile, 90);
          _run(kicker, const DriverInputs(throttle: 1), 0.1);
          expect(
            kicker.state.gear,
            isNot(gear),
            reason:
                '${profile.name}: the setup must be one where kickdown happens',
          );

          // ...but asking about it does not, and answers for the gear it is in.
          expect(
            car.accelerationFor(pedal: 1),
            greaterThan(car.accelerationFor(pedal: 0.5)),
            reason: profile.name,
          );
          final pedal = car.pedalForAcceleration(0.3);
          expect(pedal, lessThan(0.9), reason: profile.name);
          car.step(DriverInputs(throttle: pedal));
          expect(car.state.gear, gear, reason: profile.name);
        }
      },
    );

    test(
      'acceleration rises smoothly with the pedal in a manual car, with no jump for a kickdown',
      () {
        final car = _manualAt(VehicleProfiles.petrolManualSporty, 90);
        var previous = -double.infinity;
        for (var p = 0.0; p <= 1.0; p += 0.05) {
          final a = car.accelerationFor(pedal: p);

          expect(a, greaterThanOrEqualTo(previous - 1e-9), reason: 'pedal $p');
          previous = a;
        }
      },
    );
  });

  group('robustness', () {
    test(
      'random inputs for a long time never give a NaN or an impossible value',
      () {
        for (final profile in VehicleProfiles.all) {
          final random = SimRandom(7);
          final car = _warm(profile: profile);
          var lastFuel = 0.0;
          var lastDistance = 0.0;
          for (var i = 0; i < 6000; i++) {
            final inputs = i % 400 < 40
                ? DriverInputs(ignitionOn: random.chance(0.9))
                : DriverInputs(
                    throttle: random.chance(0.3) ? random.nextDouble() : 0,
                    brake: random.chance(0.2) ? random.nextDouble() : 0,
                  );
            car.step(inputs);
            final s = car.state;

            expect(
              s.speedMs.isFinite && s.speedMs >= 0,
              isTrue,
              reason: '${profile.name} step $i',
            );
            expect(
              s.rpm.isFinite && s.rpm >= 0 && s.rpm <= profile.redlineRpm + 120,
              isTrue,
              reason: '${profile.name} rpm ${s.rpm}',
            );
            expect(
              s.manifoldKpa.isFinite &&
                  s.manifoldKpa > 10 &&
                  s.manifoldKpa < 250,
              isTrue,
              reason: '${profile.name} MAP ${s.manifoldKpa}',
            );
            expect(
              s.airGramsPerSecond.isFinite && s.airGramsPerSecond >= 0,
              isTrue,
            );
            expect(
              s.fuelGramsPerSecond.isFinite && s.fuelGramsPerSecond >= 0,
              isTrue,
            );
            expect(
              s.coolantC.isFinite && s.coolantC >= 29 && s.coolantC < 110,
              isTrue,
              reason: '${profile.name} coolant ${s.coolantC}',
            );
            expect(s.voltage, inInclusiveRange(10, 15));
            expect(s.fuelLevelFraction, inInclusiveRange(0, 1));
            expect(s.accelerationMs2.isFinite, isTrue);
            expect(s.loadFraction, inInclusiveRange(0, 1));
            final truth = car.truth;
            expect(truth.fuelLitres, greaterThanOrEqualTo(lastFuel));
            expect(truth.distanceKm * 1000, greaterThanOrEqualTo(lastDistance));
            lastFuel = truth.fuelLitres;
            lastDistance = truth.distanceKm * 1000;
          }
        }
      },
    );

    test(
      'a 30 minute drive with a driver asking what-ifs every step runs in seconds',
      () {
        final car = _warm();
        final stopwatch = Stopwatch()..start();
        for (var i = 0; i < 36000; i++) {
          final wanted = 1.4 * math.sin(i / 400);
          car.step(
            DriverInputs(
              throttle: car.pedalForAcceleration(wanted),
              brake: wanted < -0.8 ? 0.3 : 0,
            ),
          );
        }

        expect(car.state.timeSeconds, closeTo(1800, 0.5));
        expect(stopwatch.elapsed.inSeconds, lessThan(30));
      },
    );

    test('every profile starts, idles, drives and stops', () {
      for (final profile in VehicleProfiles.all) {
        final car = VehicleModel(profile: profile);
        _run(car, DriverInputs.idle, 6);
        expect(
          car.state.engineState,
          EngineState.running,
          reason: profile.name,
        );
        _cruise(car, 50, 40);
        expect(car.state.speedKmh, closeTo(50, 4), reason: profile.name);
        while (car.state.speedMs > 0) {
          car.step(const DriverInputs(brake: 0.5));
        }
        expect(car.state.speedMs, 0, reason: profile.name);
      }
    });
  });
}
