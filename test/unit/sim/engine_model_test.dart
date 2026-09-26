import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/sim/engine_model.dart';
import 'package:tapedash/sim/engine_spec.dart';

const _iat = 35.0;
const _rpmGrid = [800.0, 1500.0, 2500.0, 4000.0, 6000.0];
const _demandGrid = [0.0, 0.1, 0.3, 0.6, 1.0];

double _kw(EngineOutput o, double rpm) =>
    o.torqueNm * rpm * 2 * math.pi / 60 / 1000;

void main() {
  const spec = PetrolSpec(displacementLitres: 1.5);
  final petrol = PetrolEngine(spec);

  group('interpolate', () {
    const points = [(0.0, 10.0), (10.0, 20.0), (20.0, 20.0), (30.0, 0.0)];

    test('is linear between points', () {
      expect(interpolate(points, 5), 15);
      expect(interpolate(points, 25), 10);
      expect(interpolate(points, 10), 20);
    });

    test('holds the end values outside the range', () {
      expect(interpolate(points, -5), 10);
      expect(interpolate(points, 99), 0);
    });
  });

  group('the volumetric efficiency curves', () {
    test('stay between 0.5 and 1.05', () {
      for (final curve in [
        VolumetricEfficiencyCurve.typicalPetrol,
        VolumetricEfficiencyCurve.typicalDiesel,
      ]) {
        for (var rpm = 0.0; rpm <= 9000; rpm += 100) {
          expect(curve.at(rpm), inInclusiveRange(0.5, 1.05));
        }
      }
    });

    test('a petrol road engine fills worst at low revs', () {
      const curve = VolumetricEfficiencyCurve.typicalPetrol;

      expect(curve.at(1000), lessThan(curve.at(4000)));
      expect(curve.at(4000), greaterThan(curve.at(7500)));
    });
  });

  group('petrol manifold pressure', () {
    test('is about 30 kPa at idle, on a closed throttle at 750 rpm', () {
      expect(
        petrol.run(rpm: 750, demand: 0, intakeAirC: _iat).manifoldKpa,
        inInclusiveRange(28, 33),
      );
    });

    test('is about 98 kPa with the throttle wide open', () {
      for (final rpm in [1000.0, 2500.0, 4000.0, 6500.0]) {
        final map = petrol
            .run(rpm: rpm, demand: 1, intakeAirC: _iat)
            .manifoldKpa;

        expect(map, inInclusiveRange(90, 101), reason: '$rpm rpm');
      }
    });

    test('rises with the throttle', () {
      for (final rpm in _rpmGrid) {
        var previous = 0.0;
        for (final demand in _demandGrid) {
          final map = petrol
              .run(rpm: rpm, demand: demand, intakeAirC: _iat)
              .manifoldKpa;

          expect(
            map,
            greaterThanOrEqualTo(previous),
            reason: '$rpm rpm, demand $demand',
          );
          previous = map;
        }
      }
    });

    test('falls as revs rise, for the same throttle', () {
      for (final demand in [0.1, 0.3, 0.6]) {
        var previous = double.infinity;
        for (final rpm in _rpmGrid) {
          final map = petrol
              .run(rpm: rpm, demand: demand, intakeAirC: _iat)
              .manifoldKpa;

          expect(
            map,
            lessThanOrEqualTo(previous),
            reason: 'demand $demand at $rpm',
          );
          previous = map;
        }
      }
    });

    test('never falls below the closed-throttle floor', () {
      for (final rpm in _rpmGrid) {
        expect(
          petrol.run(rpm: rpm, demand: 0, intakeAirC: _iat).manifoldKpa,
          greaterThanOrEqualTo(spec.minimumManifoldKpa),
        );
      }
    });

    test('is barely changed by the floor away from it', () {
      // 750 rpm, closed throttle: the formula alone gives 30.3 kPa.
      expect(
        petrol.run(rpm: 750, demand: 0, intakeAirC: _iat).manifoldKpa,
        closeTo(30.4, 0.3),
      );
    });
  });

  group('petrol air and fuel', () {
    test('air flow is the speed-density formula of CLAUDE.md 8.4', () {
      for (final rpm in _rpmGrid) {
        for (final demand in _demandGrid) {
          final o = petrol.run(rpm: rpm, demand: demand, intakeAirC: _iat);
          final ve = spec.volumetricEfficiency.at(rpm);
          // MAF (g/s) = 1000 * MAP * displacement * (rpm / 120) * VE / (287.05 * T)
          final expected =
              1000 *
              o.manifoldKpa *
              1.5 *
              (rpm / 120) *
              ve /
              (287.05 * (_iat + 273.15));

          expect(
            o.airGramsPerSecond,
            closeTo(expected, expected * 1e-9),
            reason: '$rpm rpm, demand $demand',
          );
        }
      }
    });

    test('fuel is air over 14.7, and litres per hour follow CLAUDE.md 8.4', () {
      for (final rpm in _rpmGrid) {
        for (final demand in _demandGrid) {
          final o = petrol.run(rpm: rpm, demand: demand, intakeAirC: _iat);
          // L/h = MAF * 3600 / (AFR * density)
          final litresPerHour = o.airGramsPerSecond * 3600 / (14.7 * 740);

          expect(
            o.fuelGramsPerSecond * 3600 / 740,
            closeTo(litresPerHour, litresPerHour * 1e-9),
          );
        }
      }
    });

    test(
      'warmer intake air is thinner, so there is less air and less fuel',
      () {
        final cool = petrol.run(rpm: 2500, demand: 0.5, intakeAirC: 20);
        final hot = petrol.run(rpm: 2500, demand: 0.5, intakeAirC: 60);

        expect(hot.airGramsPerSecond, lessThan(cool.airGramsPerSecond));
        expect(hot.fuelGramsPerSecond, lessThan(cool.fuelGramsPerSecond));
      },
    );

    test(
      'fuel cut-off injects nothing, the air keeps flowing, and the engine brakes',
      () {
        final o = petrol.run(
          rpm: 2500,
          demand: 0,
          intakeAirC: _iat,
          fuelCut: true,
        );

        expect(o.fuelGramsPerSecond, 0);
        expect(o.airGramsPerSecond, greaterThan(1));
        expect(o.torqueNm, inInclusiveRange(-40, -10));
      },
    );

    test('idle burns about 0.7 to 0.9 litres an hour', () {
      final o = petrol.run(rpm: 750, demand: 0, intakeAirC: _iat);

      expect(o.fuelGramsPerSecond * 3600 / 740, inInclusiveRange(0.6, 1.0));
    });

    test('a stopped engine has no flow and no NaN', () {
      final o = petrol.run(rpm: 0, demand: 0, intakeAirC: _iat);

      expect(o.airGramsPerSecond, 0);
      expect(o.fuelGramsPerSecond, 0);
      for (final v in [o.torqueNm, o.manifoldKpa, o.loadFraction]) {
        expect(v.isFinite, isTrue);
      }
    });

    test('load is about a third at idle and full at full throttle', () {
      expect(
        petrol.run(rpm: 750, demand: 0, intakeAirC: _iat).loadFraction,
        inInclusiveRange(0.25, 0.4),
      );
      expect(
        petrol.run(rpm: 3000, demand: 1, intakeAirC: _iat).loadFraction,
        closeTo(1, 1e-9),
      );
    });
  });

  group('petrol torque', () {
    test('rises with the throttle at any speed', () {
      for (final rpm in _rpmGrid) {
        var previous = -double.infinity;
        for (final demand in _demandGrid) {
          final t = petrol
              .run(rpm: rpm, demand: demand, intakeAirC: _iat)
              .torqueNm;

          expect(t, greaterThan(previous), reason: '$rpm rpm, demand $demand');
          previous = t;
        }
      }
    });

    test(
      'a 1.5 litre engine makes 120 to 150 N m and 70 to 95 kW at full throttle',
      () {
        var peakTorque = 0.0;
        var peakPower = 0.0;
        var peakPowerRpm = 0.0;
        for (var rpm = 1000.0; rpm <= 7000; rpm += 250) {
          final o = petrol.run(rpm: rpm, demand: 1, intakeAirC: _iat);
          peakTorque = math.max(peakTorque, o.torqueNm);
          if (_kw(o, rpm) > peakPower) {
            peakPower = _kw(o, rpm);
            peakPowerRpm = rpm;
          }
        }

        expect(peakTorque, inInclusiveRange(120, 150));
        expect(peakPower, inInclusiveRange(70, 95));
        expect(peakPowerRpm, greaterThan(5500));
      },
    );

    test(
      'a closed throttle at idle makes a small positive torque, to hold the revs',
      () {
        final t = petrol.run(rpm: 750, demand: 0, intakeAirC: _iat).torqueNm;

        expect(t, inInclusiveRange(0, 6));
      },
    );

    test('a cold engine makes less torque for the same throttle', () {
      final warm = petrol.run(rpm: 1500, demand: 0.3, intakeAirC: _iat);
      final cold = petrol.run(
        rpm: 1500,
        demand: 0.3,
        intakeAirC: _iat,
        frictionScale: 1.35,
      );

      expect(cold.torqueNm, lessThan(warm.torqueNm));
      expect(cold.fuelGramsPerSecond, warm.fuelGramsPerSecond);
    });

    test('economy at a steady speed is plausible for a small petrol hatch', () {
      // Road load on the flat for 1150 kg, CdA 0.68 and 90% drivetrain
      // efficiency, worked out here and not taken from the simulator.
      double litresPer100km(double kmh, double rpm) {
        final v = kmh / 3.6;
        final force = 0.011 * 1150 * 9.81 + 0.5 * 1.2 * 0.68 * v * v;
        final torque = force * v / 0.90 / (rpm * 2 * math.pi / 60);
        final demand = petrol.demandForTorque(
          rpm: rpm,
          torqueNm: torque,
          intakeAirC: _iat,
        );
        final o = petrol.run(rpm: rpm, demand: demand, intakeAirC: _iat);
        return o.fuelGramsPerSecond * 3600 / 740 / kmh * 100;
      }

      expect(litresPer100km(60, 1670), inInclusiveRange(4.0, 6.0));
      expect(litresPer100km(100, 2050), inInclusiveRange(4.8, 7.0));
      expect(litresPer100km(120, 2240), greaterThan(litresPer100km(60, 1670)));
    });
  });

  group('demandForTorque', () {
    test('finds the throttle that delivers a torque', () {
      for (final rpm in [1200.0, 2500.0, 4500.0]) {
        for (final torque in [10.0, 40.0, 80.0]) {
          final demand = petrol.demandForTorque(
            rpm: rpm,
            torqueNm: torque,
            intakeAirC: _iat,
          );
          final actual = petrol
              .run(rpm: rpm, demand: demand, intakeAirC: _iat)
              .torqueNm;

          expect(
            actual,
            closeTo(torque, 0.01),
            reason: '$torque N m at $rpm rpm',
          );
        }
      }
    });

    test('is 0 or 1 when the torque is out of reach', () {
      expect(
        petrol.demandForTorque(rpm: 3000, torqueNm: -200, intakeAirC: _iat),
        0,
      );
      expect(
        petrol.demandForTorque(rpm: 3000, torqueNm: 500, intakeAirC: _iat),
        1,
      );
    });

    test('needs more throttle for more torque', () {
      final small = petrol.demandForTorque(
        rpm: 2500,
        torqueNm: 20,
        intakeAirC: _iat,
      );
      final large = petrol.demandForTorque(
        rpm: 2500,
        torqueNm: 90,
        intakeAirC: _iat,
      );

      expect(large, greaterThan(small));
    });
  });

  group('the pedal', () {
    test('asks for nothing when up and everything when down', () {
      expect(petrol.demandForPedal(0), 0);
      expect(petrol.demandForPedal(1), 1);
    });

    test('opens the throttle progressively', () {
      var previous = -1.0;
      for (var p = 0.0; p <= 1.0; p += 0.05) {
        final demand = petrol.demandForPedal(p);

        expect(demand, greaterThan(previous));
        previous = demand;
      }
    });

    test('a light pedal is a small throttle opening', () {
      expect(petrol.demandForPedal(0.2), inInclusiveRange(0.08, 0.2));
    });

    test(
      'the throttle position PID reads the absolute position: never below 12%',
      () {
        expect(petrol.reportedThrottleFraction(0), closeTo(0.12, 1e-12));
        expect(petrol.reportedThrottleFraction(1), closeTo(1, 1e-12));
      },
    );

    test('out-of-range pedals are held to 0 and 1', () {
      expect(petrol.demandForPedal(-0.5), 0);
      expect(petrol.demandForPedal(2), 1);
    });
  });

  group('diesel', () {
    final diesel = DieselEngine(
      const DieselSpec(
        displacementLitres: 1.5,
        maximumTorqueCurve: [
          (1000, 130),
          (1500, 200),
          (2000, 240),
          (3000, 240),
          (4000, 205),
          (5000, 150),
        ],
      ),
    );

    test(
      'delivers the rated torque at full load once the turbo has spooled',
      () {
        expect(
          diesel.run(rpm: 2500, demand: 1, intakeAirC: _iat).torqueNm,
          closeTo(240, 0.5),
        );
        expect(
          diesel.run(rpm: 4000, demand: 1, intakeAirC: _iat).torqueNm,
          closeTo(205, 0.5),
        );
      },
    );

    test('is held by the smoke limit while the turbo is still spooling', () {
      final o = diesel.run(rpm: 1200, demand: 1, intakeAirC: _iat);

      expect(
        o.torqueNm,
        lessThan(interpolate(diesel.spec.maximumTorqueCurve, 1200)),
      );
      expect(o.airGramsPerSecond / o.fuelGramsPerSecond, closeTo(17, 0.001));
    });

    test('the mixture is never richer than the smoke limit', () {
      for (final rpm in [1000.0, 1800.0, 3000.0, 4500.0]) {
        for (final demand in _demandGrid.skip(1)) {
          final o = diesel.run(rpm: rpm, demand: demand, intakeAirC: _iat);

          expect(
            o.airGramsPerSecond / o.fuelGramsPerSecond,
            greaterThanOrEqualTo(17 - 1e-9),
          );
        }
      }
    });

    test(
      'runs very lean at idle, unlike a petrol engine, so MAF cannot give the fuel',
      () {
        final demand = diesel.demandForTorque(
          rpm: 800,
          torqueNm: 2,
          intakeAirC: _iat,
        );
        final o = diesel.run(rpm: 800, demand: demand, intakeAirC: _iat);
        final idleAfr = o.airGramsPerSecond / o.fuelGramsPerSecond;
        final loaded = diesel.run(rpm: 3000, demand: 1, intakeAirC: _iat);

        expect(idleAfr, greaterThan(60));
        expect(
          loaded.airGramsPerSecond / loaded.fuelGramsPerSecond,
          lessThan(25),
        );
        // A petrol engine's fuel is always air / 14.7. This one's is not.
        expect(o.fuelGramsPerSecond, lessThan(o.airGramsPerSecond / 14.5 / 3));
      },
    );

    test('makes boost at load and none at idle', () {
      expect(
        diesel.run(rpm: 800, demand: 0.02, intakeAirC: _iat).manifoldKpa,
        closeTo(101.3, 1),
      );
      expect(
        diesel.run(rpm: 3000, demand: 1, intakeAirC: _iat).manifoldKpa,
        greaterThan(160),
      );
    });

    test('torque follows the pedal', () {
      final half = diesel
          .run(rpm: 2500, demand: 0.5, intakeAirC: _iat)
          .torqueNm;

      expect(half, closeTo(120, 1));
    });

    test('brakes hard with the fuel cut', () {
      expect(
        diesel
            .run(rpm: 2500, demand: 0, intakeAirC: _iat, fuelCut: true)
            .torqueNm,
        lessThan(-15),
      );
    });

    test('load is the share of the available torque in use', () {
      expect(
        diesel.run(rpm: 2500, demand: 1, intakeAirC: _iat).loadFraction,
        closeTo(1, 0.01),
      );
      expect(
        diesel.run(rpm: 2500, demand: 0.5, intakeAirC: _iat).loadFraction,
        closeTo(0.5, 0.01),
      );
    });

    test('the pedal is the demand, and the throttle PID reads it directly', () {
      expect(diesel.demandForPedal(0.4), 0.4);
      expect(diesel.reportedThrottleFraction(0.4), 0.4);
    });
  });

  test('EngineModel.forSpec chooses the engine for the spec', () {
    expect(EngineModel.forSpec(spec), isA<PetrolEngine>());
    expect(
      EngineModel.forSpec(
        const DieselSpec(
          displacementLitres: 1.5,
          maximumTorqueCurve: [(1000, 100)],
        ),
      ),
      isA<DieselEngine>(),
    );
  });
}
