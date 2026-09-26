import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/sim/drive_scenario.dart';
import 'package:tapedash/sim/ground_truth.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenario_events.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';
import 'package:tapedash/sim/vehicle_model.dart';

/// Everything worth knowing about one run of a scenario.
class _Run {
  _Run(
    DriveScenario scenario, {
    int seed = 1,
    Duration limit = const Duration(hours: 2),
  }) : car = SimulatedCar(scenario: scenario, seed: seed) {
    var wasMoving = false;
    var offStartedAt = -1.0;
    var lastGear = 1;
    var aboveHigh = false;
    final limitSeconds = limit.inMicroseconds / 1e6;
    var tick = 0;
    while (!car.isFinished && car.elapsedSeconds < limitSeconds) {
      car.tick();
      final s = car.state;
      speeds.add(s.speedKmh);
      maxKmh = math.max(maxKmh, s.speedKmh);
      maxRpm = math.max(maxRpm, s.rpm);
      maxAccel = math.max(maxAccel, s.accelerationMs2);
      maxDecel = math.max(maxDecel, -s.accelerationMs2);
      maxLateral = math.max(maxLateral, s.lateralAccelerationMs2.abs());
      if (s.engineRunning) {
        engineOnSamples++;
        if (s.rpm > 6000 && !aboveHigh) revPeaks++;
        aboveHigh = s.rpm > 6000;
      }
      if (s.engineState == EngineState.off) {
        engineOffTicks++;
      }
      if (s.gear != 0 && s.gear != lastGear) {
        gearChanges++;
        lastGear = s.gear;
      }
      final moving = s.speedKmh > 3;
      if (wasMoving && s.speedMs < 0.05) stops++;
      wasMoving = moving || (wasMoving && s.speedMs >= 0.05);
      if (!s.ignitionOn && offStartedAt < 0) offStartedAt = s.timeSeconds;
      if (s.ignitionOn && offStartedAt >= 0) {
        ignitionOffPeriods.add(s.timeSeconds - offStartedAt);
        offStartedAt = -1;
      }
      if (tick++ % 2 == 0) {
        obdSpeeds.add(s.speedKmh.roundToDouble());
      }
    }
  }

  final SimulatedCar car;
  final List<double> speeds = [];
  final List<double> obdSpeeds = [];
  double maxKmh = 0;
  double maxRpm = 0;
  double maxAccel = 0;
  double maxDecel = 0;
  double maxLateral = 0;
  int stops = 0;
  int engineOnSamples = 0;
  int engineOffTicks = 0;
  int revPeaks = 0;
  int gearChanges = 0;
  final List<double> ignitionOffPeriods = [];

  GroundTruth get truth => car.truth;
  double get seconds => car.elapsedSeconds;
  double get idleShare => truth.idleSeconds / truth.engineOnSeconds;
  double get litresPer100Km => truth.fuelLitres / truth.distanceKm * 100;
}

/// How many episodes the app's own detectors (CLAUDE.md 8.8) would find in a
/// run: the speed as the OBD port gives it, whole km/h at 10 Hz, smoothed with
/// an exponential average of about a second, and acceleration taken from that.
({int hardAcceleration, int hardBraking}) _detect(List<double> obdKmh) {
  const dt = 0.1;
  final alpha = 1 - math.exp(-dt / 1.0);
  var smoothed = obdKmh.first / 3.6;
  var hardAccelerationFor = 0.0;
  var hardBrakingFor = 0.0;
  var accelerationEvents = 0;
  var brakingEvents = 0;
  var accelerationOpen = false;
  var brakingOpen = false;
  for (final kmh in obdKmh.skip(1)) {
    final next = smoothed + alpha * (kmh / 3.6 - smoothed);
    final acceleration = (next - smoothed) / dt;
    smoothed = next;

    hardAccelerationFor = acceleration > 2.5 ? hardAccelerationFor + dt : 0;
    if (hardAccelerationFor >= 1.0 && !accelerationOpen) {
      accelerationEvents++;
      accelerationOpen = true;
    }
    if (acceleration <= 2.5) accelerationOpen = false;

    hardBrakingFor = acceleration < -3.5 ? hardBrakingFor + dt : 0;
    if (hardBrakingFor >= 0.5 && !brakingOpen) {
      brakingEvents++;
      brakingOpen = true;
    }
    if (acceleration >= -3.5) brakingOpen = false;
  }
  return (hardAcceleration: accelerationEvents, hardBraking: brakingEvents);
}

void main() {
  final runs = <String, _Run>{};
  _Run run(DriveScenario scenario) =>
      runs.putIfAbsent(scenario.name, () => _Run(scenario));

  group('the scenario library', () {
    test('has the ten scenarios of CLAUDE.md 7.3', () {
      expect(DriveScenarios.all.map((s) => s.name), [
        'cold_start_idle',
        'city_stop_go',
        'highway_cruise',
        'aggressive_city',
        'eco_city',
        'traffic_jam',
        'mixed_commute',
        'spirited_revs',
        'dtc_present',
        'adapter_flaky',
      ]);
    });

    test('byName finds each, and nothing else', () {
      for (final scenario in DriveScenarios.all) {
        expect(DriveScenarios.byName(scenario.name), same(scenario));
      }
      expect(DriveScenarios.byName('nope'), isNull);
    });

    test('every scenario has a description and a route', () {
      for (final scenario in DriveScenarios.all) {
        expect(scenario.description, isNotEmpty, reason: scenario.name);
        expect(scenario.route.lengthM, greaterThan(0), reason: scenario.name);
      }
    });

    test(
      'every scenario runs to the end, in a fraction of its simulated time',
      () {
        final watch = Stopwatch()..start();
        for (final scenario in DriveScenarios.all) {
          final r = run(scenario);

          expect(r.car.isFinished, isTrue, reason: scenario.name);
          expect(r.seconds, greaterThan(60), reason: scenario.name);
        }
        // Hours of driving in a few seconds.
        expect(watch.elapsed.inSeconds, lessThan(60));
      },
    );

    test(
      'a fresh driver is built for each run, so runs do not affect each other',
      () {
        final a = SimulatedCar(scenario: DriveScenarios.cityStopGo)..runToEnd();
        final b = SimulatedCar(scenario: DriveScenarios.cityStopGo)..runToEnd();

        expect(b.truth.fuelLitres, a.truth.fuelLitres);
        expect(b.truth.distanceKm, a.truth.distanceKm);
      },
    );

    test(
      'the same seed gives the same drive, and the physics does not depend on the seed',
      () {
        final one = _Run(DriveScenarios.cityStopGo, seed: 1);
        final again = _Run(DriveScenarios.cityStopGo, seed: 1);
        final other = _Run(DriveScenarios.cityStopGo, seed: 77);

        expect(again.speeds, one.speeds);
        expect(other.truth.fuelLitres, one.truth.fuelLitres);
        expect(other.truth.distanceKm, one.truth.distanceKm);
      },
    );
  });

  group('cold_start_idle', () {
    test('lasts five minutes, from a cold engine', () {
      final r = run(DriveScenarios.coldStartIdle);

      expect(r.seconds, closeTo(300, 0.1));
      expect(r.car.model.ambientC, 30);
    });

    test('the car never moves', () {
      final r = run(DriveScenarios.coldStartIdle);

      expect(r.maxKmh, 0);
      expect(r.truth.distanceKm, 0);
    });

    test(
      'the engine starts within the first few seconds and idles for the rest',
      () {
        final r = run(DriveScenarios.coldStartIdle);

        expect(r.truth.engineOnSeconds, greaterThan(295));
        expect(r.idleShare, greaterThan(0.99));
      },
    );

    test('the revs start fast and settle towards the warm idle', () {
      final car = SimulatedCar(scenario: DriveScenarios.coldStartIdle);
      double rpmAt(double seconds) {
        while (car.elapsedSeconds < seconds) {
          car.tick();
        }
        return car.state.rpm;
      }

      final early = rpmAt(10);
      final late = rpmAt(290);

      expect(early, greaterThan(1050));
      expect(late, lessThan(early - 150));
      expect(late, greaterThan(740));
    });

    test('the coolant warms slowly while idling', () {
      final r = run(DriveScenarios.coldStartIdle);

      expect(r.car.state.coolantC, inInclusiveRange(38, 60));
    });
  });

  group('city_stop_go', () {
    test('lasts 20 minutes', () {
      expect(run(DriveScenarios.cityStopGo).seconds, closeTo(1200, 0.1));
    });

    test('goes from 0 to 50 km/h with traffic signals, idling at them', () {
      final r = run(DriveScenarios.cityStopGo);

      expect(r.maxKmh, inInclusiveRange(48, 53));
      expect(r.stops, greaterThanOrEqualTo(8));
      expect(r.idleShare, inInclusiveRange(0.15, 0.45));
    });

    test('covers a plausible city distance at a plausible economy', () {
      final r = run(DriveScenarios.cityStopGo);

      expect(r.truth.distanceKm, inInclusiveRange(6, 10));
      expect(r.litresPer100Km, inInclusiveRange(7, 12));
    });

    test('is ordinary driving, with no scripted hard events', () {
      expect(run(DriveScenarios.cityStopGo).truth.events, isEmpty);
    });

    test('takes its bends at a sensible lateral acceleration', () {
      expect(
        run(DriveScenarios.cityStopGo).maxLateral,
        inInclusiveRange(0.8, 3.0),
      );
    });
  });

  group('highway_cruise', () {
    test('lasts 30 minutes', () {
      expect(run(DriveScenarios.highwayCruise).seconds, closeTo(1800, 0.1));
    });

    test('holds 70 to 110 km/h once up to speed, with a few overtakes', () {
      final r = run(DriveScenarios.highwayCruise);
      final cruising = r.speeds.skip(1800);

      expect(cruising.reduce(math.min), greaterThan(70));
      expect(cruising.reduce(math.max), lessThan(110));
      expect(r.maxKmh, inInclusiveRange(100, 110));
      var overtakes = 0;
      var above = false;
      for (final v in r.speeds) {
        if (v > 100 && !above) overtakes++;
        above = v > 100;
      }
      expect(overtakes, greaterThanOrEqualTo(3));
    });

    test('never stops, and burns like a car on a motorway', () {
      final r = run(DriveScenarios.highwayCruise);

      expect(r.stops, 0);
      expect(r.truth.distanceKm, inInclusiveRange(38, 52));
      expect(r.litresPer100Km, inInclusiveRange(4.8, 7.5));
    });

    test('has gentle bends', () {
      expect(run(DriveScenarios.highwayCruise).maxLateral, lessThan(1.5));
    });
  });

  group('aggressive_city and eco_city', () {
    test('are the same road', () {
      final aggressive = DriveScenarios.aggressiveCity.route;
      final eco = DriveScenarios.ecoCity.route;

      expect(eco.lengthM, aggressive.lengthM);
      for (var d = 0.0; d < aggressive.lengthM; d += 97) {
        expect(eco.pointAt(d).latitude, aggressive.pointAt(d).latitude);
        expect(eco.pointAt(d).longitude, aggressive.pointAt(d).longitude);
      }
    });

    test('cover the same distance', () {
      final aggressive = run(DriveScenarios.aggressiveCity);
      final eco = run(DriveScenarios.ecoCity);

      expect(
        eco.truth.distanceKm,
        closeTo(
          aggressive.truth.distanceKm,
          aggressive.truth.distanceKm * 0.02,
        ),
      );
    });

    test(
      'the eco run costs at least 15% less than the aggressive run, over the same route',
      () {
        final aggressive = run(DriveScenarios.aggressiveCity);
        final eco = run(DriveScenarios.ecoCity);

        expect(
          eco.truth.fuelLitres,
          lessThan(aggressive.truth.fuelLitres * 0.85),
          reason:
              'eco ${eco.truth.fuelLitres} L, aggressive ${aggressive.truth.fuelLitres} L',
        );
      },
    );

    test(
      'the saving is real driving, not less idling: they idle for the same waits',
      () {
        final aggressive = run(DriveScenarios.aggressiveCity);
        final eco = run(DriveScenarios.ecoCity);
        final aggressiveMoving =
            aggressive.truth.fuelLitres - aggressive.truth.idleFuelLitres;
        final ecoMoving = eco.truth.fuelLitres - eco.truth.idleFuelLitres;

        expect(
          eco.truth.idleSeconds,
          closeTo(
            aggressive.truth.idleSeconds,
            aggressive.truth.idleSeconds * 0.05,
          ),
        );
        expect(ecoMoving, lessThan(aggressiveMoving * 0.8));
      },
    );

    test('the eco run takes longer, as gentle driving does', () {
      expect(
        run(DriveScenarios.ecoCity).seconds,
        greaterThan(run(DriveScenarios.aggressiveCity).seconds),
      );
    });

    test(
      'the aggressive run has one hard acceleration and one hard braking per block',
      () {
        final truth = run(DriveScenarios.aggressiveCity).truth;

        expect(truth.hardAccelerationCount, 12);
        expect(
          truth.hardBrakingCount,
          inInclusiveRange(12, 13),
          reason: 'the final stop may be a thirteenth',
        );
      },
    );

    test(
      'each scripted hard event is hard enough and long enough to be detected (CLAUDE.md 8.8)',
      () {
        for (final event in run(DriveScenarios.aggressiveCity).truth.events) {
          if (event.type == TruthEventType.hardAcceleration) {
            expect(event.peakAccelerationMs2, greaterThan(2.5));
            expect(event.durationSeconds, greaterThan(1.0));
          } else {
            expect(event.peakAccelerationMs2, greaterThan(3.5));
            expect(event.durationSeconds, greaterThan(0.5));
          }
        }
      },
    );

    test(
      'the app\'s own detectors, on whole-km/h speed samples, find the scripted events, within one',
      () {
        final aggressive = run(DriveScenarios.aggressiveCity);
        final found = _detect(aggressive.obdSpeeds);
        final truth = aggressive.truth;

        expect(
          (found.hardAcceleration - truth.hardAccelerationCount).abs(),
          lessThanOrEqualTo(1),
          reason:
              'acceleration: ${found.hardAcceleration} found, ${truth.hardAccelerationCount} scripted',
        );
        expect(
          (found.hardBraking - truth.hardBrakingCount).abs(),
          lessThanOrEqualTo(1),
          reason:
              'braking: ${found.hardBraking} found, ${truth.hardBrakingCount} scripted',
        );
      },
    );

    test(
      'the eco run has no scripted events, and the app\'s detectors find none either',
      () {
        final eco = run(DriveScenarios.ecoCity);
        final found = _detect(eco.obdSpeeds);

        expect(eco.truth.events, isEmpty);
        expect(found.hardAcceleration, 0);
        expect(found.hardBraking, 0);
        expect(eco.maxAccel, lessThan(2.0));
        expect(eco.maxDecel, lessThan(2.5));
      },
    );

    test('the aggressive run is fast and the eco run stays below 45 km/h', () {
      expect(run(DriveScenarios.aggressiveCity).maxKmh, closeTo(64, 3));
      expect(run(DriveScenarios.ecoCity).maxKmh, closeTo(45, 3));
    });

    test('both stop at the same signals', () {
      expect(
        run(DriveScenarios.ecoCity).stops,
        run(DriveScenarios.aggressiveCity).stops,
      );
    });
  });

  group('traffic_jam', () {
    test('lasts 15 minutes and is mostly idling', () {
      final r = run(DriveScenarios.trafficJam);

      expect(r.seconds, closeTo(900, 0.1));
      expect(r.idleShare, greaterThan(0.7));
    });

    test('only crawls, and the engine keeps running throughout', () {
      final r = run(DriveScenarios.trafficJam);

      expect(r.maxKmh, lessThan(15));
      expect(r.maxKmh, greaterThan(4));
      expect(r.truth.distanceKm, lessThan(0.6));
      expect(
        r.engineOffTicks,
        lessThan(60),
        reason: 'only the first seconds before the start',
      );
      expect(r.car.state.engineRunning, isTrue);
    });

    test('is the same jam every time', () {
      expect(
        _Run(DriveScenarios.trafficJam).speeds,
        run(DriveScenarios.trafficJam).speeds,
      );
    });
  });

  group('mixed_commute', () {
    test(
      'goes through city, highway and city, with the ignition off once part way',
      () {
        final r = run(DriveScenarios.mixedCommute());

        expect(r.maxKmh, inInclusiveRange(88, 96));
        expect(r.ignitionOffPeriods, hasLength(1));
        expect(r.truth.distanceKm, inInclusiveRange(25, 40));
        expect(r.seconds, greaterThan(25 * 60));
      },
    );

    test(
      'the default ignition-off is 3 minutes, so the trip resumes (under 5 minutes, CLAUDE.md 8.6)',
      () {
        final r = run(DriveScenarios.mixedCommute());

        expect(r.ignitionOffPeriods.single, closeTo(180, 2));
      },
    );

    test('the ignition-off time can be set, to make a new trip instead', () {
      final r = _Run(
        DriveScenarios.mixedCommute(ignitionOff: const Duration(minutes: 8)),
      );

      expect(r.ignitionOffPeriods.single, closeTo(480, 2));
    });

    test(
      'the engine is stopped while the ignition is off and restarts after',
      () {
        final r = run(DriveScenarios.mixedCommute());

        expect(r.engineOffTicks * 0.05, greaterThan(170));
        expect(r.car.state.engineRunning || r.car.isFinished, isTrue);
      },
    );

    test('the car is stopped when the ignition goes off', () {
      final car = SimulatedCar(scenario: DriveScenarios.mixedCommute());
      double? speedAtOff;
      while (!car.isFinished && speedAtOff == null) {
        car.tick();
        if (!car.state.ignitionOn && car.elapsedSeconds > 10) {
          speedAtOff = car.state.speedMs;
        }
      }

      expect(speedAtOff, 0);
    });
  });

  group('spirited_revs', () {
    test('is written for the sporty manual', () {
      expect(DriveScenarios.spiritedRevs.profile.name, 'petrol_manual_sporty');
    });

    test(
      'pulls to near the redline again and again, and changes gear through the pulls',
      () {
        final r = run(DriveScenarios.spiritedRevs);

        expect(r.maxRpm, inInclusiveRange(6200, 7100));
        expect(r.revPeaks, greaterThanOrEqualTo(8));
        expect(r.gearChanges, greaterThanOrEqualTo(10));
      },
    );

    test('logs each pull as a hard acceleration', () {
      expect(run(DriveScenarios.spiritedRevs).truth.hardAccelerationCount, 16);
    });

    test('lifts between pulls, with the fuel cut on engine braking', () {
      final car = SimulatedCar(scenario: DriveScenarios.spiritedRevs);
      var cutSeconds = 0.0;
      while (!car.isFinished) {
        car.tick();
        if (car.state.fuelCut) cutSeconds += VehicleModel.stepSeconds;
      }

      expect(cutSeconds, greaterThan(30));
    });

    test('the revs swing widely, which is what the needle work needs', () {
      final car = SimulatedCar(scenario: DriveScenarios.spiritedRevs);
      var low = 1e9;
      var high = 0.0;
      while (!car.isFinished) {
        car.tick();
        if (car.elapsedSeconds > 30) {
          low = math.min(low, car.state.rpm);
          high = math.max(high, car.state.rpm);
        }
      }

      expect(high - low, greaterThan(3500));
    });
  });

  group('dtc_present', () {
    test(
      'has P0420 and P0171 stored from the start, and the check-engine light on',
      () {
        final car = SimulatedCar(scenario: DriveScenarios.dtcPresent)..tick();

        expect(car.storedDtcs, ['P0420', 'P0171']);
        expect(car.pendingDtcs, isEmpty);
        expect(car.milOn, isTrue);
      },
    );

    test('clearing the codes clears the light', () {
      final car = SimulatedCar(scenario: DriveScenarios.dtcPresent)..tick();
      car.clearDtcs();

      expect(car.storedDtcs, isEmpty);
      expect(car.milOn, isFalse);
    });

    test('is a real drive as well', () {
      final r = run(DriveScenarios.dtcPresent);

      expect(r.seconds, closeTo(300, 0.1));
      expect(r.truth.distanceKm, greaterThan(1));
    });
  });

  group('adapter_flaky', () {
    test('uses flaky adapter quirks and a scheduled disconnect part way', () {
      final scenario = DriveScenarios.adapterFlaky;

      expect(scenario.quirks.noDataRate, greaterThan(0));
      expect(scenario.quirks.missingPromptRate, greaterThan(0));
      expect(scenario.quirks.garbageRate, greaterThan(0));
      expect(scenario.quirks.dropFirstCommand, isTrue);
      final fault = scenario.adapterFaults.single as AdapterDisconnect;
      expect(fault.at, const Duration(minutes: 4));
      expect(fault.outage, const Duration(seconds: 15));
    });

    test('the drive itself carries on regardless', () {
      final r = run(DriveScenarios.adapterFlaky);

      expect(r.seconds, closeTo(600, 0.1));
      expect(r.truth.distanceKm, greaterThan(2));
    });
  });

  group('the other scenarios', () {
    test('have no quirks and no faults', () {
      for (final scenario in DriveScenarios.all.where(
        (s) => s.name != 'adapter_flaky',
      )) {
        expect(scenario.adapterFaults, isEmpty, reason: scenario.name);
        expect(scenario.quirks.noDataRate, 0, reason: scenario.name);
      }
    });

    test('only dtc_present has fault codes', () {
      for (final scenario in DriveScenarios.all.where(
        (s) => s.name != 'dtc_present',
      )) {
        expect(scenario.dtcs, isEmpty, reason: scenario.name);
      }
    });

    test('every profile can drive every scenario', () {
      for (final profile in VehicleProfiles.all) {
        final car = SimulatedCar(
          scenario: DriveScenarios.cityStopGo,
          profile: profile,
        );
        while (car.elapsedSeconds < 240) {
          car.tick();
        }

        expect(car.truth.distanceKm, greaterThan(0.3), reason: profile.name);
        expect(car.state.speedKmh.isFinite, isTrue);
      }
    });
  });
}
