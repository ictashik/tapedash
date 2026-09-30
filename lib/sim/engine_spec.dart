import '../core/fuel_blend.dart';

/// What a fuel is made of, for the parts of the simulator that turn air into
/// fuel and fuel into torque.
class FuelProperties {
  const FuelProperties({
    required this.name,
    required this.densityGramsPerLitre,
    required this.lowerHeatingValueJoulesPerGram,
    required this.stoichiometricAirFuelRatio,
  });

  final String name;
  final double densityGramsPerLitre;
  final double lowerHeatingValueJoulesPerGram;
  final double stoichiometricAirFuelRatio;

  /// Petrol: 14.7 to 1 and 740 g/L, the figures CLAUDE.md 8.4 uses.
  static const FuelProperties petrol = FuelProperties(
    name: 'petrol',
    densityGramsPerLitre: 740,
    lowerHeatingValueJoulesPerGram: 44000,
    stoichiometricAirFuelRatio: 14.7,
  );

  /// Petrol with ethanol in it, worked out from the two fuels
  /// ([PetrolBlend]). E0 is exactly [petrol].
  static FuelProperties petrolBlend(PetrolBlend blend) =>
      blend == PetrolBlend.e0
      ? petrol
      : FuelProperties(
          name: 'petrol ${blend.label}',
          densityGramsPerLitre: blend.densityGramsPerLitre,
          lowerHeatingValueJoulesPerGram: blend.lowerHeatingValueJoulesPerGram,
          stoichiometricAirFuelRatio: blend.airFuelRatio,
        );

  static const FuelProperties diesel = FuelProperties(
    name: 'diesel',
    densityGramsPerLitre: 832,
    lowerHeatingValueJoulesPerGram: 42600,
    stoichiometricAirFuelRatio: 14.5,
  );
}

/// Linear interpolation through (x, y) points, holding the end values outside
/// them. The points must be in increasing order of x.
double interpolate(List<(double, double)> points, double x) {
  if (x <= points.first.$1) return points.first.$2;
  for (var i = 1; i < points.length; i++) {
    final (x1, y1) = points[i];
    if (x <= x1) {
      final (x0, y0) = points[i - 1];
      return y0 + (y1 - y0) * (x - x0) / (x1 - x0);
    }
  }
  return points.last.$2;
}

/// How completely the cylinders fill at each engine speed, as a fraction of
/// what the displacement could hold at the manifold's pressure and temperature.
class VolumetricEfficiencyCurve {
  const VolumetricEfficiencyCurve(this.points);

  /// (rpm, fraction) points in increasing order of rpm.
  final List<(double, double)> points;

  double at(double rpm) => interpolate(points, rpm);

  /// Fills poorly at low revs and best in the upper middle, like a road engine
  /// with a tuned intake. The app's speed-density estimate assumes a flat 0.85
  /// (CLAUDE.md 8.4), so this is what its error comes from before calibration.
  static const VolumetricEfficiencyCurve typicalPetrol =
      VolumetricEfficiencyCurve([
        (500, 0.66),
        (1000, 0.75),
        (1500, 0.80),
        (2000, 0.84),
        (3000, 0.90),
        (4000, 0.95),
        (5000, 0.98),
        (6000, 0.98),
        (6500, 0.96),
        (7500, 0.86),
      ]);

  static const VolumetricEfficiencyCurve typicalDiesel =
      VolumetricEfficiencyCurve([
        (500, 0.80),
        (1500, 0.90),
        (3000, 0.95),
        (4500, 0.90),
        (5500, 0.84),
      ]);
}

/// The parts of an engine that decide how air, fuel and torque relate.
sealed class EngineSpec {
  const EngineSpec({
    required this.displacementLitres,
    required this.fuel,
    required this.volumetricEfficiency,
    required this.indicatedEfficiency,
    required this.frictionBaseKpa,
    required this.frictionPerKrpmKpa,
    required this.frictionPerKrpm2Kpa,
    required this.accessoryTorqueNm,
  });

  final double displacementLitres;
  final FuelProperties fuel;
  final VolumetricEfficiencyCurve volumetricEfficiency;

  /// The share of fuel energy that becomes gross work on the pistons, at full
  /// load. It is lower at part load (see PetrolEngine).
  final double indicatedEfficiency;

  /// Friction as a pressure, in kPa of mean effective pressure:
  /// base + linear * n + quadratic * n^2, with n in thousands of rpm.
  final double frictionBaseKpa;
  final double frictionPerKrpmKpa;
  final double frictionPerKrpm2Kpa;

  /// What the alternator, water pump and the like take, at the crank.
  final double accessoryTorqueNm;
}

/// A throttled spark-ignition engine at stoichiometric mixture. Air comes
/// first: the throttle sets the manifold pressure, that sets the air, and the
/// fuel follows at 14.7 to 1.
class PetrolSpec extends EngineSpec {
  const PetrolSpec({
    required super.displacementLitres,
    super.volumetricEfficiency = VolumetricEfficiencyCurve.typicalPetrol,
    super.indicatedEfficiency = 0.42,
    super.frictionBaseKpa = 80,
    super.frictionPerKrpmKpa = 6,
    super.frictionPerKrpm2Kpa = 1.9,
    super.accessoryTorqueNm = 3,
    this.throttleLeakArea = 0.32,
    this.throttleWideOpenArea = 67,
    this.throttleExponent = 2.0,
    this.intakeDemandPerRpm = 0.001,
    this.partLoadEfficiencyFloor = 0.32,
    this.partLoadEfficiencyExponent = 0.6,
    this.minimumManifoldKpa = 17,
    super.fuel = FuelProperties.petrol,
  });

  /// The same engine on another fuel.
  PetrolSpec withFuel(FuelProperties fuel) => PetrolSpec(
    displacementLitres: displacementLitres,
    volumetricEfficiency: volumetricEfficiency,
    indicatedEfficiency: indicatedEfficiency,
    frictionBaseKpa: frictionBaseKpa,
    frictionPerKrpmKpa: frictionPerKrpmKpa,
    frictionPerKrpm2Kpa: frictionPerKrpm2Kpa,
    accessoryTorqueNm: accessoryTorqueNm,
    throttleLeakArea: throttleLeakArea,
    throttleWideOpenArea: throttleWideOpenArea,
    throttleExponent: throttleExponent,
    intakeDemandPerRpm: intakeDemandPerRpm,
    partLoadEfficiencyFloor: partLoadEfficiencyFloor,
    partLoadEfficiencyExponent: partLoadEfficiencyExponent,
    minimumManifoldKpa: minimumManifoldKpa,
    fuel: fuel,
  );

  /// The throttle is modelled as an orifice: with area A and an engine that
  /// demands b * rpm of air, the manifold sits at atmosphere * A / (A + b*rpm).
  /// A closed plate still passes [throttleLeakArea], and a fully open one adds
  /// [throttleWideOpenArea] on top. The units are arbitrary and only the ratio
  /// to [intakeDemandPerRpm] matters.
  final double throttleLeakArea;
  final double throttleWideOpenArea;

  /// How the area grows with the plate opening (area ~ opening^exponent).
  final double throttleExponent;
  final double intakeDemandPerRpm;

  /// Part load costs efficiency. The share of full-load indicated efficiency
  /// is floor + (1 - floor) * (pressure / atmosphere)^exponent.
  final double partLoadEfficiencyFloor;
  final double partLoadEfficiencyExponent;

  /// A closed throttle at speed still leaves some pressure in the manifold,
  /// which the model approaches smoothly.
  final double minimumManifoldKpa;
}

/// A turbocharged compression-ignition engine. Fuel comes first: the pedal asks
/// for torque, the injectors deliver the fuel for it, and the air is whatever
/// the turbo provides, so the mixture varies a great deal with load.
class DieselSpec extends EngineSpec {
  const DieselSpec({
    required super.displacementLitres,
    required this.maximumTorqueCurve,
    super.volumetricEfficiency = VolumetricEfficiencyCurve.typicalDiesel,
    super.indicatedEfficiency = 0.46,
    super.frictionBaseKpa = 100,
    super.frictionPerKrpmKpa = 14,
    super.frictionPerKrpm2Kpa = 3.5,
    super.accessoryTorqueNm = 4,
    this.maximumBoostKpa = 90,
    this.smokeLimitAirFuelRatio = 17,
  }) : super(fuel: FuelProperties.diesel);

  /// (rpm, N m): the most torque the engine can deliver at each speed.
  final List<(double, double)> maximumTorqueCurve;

  /// Boost above atmosphere at full load, once the turbo has spooled up.
  final double maximumBoostKpa;

  /// Fuel is cut back so the mixture is never richer than this.
  final double smokeLimitAirFuelRatio;
}
