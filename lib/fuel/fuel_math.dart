/// The formulas of CLAUDE.md 8.4, on plain numbers, so that each can be checked
/// against a hand-computed value.
abstract final class FuelMath {
  /// Air mass flow from the manifold, by speed-density (CLAUDE.md 8.4):
  /// `1000 * MAP * displacement * (rpm / 120) * VE / (287.05 * IAT)`, in g/s,
  /// with MAP in kPa, displacement in litres and the intake air in kelvin.
  ///
  /// A four-stroke engine takes in its displacement once every two turns, which
  /// is where the 120 comes from.
  static double airFlowFromManifold({
    required double manifoldKpa,
    required double intakeCelsius,
    required double rpm,
    required double displacementLitres,
    required double volumetricEfficiency,
    double specificGasConstant = 287.05,
  }) =>
      1000 *
      manifoldKpa *
      displacementLitres *
      (rpm / 120) *
      volumetricEfficiency /
      (specificGasConstant * (intakeCelsius + 273.15));

  /// Fuel flow, in litres an hour, from an air mass flow in g/s:
  /// `MAF * 3600 / (AFR * density)`.
  static double litresPerHourFromAirFlow({
    required double gramsPerSecond,
    required double airFuelRatio,
    required double densityGramsPerLitre,
  }) => gramsPerSecond * 3600 / (airFuelRatio * densityGramsPerLitre);
}
