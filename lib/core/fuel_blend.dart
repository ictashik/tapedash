/// How much ethanol there is in the petrol (CLAUDE.md 8.4).
///
/// The fuel-flow estimators turn a mass of air into a volume of fuel, and both
/// numbers they use depend on the blend: ethanol carries less carbon, so it
/// needs less air per kilo (9.0 to 1, against gasoline's 14.7 to 1), and it is
/// denser (789 g/L against 740). A car that holds a stoichiometric mixture,
/// which is what its oxygen sensor does at idle and in steady driving, burns
/// **more litres for the same air** on E20 than on plain petrol: about 7.5%.
/// The estimate has to know, or it reads that much low until a fill-up
/// calibrates it.
///
/// E0 (no ethanol) is exactly the 14.7 and 740 of CLAUDE.md 8.4.
enum PetrolBlend {
  e0('E0', 0),
  e10('E10', 10),
  e20('E20', 20);

  const PetrolBlend(this.label, this.ethanolPercent);

  final String label;

  /// Ethanol, in percent of the volume.
  final int ethanolPercent;

  /// Ethanol's share of the fuel's volume, 0 to 1.
  double get ethanolVolumeShare => ethanolPercent / 100;

  /// Ethanol's share of the fuel's mass, 0 to 1.
  double get ethanolMassShare {
    final e = ethanolVolumeShare * FuelBlendChemistry.ethanolDensity;
    final g = (1 - ethanolVolumeShare) * FuelBlendChemistry.gasolineDensity;
    return e / (e + g);
  }

  /// The stoichiometric air-fuel ratio of the blend: what a mixture of the two
  /// needs is the mass-weighted sum of what each needs.
  double get airFuelRatio {
    final w = ethanolMassShare;
    return (1 - w) * FuelBlendChemistry.gasolineAirFuelRatio +
        w * FuelBlendChemistry.ethanolAirFuelRatio;
  }

  /// The blend's density, in g/L.
  double get densityGramsPerLitre =>
      ethanolVolumeShare * FuelBlendChemistry.ethanolDensity +
      (1 - ethanolVolumeShare) * FuelBlendChemistry.gasolineDensity;

  /// The blend's lower heating value, in J/g (mass-weighted).
  double get lowerHeatingValueJoulesPerGram {
    final w = ethanolMassShare;
    return (1 - w) * FuelBlendChemistry.gasolineHeatingValue +
        w * FuelBlendChemistry.ethanolHeatingValue;
  }

  /// How many more litres the blend burns than E0 for the same mass of air, as a
  /// factor: 1 for E0, about 1.036 for E10 and 1.075 for E20.
  double get litresPerAirFactor =>
      (PetrolBlend.e0.airFuelRatio * PetrolBlend.e0.densityGramsPerLitre) /
      (airFuelRatio * densityGramsPerLitre);
}

/// The two fuels a blend is made of.
abstract final class FuelBlendChemistry {
  static const double gasolineAirFuelRatio = 14.7;
  static const double gasolineDensity = 740;
  static const double gasolineHeatingValue = 44000;

  static const double ethanolAirFuelRatio = 9.0;
  static const double ethanolDensity = 789;
  static const double ethanolHeatingValue = 26800;
}
