// Ethanol in the petrol (CLAUDE.md 8.4): the air-fuel ratio and the density of a
// blend, against hand-computed values.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fuel_blend.dart';
import 'package:tapedash/fuel/fuel_constants.dart';
import 'package:tapedash/sim/engine_spec.dart';

void main() {
  test('E0 is exactly the 14.7, 740 and 44 kJ/g of plain petrol', () {
    expect(PetrolBlend.e0.airFuelRatio, 14.7);
    expect(PetrolBlend.e0.densityGramsPerLitre, 740);
    expect(PetrolBlend.e0.lowerHeatingValueJoulesPerGram, 44000);
    expect(PetrolBlend.e0.litresPerAirFactor, 1);
    expect(FuelConstants.forBlend(PetrolBlend.e0), same(FuelConstants.petrol));
    expect(
      FuelProperties.petrolBlend(PetrolBlend.e0),
      same(FuelProperties.petrol),
    );
  });

  test('E20: 13.50 to 1 and 749.8 g/L', () {
    // Ethanol is 20% of the volume: 0.2 * 789 = 157.8 g and 0.8 * 740 = 592 g
    // in a litre, so 21.05% of the mass is ethanol.
    // AFR = 0.7895 * 14.7 + 0.2105 * 9.0 = 13.50.
    expect(PetrolBlend.e20.ethanolMassShare, closeTo(0.2105, 1e-3));
    expect(PetrolBlend.e20.airFuelRatio, closeTo(13.50, 0.01));
    expect(PetrolBlend.e20.densityGramsPerLitre, closeTo(749.8, 0.05));
  });

  test('E10: 14.10 to 1, the figure usually quoted, and 744.9 g/L', () {
    expect(PetrolBlend.e10.airFuelRatio, closeTo(14.10, 0.01));
    expect(PetrolBlend.e10.densityGramsPerLitre, closeTo(744.9, 0.05));
  });

  test('the same air is more litres of E20: 7.5%, and of E10: 3.6%', () {
    expect(PetrolBlend.e10.litresPerAirFactor, closeTo(1.036, 0.002));
    expect(PetrolBlend.e20.litresPerAirFactor, closeTo(1.075, 0.002));
  });

  test('ethanol has less energy: E20 about 8% less per gram', () {
    expect(
      PetrolBlend.e20.lowerHeatingValueJoulesPerGram / 44000,
      closeTo(0.918, 0.005),
    );
  });

  test(
    'the app\'s constants and the simulator\'s fuel are the same numbers',
    () {
      for (final b in PetrolBlend.values) {
        final c = FuelConstants.forBlend(b);
        final f = FuelProperties.petrolBlend(b);
        expect(c.airFuelRatio, f.stoichiometricAirFuelRatio);
        expect(c.densityGramsPerLitre, f.densityGramsPerLitre);
      }
    },
  );

  test(
    'a setup takes its constants from its blend, and a diesel ignores it',
    () {
      expect(
        const VehicleSetup(blend: PetrolBlend.e20).constants.airFuelRatio,
        closeTo(13.50, 0.01),
      );
      expect(const VehicleSetup().constants, same(FuelConstants.petrol));
      expect(
        const VehicleSetup(
          fuelType: FuelType.diesel,
          blend: PetrolBlend.e20,
        ).constants,
        same(FuelConstants.diesel),
      );
      expect(VehicleSetup.indiaDefault.blend, PetrolBlend.e20);
    },
  );
}
