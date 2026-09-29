/// The fuel a car burns.
enum FuelType {
  petrol('Petrol'),
  diesel('Diesel');

  const FuelType(this.label);

  final String label;
}

/// The constants the fuel-flow estimators use (CLAUDE.md 8.4), in one place so
/// that each can be set per vehicle.
class FuelConstants {
  const FuelConstants({
    required this.airFuelRatio,
    required this.densityGramsPerLitre,
    this.volumetricEfficiency = 0.85,
    this.volumetricEfficiencyShape = typicalPetrolShape,
    this.specificGasConstant = 287.05,
    this.cutOffMinRpm = 1500,
    this.cutOffMinSpeedKmh = 10,
    this.cutOffMaxThrottlePercent = 2,
  });

  /// Petrol: 14.7 to 1 by mass, at 740 g/L.
  static const FuelConstants petrol = FuelConstants(
    airFuelRatio: 14.7,
    densityGramsPerLitre: 740,
  );

  /// Diesel burns lean at part load and its ratio varies with load, so this
  /// mean is a rough figure. A diesel's estimate from air flow is marked low
  /// confidence until a fill-up has calibrated it (CLAUDE.md 8.4).
  static const FuelConstants diesel = FuelConstants(
    airFuelRatio: 24,
    densityGramsPerLitre: 832,
    volumetricEfficiency: 0.90,
    volumetricEfficiencyShape: [],
  );

  static FuelConstants forType(FuelType type) => switch (type) {
    FuelType.petrol => petrol,
    FuelType.diesel => diesel,
  };

  /// Air mass over fuel mass.
  final double airFuelRatio;

  final double densityGramsPerLitre;

  /// What the speed-density method assumes an engine breathes, as a share of
  /// its displacement. Calibration adjusts the fuel it gives, which is the same
  /// thing as adjusting this.
  final double volumetricEfficiency;

  /// How an engine's breathing varies with its speed, as (rpm, multiple of
  /// [volumetricEfficiency]) points in increasing order of rpm. A road engine
  /// fills its cylinders poorly at idle and best in the upper middle of its
  /// range; a flat 0.85 over-counts the fuel at idle by a fifth, and idling is
  /// where a city car spends a good part of its money. Calibration corrects the
  /// level and not the shape. Pass an empty list for a flat VE.
  final List<(double, double)> volumetricEfficiencyShape;

  /// The VE at [rpm]: the level times the shape.
  double volumetricEfficiencyAt(double rpm) {
    final pts = volumetricEfficiencyShape;
    if (pts.isEmpty) return volumetricEfficiency;
    if (rpm <= pts.first.$1) return volumetricEfficiency * pts.first.$2;
    for (var i = 1; i < pts.length; i++) {
      final (x1, y1) = pts[i];
      if (rpm <= x1) {
        final (x0, y0) = pts[i - 1];
        return volumetricEfficiency * (y0 + (y1 - y0) * (rpm - x0) / (x1 - x0));
      }
    }
    return volumetricEfficiency * pts.last.$2;
  }

  /// A generic naturally-aspirated petrol engine's breathing, relative to its
  /// value at 2000 rpm.
  static const List<(double, double)> typicalPetrolShape = [
    (500, 0.80),
    (1000, 0.88),
    (1500, 0.94),
    (2000, 1.00),
    (3000, 1.06),
    (4000, 1.10),
    (5000, 1.12),
    (6000, 1.10),
    (7000, 1.02),
  ];

  /// Dry air, in J/(kg K).
  final double specificGasConstant;

  /// Fuel is cut when the throttle is closed and the engine is being driven by
  /// the wheels: above this speed and this many rpm, with the throttle at or
  /// below [cutOffMaxThrottlePercent]. The air-based estimates then give no
  /// fuel, since air still flows and no fuel goes with it.
  final double cutOffMinRpm;
  final double cutOffMinSpeedKmh;
  final double cutOffMaxThrottlePercent;
}

/// What the app knows about the car it is in (CLAUDE.md 8.4): set in the Garage
/// or by onboarding.
class VehicleSetup {
  const VehicleSetup({
    this.fuelType = FuelType.petrol,
    this.displacementLitres = 1.5,
    this.tankLitres = 40,
    FuelConstants? constants,
  }) : _constants = constants; // ignore: prefer_initializing_formals

  final FuelType fuelType;

  /// The engine's displacement, in litres, for the speed-density method.
  final double displacementLitres;

  /// The tank's capacity, in litres, to turn the fuel level into litres.
  final double tankLitres;

  final FuelConstants? _constants;

  FuelConstants get constants => _constants ?? FuelConstants.forType(fuelType);

  bool get isDiesel => fuelType == FuelType.diesel;

  VehicleSetup copyWith({
    FuelType? fuelType,
    double? displacementLitres,
    double? tankLitres,
    FuelConstants? constants,
  }) => VehicleSetup(
    fuelType: fuelType ?? this.fuelType,
    displacementLitres: displacementLitres ?? this.displacementLitres,
    tankLitres: tankLitres ?? this.tankLitres,
    constants: constants ?? _constants,
  );
}
