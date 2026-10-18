import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/insights/insight_constants.dart';
import 'package:tapedash/insights/powerflow.dart';
import 'package:tapedash/insights/wheel_power.dart';
import 'package:tapedash/money/spend_bucket.dart';
import 'package:tapedash/trips/trip.dart';

import '../../support/insight_drive.dart';

void main() {
  test('a steady 60 km/h asks only what the tyres and the air take', () {
    final moments = WheelPower.moments(madeDrive(60, kmh: (_) => 60));
    final m = moments.last;
    // 0.012 * 1250 kg * 9.81 * 16.67 m/s = 2.45 kW; 0.5 * 1.18 * 0.65 * 16.67^3
    // = 1.78 kW.
    expect(m.rollingKw, closeTo(2.45, 0.02));
    expect(m.airKw, closeTo(1.78, 0.02));
    expect(m.tractionKw, closeTo(4.23, 0.05));
    expect(m.brakingKw, 0);
  });

  test('one wrong speed reading is not a pull', () {
    // A real drive shows 46 then 95 km/h on a 40 km/h road, for one reading.
    final moments = WheelPower.moments(
      madeDrive(60, kmh: (t) => t == 30 ? 95 : 50),
    );
    final top = moments
        .map((m) => m.tractionKw)
        .reduce((a, b) => a > b ? a : b);
    // 50 km/h steady asks 3.1 kW; the spike must not ask a hundred.
    expect(top, lessThan(12));
  });

  test('a hard-working engine is not what noise in the speed looks like', () {
    // 50 km/h with a whole km/h of jitter either way: the work is the steady
    // 3.1 kW, and the jitter must not add much of its own by being rectified.
    final jitter = madeDrive(300, kmh: (t) => 50.0 + (t.isEven ? 1 : -1));
    final steady = madeDrive(300, kmh: (_) => 50);
    double mean(List<WheelMoment> m) =>
        m.fold<double>(0, (a, x) => a + x.tractionKw) / m.length;
    final noisy = mean(WheelPower.moments(jitter));
    final clean = mean(WheelPower.moments(steady));
    expect(noisy, lessThan(clean * 1.25));
  });

  test('a moment that asks more than a car can give is dropped', () {
    final moments = WheelPower.moments(
      madeDrive(20, kmh: (t) => t < 10 ? 20.0 : 20.0 + (t - 10) * 40),
    );
    for (final m in moments) {
      expect(m.tractionKw, lessThan(200));
    }
    expect(moments.length, lessThan(20));
  });

  test('speeding up asks more, and slowing down hands it to the brakes', () {
    final up = WheelPower.moments(madeDrive(10, kmh: (t) => 20.0 + 3 * t));
    // 3 km/h a second is 0.83 m/s2: 1250 * 0.83 * v.
    expect(up.last.tractionKw, greaterThan(up.last.rollingKw + up.last.airKw));
    final down = WheelPower.moments(madeDrive(10, kmh: (t) => 80.0 - 6 * t));
    expect(down.last.tractionKw, 0);
    expect(down.last.brakingKw, greaterThan(5));
  });

  test('a gap in the samples is not driving', () {
    final s = madeDrive(20, kmh: (_) => 50);
    final gapped = [
      ...s.take(10),
      ...s
          .skip(10)
          .map(
            (x) => TripSample(
              seconds: x.seconds + 60,
              speedKmh: x.speedKmh,
              rpm: x.rpm,
              throttle: x.throttle,
              litresPerHour: x.litresPerHour,
            ),
          ),
    ];
    final moments = WheelPower.moments(gapped);
    expect(moments.where((m) => m.dt > WheelPower.maxGap), isEmpty);
    expect(moments.length, lessThan(gapped.length - 1));
  });

  group('Powerflow', () {
    Trip trip({double litres = 1.5, Map<SpendBucket, double>? idle}) => Trip(
      startedAt: DateTime(2026, 10, 1),
      litres: litres,
      cost: 175,
      bucketLitres: idle ?? {SpendBucket.idling: 0.1, SpendBucket.normal: 1.4},
    );

    // Stop and go: 20 s up to 50 km/h, 20 s down, a stand.
    final stopGo = madeDrive(
      600,
      kmh: (t) {
        final c = t % 60;
        if (c < 20) return c * 2.5;
        if (c < 40) return 50 - (c - 20) * 2.5;
        return 0;
      },
    );

    test('its shares add up at each split', () {
      final f = Powerflow.of(trip(), stopGo)!;
      expect(f.idleShare + f.wheelShare + f.heatShare, closeTo(1, 1e-9));
      expect(f.tyreShare + f.airShare + f.brakeShare, closeTo(1, 1e-9));
      expect(f.brakeShare, greaterThan(0.1));
      expect(f.wheelShare, lessThanOrEqualTo(Powerflow.ceiling));
      expect(f.idleShare, closeTo(0.1 / 1.5, 1e-6));
    });

    test('the fuel is the litres in kWh, E20 being a little leaner', () {
      final f = Powerflow.of(trip(), stopGo)!;
      expect(
        f.fuelKwh,
        closeTo(1.5 * const InsightConstants().kwhPerLitre, 1e-9),
      );
      expect(const InsightConstants().kwhPerLitre, closeTo(8.28, 0.02));
    });

    test('rupees follow the share', () {
      final f = Powerflow.of(trip(), stopGo)!;
      expect(f.rupees(f.brakeOfFuel), closeTo(175 * f.brakeOfFuel, 1e-9));
    });

    test('a trip with no fuel or no samples has no flow', () {
      expect(Powerflow.of(trip(litres: 0), stopGo), isNull);
      expect(Powerflow.of(trip(), stopGo.take(10).toList()), isNull);
    });
  });
}
