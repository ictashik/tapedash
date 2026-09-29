// Layer 3 (CLAUDE.md 10) for phase 4: the whole stack, from the simulated car
// to the trip record, against the simulator's ground truth. Fuel, money, idling,
// the trip's start and end, calibration and the Money Tape.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/coach/hard_event_detector.dart';
import 'package:tapedash/core/key_value_store.dart';
import 'package:tapedash/fuel/fuel_constants.dart';
import 'package:tapedash/fuel/fuel_estimator.dart';
import 'package:tapedash/money/calibration.dart';
import 'package:tapedash/money/fill_up.dart';
import 'package:tapedash/money/fuel_ledger.dart';
import 'package:tapedash/money/spend_bucket.dart';
import 'package:tapedash/obd/poller.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/vehicle_profile.dart';
import 'package:tapedash/trips/trip_recorder.dart';
import 'package:tapedash/vehicle/sensor.dart';

import 'trip_rig.dart';

const double price = 100;

void main() {
  group('accuracy against the truth, before any calibration', () {
    // CLAUDE.md 10: distance within 2%; fuel within 5% for the 5E and MAF
    // profiles and 10% for speed-density; idle time within 5% and idle cost
    // within 7%.
    for (final (profile, fuelTolerance) in [
      (VehicleProfiles.petrolCvtFuelRate, 0.05),
      (VehicleProfiles.petrolCvtMaf, 0.05),
      (VehicleProfiles.petrolCvtMap, 0.10),
      (VehicleProfiles.petrolManualSporty, 0.05),
    ]) {
      for (final scenario in [
        DriveScenarios.cityStopGo,
        DriveScenarios.highwayCruise,
        DriveScenarios.aggressiveCity,
        DriveScenarios.ecoCity,
        DriveScenarios.trafficJam,
      ]) {
        test('${profile.name}, ${scenario.name}', () async {
          final rig = TripRig(scenario, profile: profile, price: price)
            ..runToEnd();
          addTearDown(rig.close);
          await rig.recorder.idle;
          final truth = rig.rig.car.truth;
          final c = rig.computer;

          expect(
            relError(c.distanceKm.value, truth.distanceKm).abs(),
            lessThan(0.02),
            reason: 'distance',
          );
          expect(
            relError(c.litres.value, truth.fuelLitres).abs(),
            lessThan(fuelTolerance),
            reason: 'fuel: ${c.litres.value} against ${truth.fuelLitres}',
          );
          // Idling is only worth judging where there is some to judge.
          if (truth.idleSeconds > 60) {
            expect(
              relError(c.idleSeconds.value, truth.idleSeconds).abs(),
              lessThan(0.05),
              reason: 'idle time',
            );
            final idleCost = c.bucketLitres[SpendBucket.idling]! * price;
            expect(
              relError(idleCost, truth.idleFuelLitres * price).abs(),
              lessThan(0.07),
              reason: 'idle cost',
            );
            expect(c.idleCost.value, closeTo(idleCost, 1e-9));
          }
        });
      }
    }

    test('behind a Bluetooth clone (80 ms, jittery) it is no worse', () async {
      final rig = TripRig(
        DriveScenarios.cityStopGo,
        profile: VehicleProfiles.petrolCvtMaf,
        quirks: AdapterQuirks.bluetoothClone,
      )..runToEnd();
      addTearDown(rig.close);
      final truth = rig.rig.car.truth;
      expect(
        relError(rig.computer.litres.value, truth.fuelLitres).abs(),
        lessThan(0.05),
      );
      expect(
        relError(rig.computer.distanceKm.value, truth.distanceKm).abs(),
        lessThan(0.02),
      );
    });
  });

  group('the fuel source', () {
    for (final (profile, expected) in [
      (VehicleProfiles.petrolCvtFuelRate, FuelSource.fuelRate),
      (VehicleProfiles.petrolCvtMaf, FuelSource.airFlow),
      (VehicleProfiles.petrolCvtMap, FuelSource.speedDensity),
    ]) {
      test('${profile.name} uses ${expected.label}', () {
        final rig = TripRig(DriveScenarios.cityStopGo, profile: profile)
          ..rig.run(120);
        addTearDown(rig.close);
        expect(rig.estimator.source.value, expected);
      });
    }

    test('while a trip is recorded its PID is polled at the fast tier', () {
      final rig = TripRig(
        DriveScenarios.cityStopGo,
        profile: VehicleProfiles.petrolCvtMaf,
      )..rig.run(60);
      addTearDown(rig.close);
      expect(rig.recorder.recording, isTrue);
      expect(rig.rig.session.poller!.tierOf(0x10), PollTier.fast);
      expect(rig.demand.held, {0x10});
    });

    test('the fast tier is given back when the trip ends', () {
      // The drive ends and the engine is switched off.
      final rig = TripRig(simpleTrip(), profile: VehicleProfiles.petrolCvtMaf)
        ..rig.run(300);
      addTearDown(rig.close);
      expect(rig.recorder.recording, isFalse);
      expect(rig.demand.held, isEmpty);
      expect(rig.rig.session.poller?.tierOf(0x10), isNot(PollTier.fast));
    });

    test('an old car with no fuel PID has no fuel and no money', () async {
      final rig = TripRig(
        DriveScenarios.cityStopGo,
        profile: VehicleProfiles.minimalOldCar,
      )..runToEnd();
      addTearDown(rig.close);
      expect(rig.estimator.source.value, FuelSource.none);
      expect(rig.computer.fuelKnown.value, isFalse);
      expect(rig.computer.cost.value, isNull);
      expect(rig.computer.costPerKm.value, isNull);
      expect(rig.computer.litres.value, 0);
      // What can work does: the trip and its distance.
      final truth = rig.rig.car.truth;
      expect(
        relError(rig.computer.distanceKm.value, truth.distanceKm).abs(),
        lessThan(0.02),
      );
    });

    test(
      'a diesel with air flow is estimated, and flagged low confidence',
      () async {
        final rig = TripRig(
          DriveScenarios.cityStopGo,
          profile: VehicleProfiles.dieselManual,
        )..runToEnd();
        addTearDown(rig.close);
        await rig.recorder.idle;
        expect(rig.computer.fuelKnown.value, isTrue);
        expect(rig.computer.lowConfidence, isTrue);
        final trip = await rig.trips.get(1);
        expect(trip!.lowConfidence, isTrue);
      },
    );
  });

  group('calibration', () {
    // A car is filled to the top, driven, filled to the top again; the second
    // fill-up says what the drives really burnt, and the next drive's estimate
    // is corrected by it (CLAUDE.md 8.5). The simulator's own tank says what
    // was really burnt.
    Future<FuelLedger> fillDriveFill(
      VehicleProfile profile, {
      VehicleSetup? setup,
    }) async {
      final fills = MemoryFillUpRepository();
      final ledger = FuelLedger(fills: fills, store: MemoryKeyValueStore());
      await ledger.recordFillUp(
        at: DateTime(2026, 1, 1),
        litres: 30,
        amount: 3000,
        fullTank: true,
      );
      var burnt = 0.0;
      for (final scenario in [
        DriveScenarios.highwayCruise,
        DriveScenarios.cityStopGo,
      ]) {
        final rig = TripRig(scenario, profile: profile, sharedLedger: ledger);
        if (setup != null) rig.estimator.setup = setup;
        rig.runToEnd();
        burnt += rig.rig.car.truth.fuelLitres;
        await rig.close();
      }
      expect(burnt, greaterThan(FuelLedger.minLitres));
      await ledger.recordFillUp(
        at: DateTime(2026, 1, 4),
        litres: burnt,
        amount: burnt * price,
        fullTank: true,
      );
      return ledger;
    }

    for (final profile in [
      VehicleProfiles.petrolCvtFuelRate,
      VehicleProfiles.petrolCvtMaf,
      VehicleProfiles.petrolCvtMap,
      VehicleProfiles.petrolManualSporty,
    ]) {
      test('${profile.name}: after two full tanks it is within 3%', () async {
        final ledger = await fillDriveFill(profile);
        expect(
          ledger.calibration.confidence,
          CalibrationConfidence.calibrating,
        );
        final next = TripRig(
          DriveScenarios.aggressiveCity,
          profile: profile,
          sharedLedger: ledger,
          seed: 7,
        )..runToEnd();
        addTearDown(next.close);
        expect(
          relError(
            next.computer.litres.value,
            next.rig.car.truth.fuelLitres,
          ).abs(),
          lessThan(0.03),
        );
      });
    }

    test(
      'it corrects a wrong displacement (1.2 L set for a 1.5 L engine)',
      () async {
        const wrong = VehicleSetup(displacementLitres: 1.2);
        // Uncalibrated, the speed-density estimate is a fifth low.
        final probe = TripRig(
          DriveScenarios.aggressiveCity,
          profile: VehicleProfiles.petrolCvtMap,
        );
        probe.estimator.setup = wrong;
        probe.runToEnd();
        addTearDown(probe.close);
        expect(
          relError(probe.computer.litres.value, probe.rig.car.truth.fuelLitres),
          lessThan(-0.12),
        );

        final ledger = await fillDriveFill(
          VehicleProfiles.petrolCvtMap,
          setup: wrong,
        );
        expect(ledger.calibration.factor, greaterThan(1.15));
        final next = TripRig(
          DriveScenarios.aggressiveCity,
          profile: VehicleProfiles.petrolCvtMap,
          sharedLedger: ledger,
          seed: 5,
        );
        next.estimator.setup = wrong;
        next.runToEnd();
        addTearDown(next.close);
        expect(
          relError(
            next.computer.litres.value,
            next.rig.car.truth.fuelLitres,
          ).abs(),
          lessThan(0.05),
        );
      },
    );

    test(
      'a diesel stays low confidence until it has been calibrated',
      () async {
        final before = TripRig(
          DriveScenarios.cityStopGo,
          profile: VehicleProfiles.dieselManual,
        )..runToEnd();
        addTearDown(before.close);
        expect(before.computer.lowConfidence, isTrue);
        expect(
          before.ledger.calibration.confidence,
          CalibrationConfidence.uncalibrated,
        );
      },
    );
  });

  group('the coach\'s hard events', () {
    test('aggressive_city: counts match the scripted events, within one', () {
      final rig = TripRig(DriveScenarios.aggressiveCity)..runToEnd();
      addTearDown(rig.close);
      final truth = rig.rig.car.truth;
      final events = rig.hard.events;
      final accels = events
          .where((e) => e.type == HardEventType.hardAcceleration)
          .length;
      final brakes = events
          .where((e) => e.type == HardEventType.hardBraking)
          .length;
      expect(truth.hardAccelerationCount, greaterThan(3));
      expect(
        (accels - truth.hardAccelerationCount).abs(),
        lessThanOrEqualTo(1),
      );
      expect((brakes - truth.hardBrakingCount).abs(), lessThanOrEqualTo(1));
    });

    test('eco_city finds none, or next to none', () {
      final rig = TripRig(DriveScenarios.ecoCity)..runToEnd();
      addTearDown(rig.close);
      expect(rig.hard.events.length, lessThanOrEqualTo(1));
    });
  });

  group('where the money went', () {
    test(
      'the buckets add up to the trip, and the hard bucket is used',
      () async {
        final rig = TripRig(DriveScenarios.aggressiveCity, price: price)
          ..runToEnd();
        addTearDown(rig.close);
        final c = rig.computer;
        c.finish();
        final sum = c.bucketLitres.values.fold<double>(0, (a, b) => a + b);
        expect(c.pendingLitres, 0);
        expect(sum, closeTo(c.litres.value, 1e-9));
        expect(c.bucketLitres[SpendBucket.hardAcceleration]!, greaterThan(0));
        expect(c.bucketLitres[SpendBucket.idling]!, greaterThan(0));
        final costs = c.bucketCosts!.values.fold<double>(0, (a, b) => a + b);
        expect(costs, closeTo(c.cost.value!, 1e-6));
      },
    );

    test(
      'the Money Tape adds up to the total and matches the buckets',
      () async {
        final rig = TripRig(DriveScenarios.aggressiveCity, price: 400)
          ..runToEnd();
        addTearDown(rig.close);
        final c = rig.computer..finish();
        expect(c.blocks.length, c.cost.value!.floor());
        expect(c.blocks.length, greaterThan(5));
        final costs = c.bucketCosts!;
        for (final b in SpendBucket.values) {
          final count = c.blocks.where((e) => e.bucket == b).length;
          expect((count - costs[b]!).abs(), lessThan(1.0), reason: '$b');
        }
        for (var i = 0; i < c.blocks.length; i++) {
          expect(c.blocks[i].index, i + 1);
          if (i > 0) expect(c.blocks[i].at >= c.blocks[i - 1].at, isTrue);
        }
      },
    );

    test(
      'eco_city costs at least 15% less than aggressive_city, same route',
      () {
        final aggressive = TripRig(DriveScenarios.aggressiveCity, price: price)
          ..runToEnd();
        final eco = TripRig(DriveScenarios.ecoCity, price: price)..runToEnd();
        addTearDown(aggressive.close);
        addTearDown(eco.close);
        final a = aggressive.computer.cost.value!;
        final e = eco.computer.cost.value!;
        expect(e, lessThan(a * 0.85), reason: 'eco $e against aggressive $a');
        // The same road, to within a little.
        expect(
          eco.computer.distanceKm.value,
          closeTo(aggressive.computer.distanceKm.value, 0.3),
        );
      },
    );
  });

  group('trips: start, end, resume', () {
    test('a drive is one trip, saved with its samples', () async {
      final rig = TripRig(simpleTrip(), price: price)..rig.run(300);
      addTearDown(rig.close);
      await rig.recorder.idle;
      final all = await rig.trips.all();
      expect(all.length, 1);
      final trip = all.single;
      final truth = rig.rig.car.truth;
      expect(trip.isOpen, isFalse);
      expect(trip.isDemo, isFalse);
      expect(relError(trip.distanceKm, truth.distanceKm).abs(), lessThan(0.02));
      expect(trip.cost, closeTo(trip.litres * price, 1e-6));
      expect(trip.pricePerLitre, price);
      expect(trip.fuelSource, FuelSource.airFlow);
      expect(trip.blockBuckets.length, trip.cost!.floor());
      final samples = await rig.trips.samples(trip.id!);
      // One a second while the engine ran.
      expect(samples.length, closeTo(trip.engineSeconds, 12));
      expect(samples.first.seconds, lessThan(samples.last.seconds));
      expect(rig.recorder.phase.value, TripPhase.ended);
    });

    test(
      'a trip started in demo is stored, flagged, and left out of statistics',
      () async {
        final rig = TripRig(DriveScenarios.cityStopGo, isDemo: true)
          ..rig.run(90);
        addTearDown(rig.close);
        await rig.recorder.close();
        expect((await rig.trips.all()).length, 0);
        expect((await rig.trips.all(includeDemo: true)).single.isDemo, isTrue);
      },
    );

    test(
      'traffic_jam: standing still with the engine on never ends a trip',
      () async {
        final rig = TripRig(DriveScenarios.trafficJam);
        addTearDown(rig.close);
        var ended = 0;
        rig.recorder.onTripEnded((_) => ended++);
        rig.runToEnd();
        rig.rig.run(600); // a further ten minutes of idling after the script.
        await rig.recorder.idle;
        expect(ended, 0);
        expect(rig.recorder.phase.value, TripPhase.running);
        expect((await rig.trips.all()).length, 1);
      },
    );

    test(
      'mixed_commute, engine off for 3 minutes: the same trip resumes',
      () async {
        final rig = TripRig(DriveScenarios.mixedCommute());
        addTearDown(rig.close);
        var ended = 0;
        var resumed = 0;
        rig.recorder.onTripEnded((_) => ended++);
        rig.recorder.onTripResumed((_) => resumed++);
        rig.runToEnd();
        await rig.recorder.idle;
        expect(ended, 1);
        expect(resumed, 1);
        expect((await rig.trips.all()).length, 1);
      },
    );

    test('mixed_commute, engine off for 8 minutes: a new trip', () async {
      final rig = TripRig(
        DriveScenarios.mixedCommute(ignitionOff: const Duration(minutes: 8)),
      );
      addTearDown(rig.close);
      var resumed = 0;
      rig.recorder.onTripResumed((_) => resumed++);
      rig.runToEnd();
      await rig.recorder.idle;
      expect(resumed, 0);
      final all = await rig.trips.all();
      expect(all.length, 2);
      // The second starts where the first stopped counting: from nothing.
      expect(all.first.distanceKm, greaterThan(5));
      expect(all.last.distanceKm, greaterThan(5));
    });

    test(
      'adapter_flaky: it reconnects, the trip goes on as one, no fuel spike',
      () async {
        final rig = TripRig(DriveScenarios.adapterFlaky, price: price);
        addTearDown(rig.close);
        var peak = 0.0;
        rig.estimator.flow.addListener(() {
          final f = rig.estimator.flow.value!;
          if (f.litresPerHour > peak) peak = f.litresPerHour;
        });
        var ended = 0;
        rig.recorder.onTripEnded((_) => ended++);
        rig.runToEnd();
        await rig.recorder.idle;
        expect(rig.rig.session.reconnects, greaterThan(0));
        expect(ended, 0);
        expect((await rig.trips.all()).length, 1);
        final truth = rig.rig.car.truth;
        // Missing data does not become fuel: the estimate is near the truth, and
        // no estimate is beyond what the engine can burn.
        expect(
          relError(rig.computer.litres.value, truth.fuelLitres).abs(),
          lessThan(0.12),
        );
        expect(peak, lessThan(40));
        expect(
          rig.computer.distanceKm.value,
          closeTo(truth.distanceKm, truth.distanceKm * 0.06),
        );
      },
    );
  });

  test('every sensor the money needs is polled while driving', () {
    final rig = TripRig(
      DriveScenarios.cityStopGo,
      profile: VehicleProfiles.petrolCvtMap,
    )..rig.run(60);
    addTearDown(rig.close);
    for (final s in [Sensor.manifoldPressure, Sensor.intakeAir, Sensor.rpm]) {
      expect(rig.rig.vehicle.reading(s).value, isNotNull, reason: '$s');
    }
  });
}
