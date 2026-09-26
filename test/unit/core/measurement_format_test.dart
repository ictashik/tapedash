import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/measurement_format.dart';
import 'package:tapedash/core/number_format.dart';
import 'package:tapedash/core/units.dart';

void main() {
  group('formatSpeed', () {
    test('is a whole number of km/h', () {
      expect(formatSpeed(0), '0');
      expect(formatSpeed(87.4), '87');
      expect(formatSpeed(87.6), '88');
      expect(formatSpeed(107), '107');
    });

    test('converts to mph', () {
      expect(formatSpeed(100, unit: SpeedUnit.mph), '62');
      expect(formatSpeed(120, unit: SpeedUnit.mph), '75');
    });

    test('a missing speed is the missing-value text', () {
      expect(formatSpeed(null), noValue);
      expect(formatSpeed(double.nan), noValue);
    });
  });

  group('formatRpm', () {
    test('is a whole number with no grouping', () {
      expect(formatRpm(0), '0');
      expect(formatRpm(750.4), '750');
      expect(formatRpm(3450), '3450');
      expect(formatRpm(6500), '6500');
    });

    test('a missing value is the missing-value text', () {
      expect(formatRpm(null), noValue);
    });
  });

  group('formatDistance', () {
    test('has one decimal under 100', () {
      expect(formatDistance(0), '0.0');
      expect(formatDistance(12.34), '12.3');
      expect(formatDistance(12.36), '12.4');
      expect(formatDistance(99.9), '99.9');
    });

    test('is whole from 100', () {
      expect(formatDistance(100), '100');
      expect(formatDistance(100.4), '100');
      expect(formatDistance(1234.5), '1235');
    });

    test('a value that rounds up to 100 reads 100, not 100.0', () {
      expect(formatDistance(99.94), '99.9');
      expect(formatDistance(99.96), '100');
    });

    test('the choice follows the unit shown, not the kilometres', () {
      // 150 km is 93.2 mi: under 100 in miles.
      expect(formatDistance(150, unit: DistanceUnit.mi), '93.2');
      // 170 km is 105.6 mi.
      expect(formatDistance(170, unit: DistanceUnit.mi), '106');
    });

    test('a missing distance is the missing-value text', () {
      expect(formatDistance(null), noValue);
      expect(formatDistance(double.infinity), noValue);
    });
  });

  group('formatEconomy', () {
    test('has one decimal, never false precision', () {
      expect(formatEconomy(14.6237), '14.6');
      expect(formatEconomy(14), '14.0');
      expect(formatEconomy(0), '0.0');
    });

    test('converts to litres per 100 km', () {
      expect(formatEconomy(12.5, unit: EconomyUnit.litresPer100Km), '8.0');
      expect(formatEconomy(14.6, unit: EconomyUnit.litresPer100Km), '6.8');
    });

    test('converts to miles per gallon', () {
      expect(formatEconomy(12.754, unit: EconomyUnit.mpgUs), '30.0');
      expect(formatEconomy(10, unit: EconomyUnit.mpgImperial), '28.2');
    });

    test(
      'zero km/L is infinite litres per 100 km, which reads as no value',
      () {
        expect(formatEconomy(0, unit: EconomyUnit.litresPer100Km), noValue);
      },
    );

    test('a missing value is the missing-value text', () {
      expect(formatEconomy(null), noValue);
      expect(formatEconomy(null, unit: EconomyUnit.mpgUs), noValue);
    });
  });
}
