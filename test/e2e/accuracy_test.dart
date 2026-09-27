// Layer 3 (CLAUDE.md 10): what the vehicle state knows, against the simulator's
// ground truth, through the whole path: the ECU, the adapter and its latency,
// the ELM327 layer, the poller with its batches, the outlier check and the
// smoothing.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/vehicle_model.dart';
import 'package:tapedash/vehicle/reading.dart';
import 'package:tapedash/vehicle/sensor.dart';

import 'e2e_rig.dart';

/// The mean and the 99th percentile of the absolute errors of [readings]
/// against [truth], at each reading's own time, or at its arrival if
/// [atArrival].
({double mean, double p99}) errors(
  E2eRig rig,
  List<Reading> readings,
  double Function(VehicleSnapshot snapshot) truth, {
  bool atArrival = false,
}) {
  final errs = <double>[];
  for (final r in readings) {
    final t = rig.truthAt(atArrival ? r.receivedAt : r.at);
    errs.add((r.value - truth(t)).abs());
  }
  errs.sort();
  return (
    mean: errs.reduce((a, b) => a + b) / errs.length,
    p99: errs[(errs.length * 0.99).floor()],
  );
}

void main() {
  group('speed and rpm against the truth, over a city drive', () {
    for (final (name, quirks) in [
      ('a perfect adapter', AdapterQuirks.none),
      ('a Bluetooth clone', AdapterQuirks.bluetoothClone),
      ('a flaky clone', AdapterQuirks.flaky),
    ]) {
      test(name, () {
        final rig = E2eRig(DriveScenarios.cityStopGo, quirks: quirks)
          ..runToEnd();
        addTearDown(rig.close);

        final speed = errors(
          rig,
          rig.readings[Sensor.speed]!,
          (s) => s.speedKmh,
        );
        final rpm = errors(rig, rig.readings[Sensor.rpm]!, (s) => s.rpm);

        // The car reports whole km/h, so half a km/h is the floor; the rest is
        // the time.
        expect(speed.mean, lessThan(0.45));
        expect(speed.p99, lessThan(2.5));
        // The reported rpm has its own wobble, and the ECU's noise on top.
        expect(rpm.mean, lessThan(35));
        expect(rpm.p99, lessThan(250));
      });
    }

    test(
      'the slower sensors too: coolant, voltage, fuel level, load, throttle, MAF',
      () {
        final rig = E2eRig(DriveScenarios.cityStopGo)..runToEnd();
        addTearDown(rig.close);

        final coolant = errors(
          rig,
          rig.readings[Sensor.coolant]!,
          (s) => s.coolantC,
        );
        final voltage = errors(
          rig,
          rig.readings[Sensor.voltage]!,
          (s) => s.voltage,
        );
        final fuel = errors(
          rig,
          rig.readings[Sensor.fuelLevel]!,
          (s) => s.fuelLevelFraction * 100,
        );
        final load = errors(
          rig,
          rig.readings[Sensor.load]!,
          (s) => s.loadFraction * 100,
        );
        final throttle = errors(
          rig,
          rig.readings[Sensor.throttle]!,
          (s) => s.throttleFraction * 100,
        );
        final maf = errors(
          rig,
          rig.readings[Sensor.airFlow]!,
          (s) => s.airGramsPerSecond,
        );

        expect(coolant.mean, lessThan(0.6));
        expect(voltage.mean, lessThan(0.06));
        expect(fuel.mean, lessThan(0.3));
        expect(load.mean, lessThan(4));
        expect(throttle.mean, lessThan(3));
        expect(maf.mean, lessThan(0.6));
      },
    );
  });

  group(
    'timestamping a reading at the middle of its round trip (DESIGN.md 5.2)',
    () {
      test(
        'is more accurate than timestamping it on arrival, on a slow link',
        () {
          final rig = E2eRig(
            DriveScenarios.aggressiveCity,
            quirks: AdapterQuirks.bluetoothClone,
          )..runToEnd();
          addTearDown(rig.close);

          for (final (sensor, truth)
              in <(Sensor, double Function(VehicleSnapshot))>[
                (Sensor.speed, (s) => s.speedKmh),
                (Sensor.rpm, (s) => s.rpm),
              ]) {
            final mid = errors(rig, rig.readings[sensor]!, truth);
            final arrival = errors(
              rig,
              rig.readings[sensor]!,
              truth,
              atArrival: true,
            );

            expect(
              mid.mean,
              lessThan(arrival.mean * 0.85),
              reason: sensor.name,
            );
          }
        },
      );

      test(
        'on a perfect link the difference is only the ECU\'s 20 ms, and small',
        () {
          final rig = E2eRig(DriveScenarios.aggressiveCity)..runToEnd();
          addTearDown(rig.close);

          final mid = errors(rig, rig.readings[Sensor.rpm]!, (s) => s.rpm);
          final arrival = errors(
            rig,
            rig.readings[Sensor.rpm]!,
            (s) => s.rpm,
            atArrival: true,
          );

          expect(mid.mean, lessThan(arrival.mean));
        },
      );
    },
  );

  group(
    'the coach\'s rule for hard driving, on what the vehicle state gives it (CLAUDE.md 8.8)',
    () {
      for (final (name, quirks) in [
        ('a perfect adapter', AdapterQuirks.none),
        ('a Bluetooth clone', AdapterQuirks.bluetoothClone),
      ]) {
        test(
          'aggressive_city on $name: the scripted events are found, within one',
          () {
            final rig = E2eRig(DriveScenarios.aggressiveCity, quirks: quirks)
              ..runToEnd();
            addTearDown(rig.close);

            final found = detectHardEvents(rig.motion);

            final scriptedAcceleration = rig.car.truth.hardAccelerationCount;
            final scriptedBraking = rig.car.truth.hardBrakingCount;
            expect(scriptedAcceleration, 12);
            expect(
              (found.accelerations - scriptedAcceleration).abs(),
              lessThanOrEqualTo(1),
              reason:
                  '${found.accelerations} found, $scriptedAcceleration scripted',
            );
            expect(
              (found.brakings - scriptedBraking).abs(),
              lessThanOrEqualTo(1),
              reason: '${found.brakings} found, $scriptedBraking scripted',
            );
          },
        );

        test('eco_city on $name: none is found', () {
          final rig = E2eRig(DriveScenarios.ecoCity, quirks: quirks)
            ..runToEnd();
          addTearDown(rig.close);

          final found = detectHardEvents(rig.motion);

          expect(found.accelerations, 0);
          expect(found.brakings, 0);
        });
      }

      test(
        'the acceleration it reads is a plausible one: never more than the car can do',
        () {
          final rig = E2eRig(DriveScenarios.aggressiveCity)..runToEnd();
          addTearDown(rig.close);

          final most = rig.motion
              .map((m) => m.accelerationMs2)
              .reduce(math.max);
          final least = rig.motion
              .map((m) => m.accelerationMs2)
              .reduce(math.min);

          // Whole km/h steps smoothed over a second: bounded, and not the 5.6 m/s2
          // that one step in 50 ms would be raw.
          expect(most, lessThan(6));
          expect(least, greaterThan(-9));
        },
      );
    },
  );

  group('every profile, over a short drive', () {
    for (final profile in VehicleProfiles.all) {
      test(profile.name, () {
        final rig = E2eRig(
          profile.name == 'petrol_manual_sporty'
              ? DriveScenarios.spiritedRevs
              : DriveScenarios.cityStopGo,
          profile: profile,
        )..run(300);
        addTearDown(rig.close);

        final speed = errors(
          rig,
          rig.readings[Sensor.speed]!,
          (s) => s.speedKmh,
        );
        final rpm = errors(rig, rig.readings[Sensor.rpm]!, (s) => s.rpm);

        expect(speed.mean, lessThan(0.6), reason: profile.name);
        expect(rpm.mean, lessThan(60), reason: profile.name);
      });
    }
  });

  group('running the whole thing', () {
    test('a 30-minute drive takes a few seconds (CLAUDE.md 10)', () {
      final rig = E2eRig(DriveScenarios.highwayCruise);
      addTearDown(rig.close);
      final watch = Stopwatch()..start();

      rig.runToEnd();

      expect(rig.car.elapsedSeconds, closeTo(1800, 10));
      expect(watch.elapsed.inSeconds, lessThan(20));
      expect(rig.readings[Sensor.speed]!.length, greaterThan(20000));
    });

    test('the same options give the same readings, to the last one', () {
      List<double> run() {
        final rig = E2eRig(
          DriveScenarios.cityStopGo,
          quirks: AdapterQuirks.flaky,
          seed: 5,
        )..run(300);
        final values = [
          for (final s in [Sensor.rpm, Sensor.speed, Sensor.coolant])
            ...rig.readings[s]!.expand(
              (r) => [r.value, r.at.inMicroseconds.toDouble()],
            ),
        ];
        rig.close();
        return values;
      }

      expect(run(), run());
    });

    test('another seed gives other noise on the same drive', () {
      double sum(int seed) {
        final rig = E2eRig(DriveScenarios.cityStopGo, seed: seed)..run(120);
        final total = rig.readings[Sensor.rpm]!.fold<double>(
          0,
          (a, r) => a + r.value,
        );
        rig.close();
        return total;
      }

      expect(sum(1), isNot(sum(2)));
    });

    test(
      'the poll rate of a perfect adapter is about 37 Hz, and of a clone about 9',
      () {
        final perfect = E2eRig(DriveScenarios.cityStopGo)..run(60);
        final clone = E2eRig(
          DriveScenarios.cityStopGo,
          quirks: AdapterQuirks.bluetoothClone,
        )..run(60);
        addTearDown(perfect.close);
        addTearDown(clone.close);

        expect(perfect.session.pollRate.value, closeTo(37, 4));
        expect(clone.session.pollRate.value, closeTo(9.3, 1.5));
      },
    );
  });
}
