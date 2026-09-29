// The formulas of CLAUDE.md 8.4 against hand-computed values.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/fuel/fuel_math.dart';

void main() {
  group('litresPerHourFromAirFlow', () {
    test('5 g/s of air at 14.7:1 and 740 g/L is 1.655 L/h', () {
      // 5 * 3600 / (14.7 * 740) = 18000 / 10878 = 1.6547
      expect(
        FuelMath.litresPerHourFromAirFlow(
          gramsPerSecond: 5,
          airFuelRatio: 14.7,
          densityGramsPerLitre: 740,
        ),
        closeTo(1.6547, 1e-3),
      );
    });

    test('no air is no fuel', () {
      expect(
        FuelMath.litresPerHourFromAirFlow(
          gramsPerSecond: 0,
          airFuelRatio: 14.7,
          densityGramsPerLitre: 740,
        ),
        0,
      );
    });

    test('doubles with the air', () {
      double f(double g) => FuelMath.litresPerHourFromAirFlow(
        gramsPerSecond: g,
        airFuelRatio: 14.7,
        densityGramsPerLitre: 740,
      );
      expect(f(20), closeTo(2 * f(10), 1e-12));
    });
  });

  group('airFlowFromManifold (speed-density)', () {
    test('a 1.5 L engine at 2000 rpm, 60 kPa, 30 C, VE 0.85', () {
      // 1000 * 60 * 1.5 * (2000/120) * 0.85 / (287.05 * 303.15)
      // = 1000 * 60 * 1.5 * 16.6667 * 0.85 / 87018.5
      // = 1,275,000 / 87,018.5 = 14.652
      expect(
        FuelMath.airFlowFromManifold(
          manifoldKpa: 60,
          intakeCelsius: 30,
          rpm: 2000,
          displacementLitres: 1.5,
          volumetricEfficiency: 0.85,
        ),
        closeTo(14.652, 0.01),
      );
    });

    test('at idle: 30 kPa, 750 rpm, 1.5 L, 35 C', () {
      // 1000 * 30 * 1.5 * 6.25 * 0.85 / (287.05 * 308.15)
      // = 239,062.5 / 88,455.6 = 2.7027
      expect(
        FuelMath.airFlowFromManifold(
          manifoldKpa: 30,
          intakeCelsius: 35,
          rpm: 750,
          displacementLitres: 1.5,
          volumetricEfficiency: 0.85,
        ),
        closeTo(2.7027, 0.005),
      );
    });

    test('is proportional to pressure, revs, displacement and VE', () {
      double f({
        double p = 50,
        double n = 2000,
        double d = 1.5,
        double ve = 0.85,
      }) => FuelMath.airFlowFromManifold(
        manifoldKpa: p,
        intakeCelsius: 25,
        rpm: n,
        displacementLitres: d,
        volumetricEfficiency: ve,
      );
      expect(f(p: 100), closeTo(2 * f(), 1e-9));
      expect(f(n: 4000), closeTo(2 * f(), 1e-9));
      expect(f(d: 3), closeTo(2 * f(), 1e-9));
      expect(f(ve: 0.425), closeTo(0.5 * f(), 1e-9));
    });

    test('a hotter intake is thinner air', () {
      double f(double c) => FuelMath.airFlowFromManifold(
        manifoldKpa: 50,
        intakeCelsius: c,
        rpm: 2000,
        displacementLitres: 1.5,
        volumetricEfficiency: 0.85,
      );
      expect(f(60), lessThan(f(20)));
    });

    test('the whole chain: 1.5 L, 2000 rpm, 60 kPa, 30 C is ~4.85 L/h', () {
      final air = FuelMath.airFlowFromManifold(
        manifoldKpa: 60,
        intakeCelsius: 30,
        rpm: 2000,
        displacementLitres: 1.5,
        volumetricEfficiency: 0.85,
      );
      // 14.652 * 3600 / 10878 = 4.849
      expect(
        FuelMath.litresPerHourFromAirFlow(
          gramsPerSecond: air,
          airFuelRatio: 14.7,
          densityGramsPerLitre: 740,
        ),
        closeTo(4.849, 0.01),
      );
    });
  });
}
