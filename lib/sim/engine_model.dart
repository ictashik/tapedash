import 'dart:math' as math;

import 'engine_spec.dart';

/// Standard atmospheric pressure, kPa.
const double atmosphereKpa = 101.3;

const double _airGasConstant = 287.05; // J/(kg K)

/// What an engine is doing at one instant.
class EngineOutput {
  const EngineOutput({
    required this.torqueNm,
    required this.manifoldKpa,
    required this.airGramsPerSecond,
    required this.fuelGramsPerSecond,
    required this.loadFraction,
  });

  /// Net torque at the crank, after friction, pumping and accessories. It is
  /// negative when the engine is being turned by the car, which is engine
  /// braking.
  final double torqueNm;

  /// Manifold absolute pressure, kPa.
  final double manifoldKpa;

  /// Air through the intake. It keeps flowing when the fuel is cut off.
  final double airGramsPerSecond;

  /// Fuel actually injected. Zero in fuel cut-off.
  final double fuelGramsPerSecond;

  /// Calculated load, 0 to 1: how much of the most air (or torque) the engine
  /// could have at this speed it is using.
  final double loadFraction;
}

/// Turns what the driver asks for into air, fuel and torque.
///
/// A "demand" from 0 to 1 is how hard the engine is asked to work: the throttle
/// plate opening for a petrol engine, and the fuel quantity as a share of the
/// most torque available for a diesel. MAF, MAP and fuel rate all come from the
/// same run, so they are physically consistent (CLAUDE.md 7.1).
abstract class EngineModel {
  EngineModel();

  factory EngineModel.forSpec(EngineSpec spec) => switch (spec) {
    PetrolSpec() => PetrolEngine(spec),
    DieselSpec() => DieselEngine(spec),
  };

  EngineSpec get spec;

  /// The demand that the driver's pedal (0 to 1) asks for.
  double demandForPedal(double pedal);

  /// What the throttle position PID reads for a demand, as a fraction. It is
  /// the absolute position, so a closed petrol throttle reads above zero.
  double reportedThrottleFraction(double demand);

  /// Runs the engine at [rpm] with [demand], breathing air at [intakeAirC].
  /// With [fuelCut] no fuel is injected, and the engine only drags.
  /// [frictionScale] is 1 for a warm engine and more for a cold one, whose oil
  /// is thick.
  EngineOutput run({
    required double rpm,
    required double demand,
    required double intakeAirC,
    bool fuelCut = false,
    double frictionScale = 1,
  });

  /// The demand at which the engine delivers [torqueNm] at [rpm]. This is what
  /// an idle governor does: it finds the throttle that holds the revs. It
  /// returns 0 or 1 if the torque is out of reach.
  double demandForTorque({
    required double rpm,
    required double torqueNm,
    required double intakeAirC,
  }) {
    if (run(rpm: rpm, demand: 0, intakeAirC: intakeAirC).torqueNm >= torqueNm) {
      return 0;
    }
    if (run(rpm: rpm, demand: 1, intakeAirC: intakeAirC).torqueNm <= torqueNm) {
      return 1;
    }
    var low = 0.0;
    var high = 1.0;
    for (var i = 0; i < 26; i++) {
      final mid = (low + high) / 2;
      final torque = run(
        rpm: rpm,
        demand: mid,
        intakeAirC: intakeAirC,
      ).torqueNm;
      if (torque < torqueNm) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return (low + high) / 2;
  }

  /// Friction as a mean effective pressure, in kPa.
  double frictionKpa(double rpm) {
    final n = rpm / 1000;
    return spec.frictionBaseKpa +
        spec.frictionPerKrpmKpa * n +
        spec.frictionPerKrpm2Kpa * n * n;
  }
}

/// Converts a mean effective pressure (kPa) over a displacement (litres) into
/// torque (N m) for a four-stroke: work per cycle is torque * 4 * pi.
double _torqueFromPressure(double kpa, double displacementLitres) =>
    kpa * displacementLitres / (4 * math.pi);

double _pressureFromTorque(double torqueNm, double displacementLitres) =>
    torqueNm * 4 * math.pi / displacementLitres;

/// Mass of air drawn in per cycle, in grams, by the speed-density formula that
/// CLAUDE.md 8.4 gives: 1000 * MAP * displacement * VE / (R * T).
double _airPerCycleGrams({
  required double manifoldKpa,
  required double displacementLitres,
  required double volumetricEfficiency,
  required double intakeAirC,
}) =>
    1000 *
    manifoldKpa *
    displacementLitres *
    volumetricEfficiency /
    (_airGasConstant * (intakeAirC + 273.15));

class PetrolEngine extends EngineModel {
  PetrolEngine(this.spec);

  @override
  final PetrolSpec spec;

  @override
  double demandForPedal(double pedal) =>
      math.pow(pedal.clamp(0.0, 1.0), 1.3).toDouble();

  @override
  double reportedThrottleFraction(double demand) => 0.12 + 0.88 * demand;

  double _throttleArea(double demand) =>
      spec.throttleLeakArea +
      spec.throttleWideOpenArea *
          math.pow(demand.clamp(0.0, 1.0), spec.throttleExponent);

  /// The manifold pressure with the plate at [demand] and the engine at [rpm].
  double manifoldKpa(double demand, double rpm) {
    final area = _throttleArea(demand);
    final pressure =
        atmosphereKpa * area / (area + spec.intakeDemandPerRpm * rpm);
    return _softMax(pressure, spec.minimumManifoldKpa);
  }

  /// A maximum that rounds off the corner, so the pressure keeps rising with
  /// the throttle everywhere instead of going flat on the floor.
  static double _softMax(double a, double b) {
    const width = 3.0;
    return 0.5 * (a + b + math.sqrt((a - b) * (a - b) + width * width));
  }

  @override
  EngineOutput run({
    required double rpm,
    required double demand,
    required double intakeAirC,
    bool fuelCut = false,
    double frictionScale = 1,
  }) {
    final displacement = spec.displacementLitres;
    final map = manifoldKpa(demand, rpm);
    final airPerCycle = _airPerCycleGrams(
      manifoldKpa: map,
      displacementLitres: displacement,
      volumetricEfficiency: spec.volumetricEfficiency.at(rpm),
      intakeAirC: intakeAirC,
    );
    final cyclesPerSecond = rpm / 120;
    final fuelPerCycle = fuelCut
        ? 0.0
        : airPerCycle / spec.fuel.stoichiometricAirFuelRatio;

    // Part load is less efficient than full load.
    final shareOfAtmosphere = map / atmosphereKpa;
    final efficiency =
        spec.indicatedEfficiency *
        (spec.partLoadEfficiencyFloor +
            (1 - spec.partLoadEfficiencyFloor) *
                math.pow(shareOfAtmosphere, spec.partLoadEfficiencyExponent));
    final grossKpa =
        fuelPerCycle *
        spec.fuel.lowerHeatingValueJoulesPerGram *
        efficiency /
        displacement;
    final pumpingKpa = math.max(0.0, atmosphereKpa - map);
    final brakeKpa = grossKpa - pumpingKpa - frictionKpa(rpm) * frictionScale;
    final torque =
        _torqueFromPressure(brakeKpa, displacement) - spec.accessoryTorqueNm;

    final wideOpenArea = spec.throttleLeakArea + spec.throttleWideOpenArea;
    final wideOpenMap =
        atmosphereKpa *
        wideOpenArea /
        (wideOpenArea + spec.intakeDemandPerRpm * rpm);

    return EngineOutput(
      torqueNm: torque,
      manifoldKpa: map,
      airGramsPerSecond: airPerCycle * cyclesPerSecond,
      fuelGramsPerSecond: fuelPerCycle * cyclesPerSecond,
      loadFraction: (map / wideOpenMap).clamp(0.0, 1.0),
    );
  }
}

class DieselEngine extends EngineModel {
  DieselEngine(this.spec);

  @override
  final DieselSpec spec;

  @override
  double demandForPedal(double pedal) => pedal.clamp(0.0, 1.0);

  @override
  double reportedThrottleFraction(double demand) => demand;

  /// A turbo makes no boost until the engine is fast enough to spin it.
  static double _spool(double rpm) {
    final t = ((rpm - 1200) / 900).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  @override
  EngineOutput run({
    required double rpm,
    required double demand,
    required double intakeAirC,
    bool fuelCut = false,
    double frictionScale = 1,
  }) {
    final displacement = spec.displacementLitres;
    final d = demand.clamp(0.0, 1.0);
    final maximumTorque = interpolate(spec.maximumTorqueCurve, rpm);
    const pumpingKpa = 2.0;
    final friction = frictionKpa(rpm) * frictionScale;

    final boost = spec.maximumBoostKpa * _spool(rpm) * math.pow(d, 0.9);
    final map = atmosphereKpa + boost;
    final airPerCycle = _airPerCycleGrams(
      manifoldKpa: map,
      displacementLitres: displacement,
      volumetricEfficiency: spec.volumetricEfficiency.at(rpm),
      intakeAirC: intakeAirC,
    );

    // The pedal asks for torque. Work out the fuel that delivers it, then hold
    // it to the smoke limit.
    final requestedBrakeKpa = _pressureFromTorque(
      d * maximumTorque + spec.accessoryTorqueNm,
      displacement,
    );
    final requestedGrossKpa = requestedBrakeKpa + friction + pumpingKpa;
    final wantedFuel =
        requestedGrossKpa *
        displacement /
        (spec.indicatedEfficiency * spec.fuel.lowerHeatingValueJoulesPerGram);
    final fuelPerCycle = fuelCut
        ? 0.0
        : math.min(wantedFuel, airPerCycle / spec.smokeLimitAirFuelRatio);

    final grossKpa =
        fuelPerCycle *
        spec.fuel.lowerHeatingValueJoulesPerGram *
        spec.indicatedEfficiency /
        displacement;
    final torque =
        _torqueFromPressure(grossKpa - friction - pumpingKpa, displacement) -
        spec.accessoryTorqueNm;
    final cyclesPerSecond = rpm / 120;

    return EngineOutput(
      torqueNm: torque,
      manifoldKpa: map,
      airGramsPerSecond: airPerCycle * cyclesPerSecond,
      fuelGramsPerSecond: fuelPerCycle * cyclesPerSecond,
      loadFraction: maximumTorque <= 0
          ? 0
          : (math.max(0.0, torque) / maximumTorque).clamp(0.0, 1.0),
    );
  }
}
