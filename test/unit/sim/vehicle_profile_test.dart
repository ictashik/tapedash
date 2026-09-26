import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/sim/engine_model.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/vehicle_profile.dart';

double _peakPowerKw(VehicleProfile profile) {
  final engine = EngineModel.forSpec(profile.engine);
  var peak = 0.0;
  for (var rpm = profile.idleRpm + 200; rpm <= profile.redlineRpm; rpm += 100) {
    final o = engine.run(rpm: rpm, demand: 1, intakeAirC: 35);
    peak = math.max(peak, o.torqueNm * rpm * 2 * math.pi / 60 / 1000);
  }
  return peak;
}

void main() {
  group('the profile list', () {
    test('has the six profiles of CLAUDE.md 7.2', () {
      expect(VehicleProfiles.all.map((p) => p.name), [
        'petrol_cvt_maf',
        'petrol_cvt_map',
        'petrol_cvt_fuelrate',
        'petrol_manual_sporty',
        'minimal_old_car',
        'diesel_manual',
      ]);
    });

    test('byName finds each, and nothing else', () {
      for (final profile in VehicleProfiles.all) {
        expect(VehicleProfiles.byName(profile.name), same(profile));
      }
      expect(VehicleProfiles.byName('petrol'), isNull);
      expect(VehicleProfiles.byName(''), isNull);
    });
  });

  group('supported PIDs', () {
    const withMaf = {
      0x04,
      0x05,
      0x0B,
      0x0C,
      0x0D,
      0x0F,
      0x10,
      0x11,
      0x2F,
      0x42,
    };

    test(
      'petrol_cvt_maf supports 04, 05, 0B, 0C, 0D, 0F, 10, 11, 2F and 42',
      () {
        expect(VehicleProfiles.petrolCvtMaf.supportedPids, withMaf);
      },
    );

    test(
      'petrol_cvt_map is the same but has no MAF (10), so speed-density is needed',
      () {
        final pids = VehicleProfiles.petrolCvtMap.supportedPids;

        expect(pids, withMaf.difference({0x10}));
        // Speed-density needs MAP, intake air temperature and RPM.
        expect(pids, containsAll([pidMap, pidIntakeAir, pidRpm]));
      },
    );

    test('petrol_cvt_fuelrate also supports 5E', () {
      expect(VehicleProfiles.petrolCvtFuelRate.supportedPids, {
        ...withMaf,
        0x5E,
      });
    });

    test('petrol_manual_sporty and diesel_manual answer the MAF set', () {
      expect(VehicleProfiles.petrolManualSporty.supportedPids, withMaf);
      expect(VehicleProfiles.dieselManual.supportedPids, withMaf);
    });

    test('minimal_old_car answers only 04, 05, 0C, 0D and 11', () {
      expect(VehicleProfiles.minimalOldCar.supportedPids, {
        0x04,
        0x05,
        0x0C,
        0x0D,
        0x11,
      });
    });

    test('PID 01 is always supported, since every OBD-II ECU has it', () {
      for (final profile in VehicleProfiles.all) {
        expect(profile.supports(0x01), isTrue, reason: profile.name);
        expect(profile.supportedPids, isNot(contains(0x01)));
      }
    });

    test('supports() is true for the listed PIDs and false for others', () {
      expect(VehicleProfiles.petrolCvtMaf.supports(0x0C), isTrue);
      expect(VehicleProfiles.petrolCvtMaf.supports(0x5E), isFalse);
      expect(VehicleProfiles.petrolCvtMap.supports(0x10), isFalse);
    });

    test(
      'every PID is a Mode 01 PID in the range the PID matrix shows (01 to 60)',
      () {
        for (final profile in VehicleProfiles.all) {
          for (final pid in profile.supportedPids) {
            expect(pid, inInclusiveRange(0x01, 0x60), reason: profile.name);
          }
        }
      },
    );

    test('the PID constants are the ones CLAUDE.md 8.3 lists', () {
      expect(
        [
          pidLoad,
          pidCoolant,
          pidMap,
          pidRpm,
          pidSpeed,
          pidIntakeAir,
          pidMaf,
          pidThrottle,
          pidFuelLevel,
          pidVoltage,
          pidFuelRate,
        ],
        [0x04, 0x05, 0x0B, 0x0C, 0x0D, 0x0F, 0x10, 0x11, 0x2F, 0x42, 0x5E],
      );
    });
  });

  group('every profile', () {
    for (final profile in VehicleProfiles.all) {
      test('${profile.name} is a plausible car', () {
        expect(profile.idleRpm, inInclusiveRange(600, 1000));
        expect(profile.idleRpm, lessThan(profile.redlineRpm));
        expect(profile.redlineRpm, lessThan(profile.tachMaxRpm));
        expect(profile.massKg, inInclusiveRange(800, 2000));
        expect(profile.tankLitres, inInclusiveRange(30, 80));
        expect(profile.dragAreaM2, inInclusiveRange(0.5, 1.0));
        expect(profile.maxBrakeDecelMs2, closeTo(8, 1));
        expect(profile.description, isNotEmpty);
      });

      test('${profile.name} has an engine that makes 50 to 130 kW', () {
        expect(_peakPowerKw(profile), inInclusiveRange(50, 130));
      });
    }

    test(
      'the petrol profiles idle at about 30 kPa on 0.6 to 1.0 litres an hour',
      () {
        for (final profile in VehicleProfiles.all.where((p) => !p.isDiesel)) {
          final engine = EngineModel.forSpec(profile.engine) as PetrolEngine;
          final o = engine.run(rpm: profile.idleRpm, demand: 0, intakeAirC: 35);

          expect(o.manifoldKpa, inInclusiveRange(27, 36), reason: profile.name);
          expect(
            o.fuelGramsPerSecond * 3600 / 740,
            inInclusiveRange(0.5, 1.1),
            reason: profile.name,
          );
        }
      },
    );
  });

  group('transmissions', () {
    test('the three CVT profiles use a CVT', () {
      for (final profile in [
        VehicleProfiles.petrolCvtMaf,
        VehicleProfiles.petrolCvtMap,
        VehicleProfiles.petrolCvtFuelRate,
        VehicleProfiles.minimalOldCar,
      ]) {
        expect(
          profile.transmission,
          isA<CvtTransmission>(),
          reason: profile.name,
        );
      }
    });

    test('the sporty and diesel profiles are manual with gears in order', () {
      for (final profile in [
        VehicleProfiles.petrolManualSporty,
        VehicleProfiles.dieselManual,
      ]) {
        final gearbox = profile.transmission as ManualTransmission;

        for (var i = 1; i < gearbox.gearRatios.length; i++) {
          expect(
            gearbox.gearRatios[i],
            lessThan(gearbox.gearRatios[i - 1]),
            reason: profile.name,
          );
        }
        expect(
          gearbox.upshiftRpmAtFullPedal,
          lessThanOrEqualTo(profile.redlineRpm),
        );
        expect(
          gearbox.upshiftRpmAtLightPedal,
          lessThan(gearbox.upshiftRpmAtFullPedal),
        );
        expect(gearbox.downshiftRpm, greaterThan(profile.idleRpm));
      }
    });

    test(
      'the sporty car has six gears and a 7,000 rpm redline (CLAUDE.md 7.2)',
      () {
        final sporty = VehicleProfiles.petrolManualSporty;

        expect(
          (sporty.transmission as ManualTransmission).gearRatios,
          hasLength(6),
        );
        expect(sporty.redlineRpm, 7000);
      },
    );

    test(
      'a manual car cruising at 100 km/h in top gear turns over at a sensible speed',
      () {
        for (final profile in [
          VehicleProfiles.petrolManualSporty,
          VehicleProfiles.dieselManual,
        ]) {
          final gearbox = profile.transmission as ManualTransmission;
          final wheelRevsPerMinute =
              (100 / 3.6) / (2 * math.pi * gearbox.wheelRadiusM) * 60;
          final rpm =
              wheelRevsPerMinute * gearbox.gearRatios.last * gearbox.finalDrive;

          expect(rpm, inInclusiveRange(1900, 3200), reason: profile.name);
        }
      },
    );
  });

  group('fuel', () {
    test('only the diesel profile is a diesel', () {
      expect(VehicleProfiles.all.where((p) => p.isDiesel).map((p) => p.name), [
        'diesel_manual',
      ]);
    });

    test('petrol is 740 g/L at 14.7 to 1, the figures CLAUDE.md 8.4 uses', () {
      final fuel = VehicleProfiles.petrolCvtMaf.fuel;

      expect(fuel.densityGramsPerLitre, 740);
      expect(fuel.stoichiometricAirFuelRatio, 14.7);
    });

    test('diesel is denser than petrol', () {
      expect(
        VehicleProfiles.dieselManual.fuel.densityGramsPerLitre,
        greaterThan(VehicleProfiles.petrolCvtMaf.fuel.densityGramsPerLitre),
      );
    });
  });
}
