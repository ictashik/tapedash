import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/units.dart';

/// A spread of values, from tiny to large, for round-trip checks.
const _samples = [0.0, 0.1, 1.0, 5.0, 14.6, 25.0, 60.0, 100.0, 1234.5];

void main() {
  group('constants', () {
    test('are the exact definitions', () {
      expect(kmPerMile, 1.609344);
      expect(litresPerUsGallon, 3.785411784);
      expect(litresPerImperialGallon, 4.54609);
    });
  });

  group('km/h and m/s', () {
    test('36 km/h is 10 m/s', () {
      expect(kmhToMs(36), closeTo(10, 1e-12));
      expect(msToKmh(10), closeTo(36, 1e-12));
    });

    test('round trip', () {
      for (final v in _samples) {
        expect(msToKmh(kmhToMs(v)), closeTo(v, 1e-9));
      }
    });

    test('zero is zero', () {
      expect(kmhToMs(0), 0);
      expect(msToKmh(0), 0);
    });
  });

  group('SpeedUnit', () {
    test('km/h is the identity', () {
      expect(SpeedUnit.kmh.fromKmh(87.5), 87.5);
      expect(SpeedUnit.kmh.toKmh(87.5), 87.5);
    });

    test('100 km/h is 62.137 mph', () {
      expect(SpeedUnit.mph.fromKmh(100), closeTo(62.1371192, 1e-6));
    });

    test('60 mph is 96.56064 km/h', () {
      expect(SpeedUnit.mph.toKmh(60), closeTo(96.56064, 1e-9));
    });

    test('labels are uppercase for instruments', () {
      expect(SpeedUnit.kmh.symbol, 'km/h');
      expect(SpeedUnit.kmh.label, 'KM/H');
      expect(SpeedUnit.mph.label, 'MPH');
    });

    test('round trip', () {
      for (final unit in SpeedUnit.values) {
        for (final v in _samples) {
          expect(
            unit.toKmh(unit.fromKmh(v)),
            closeTo(v, 1e-9),
            reason: '$unit',
          );
        }
      }
    });
  });

  group('DistanceUnit', () {
    test('10 km is 6.2137 mi', () {
      expect(DistanceUnit.mi.fromKm(10), closeTo(6.2137119, 1e-6));
    });

    test('one mile is 1.609344 km', () {
      expect(DistanceUnit.mi.toKm(1), closeTo(1.609344, 1e-12));
    });

    test('labels', () {
      expect(DistanceUnit.km.label, 'KM');
      expect(DistanceUnit.mi.label, 'MI');
    });

    test('round trip', () {
      for (final unit in DistanceUnit.values) {
        for (final v in _samples) {
          expect(unit.toKm(unit.fromKm(v)), closeTo(v, 1e-9), reason: '$unit');
        }
      }
    });
  });

  group('VolumeUnit', () {
    test('a US gallon is 3.785411784 litres', () {
      expect(VolumeUnit.usGallon.toLitres(1), closeTo(3.785411784, 1e-12));
      expect(VolumeUnit.usGallon.fromLitres(3.785411784), closeTo(1, 1e-12));
    });

    test('an imperial gallon is 4.54609 litres', () {
      expect(VolumeUnit.imperialGallon.toLitres(1), closeTo(4.54609, 1e-12));
    });

    test('10 litres is 2.6417 US gallons and 2.1997 imperial gallons', () {
      expect(VolumeUnit.usGallon.fromLitres(10), closeTo(2.6417205, 1e-6));
      expect(
        VolumeUnit.imperialGallon.fromLitres(10),
        closeTo(2.1996925, 1e-6),
      );
    });

    test('litres are the identity', () {
      expect(VolumeUnit.litre.fromLitres(32.45), 32.45);
    });

    test('round trip', () {
      for (final unit in VolumeUnit.values) {
        for (final v in _samples) {
          expect(
            unit.toLitres(unit.fromLitres(v)),
            closeTo(v, 1e-9),
            reason: '$unit',
          );
        }
      }
    });
  });

  group('TemperatureUnit', () {
    test('known points', () {
      expect(TemperatureUnit.fahrenheit.fromCelsius(0), 32);
      expect(TemperatureUnit.fahrenheit.fromCelsius(100), 212);
      expect(TemperatureUnit.fahrenheit.fromCelsius(90), 194);
      expect(TemperatureUnit.fahrenheit.fromCelsius(-40), -40);
      expect(TemperatureUnit.fahrenheit.toCelsius(212), 100);
      expect(TemperatureUnit.fahrenheit.toCelsius(-40), -40);
    });

    test('Celsius is the identity', () {
      expect(TemperatureUnit.celsius.fromCelsius(88.5), 88.5);
      expect(TemperatureUnit.celsius.toCelsius(-12), -12);
    });

    test('symbols', () {
      expect(TemperatureUnit.celsius.label, '°C');
      expect(TemperatureUnit.fahrenheit.label, '°F');
    });

    test('round trip, below and above zero', () {
      for (final unit in TemperatureUnit.values) {
        for (final v in [..._samples, -40.0, -273.15]) {
          expect(unit.toCelsius(unit.fromCelsius(v)), closeTo(v, 1e-9));
        }
      }
    });
  });

  group('EconomyUnit', () {
    test('km/L is the identity', () {
      expect(EconomyUnit.kmPerLitre.fromKmPerLitre(14.6), 14.6);
    });

    test('litres per 100 km is the reciprocal', () {
      expect(EconomyUnit.litresPer100Km.fromKmPerLitre(10), closeTo(10, 1e-12));
      expect(
        EconomyUnit.litresPer100Km.fromKmPerLitre(12.5),
        closeTo(8, 1e-12),
      );
      expect(EconomyUnit.litresPer100Km.fromKmPerLitre(20), closeTo(5, 1e-12));
      expect(EconomyUnit.litresPer100Km.toKmPerLitre(8), closeTo(12.5, 1e-12));
    });

    test('a higher km/L is a lower L/100 km', () {
      final thirsty = EconomyUnit.litresPer100Km.fromKmPerLitre(8);
      final frugal = EconomyUnit.litresPer100Km.fromKmPerLitre(18);

      expect(frugal, lessThan(thirsty));
    });

    test(
      '1 mpg (US) is 0.425143707 km/L, and 1 mpg (imperial) 0.354006189',
      () {
        expect(EconomyUnit.mpgUs.toKmPerLitre(1), closeTo(0.425143707, 1e-8));
        expect(
          EconomyUnit.mpgImperial.toKmPerLitre(1),
          closeTo(0.354006189, 1e-8),
        );
      },
    );

    test('30 mpg (US) is 7.84 L/100 km', () {
      final kmPerLitre = EconomyUnit.mpgUs.toKmPerLitre(30);

      expect(
        EconomyUnit.litresPer100Km.fromKmPerLitre(kmPerLitre),
        closeTo(7.8405, 1e-3),
      );
    });

    test('zero economy is infinite litres per 100 km, and back', () {
      expect(EconomyUnit.litresPer100Km.fromKmPerLitre(0), double.infinity);
      expect(EconomyUnit.litresPer100Km.toKmPerLitre(0), double.infinity);
    });

    test('a negative value is treated like zero, not turned into a number', () {
      expect(EconomyUnit.litresPer100Km.fromKmPerLitre(-3), double.infinity);
    });

    test('labels', () {
      expect(EconomyUnit.kmPerLitre.label, 'KM/L');
      expect(EconomyUnit.litresPer100Km.label, 'L/100 KM');
      expect(EconomyUnit.mpgUs.label, 'MPG');
    });

    test('round trip', () {
      for (final unit in EconomyUnit.values) {
        for (final v in _samples.where((v) => v > 0)) {
          expect(
            unit.toKmPerLitre(unit.fromKmPerLitre(v)),
            closeTo(v, 1e-9),
            reason: '$unit',
          );
        }
      }
    });
  });
}
