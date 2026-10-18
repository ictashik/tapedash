import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/insights/gearbox.dart';
import 'package:tapedash/insights/power_curve.dart';
import 'package:tapedash/trips/trip.dart';

import '../../support/insight_drive.dart';

/// Accelerating through gears: in gear g the revs are ratio[g] * speed.
List<TripSample> geared(List<double> ratios, {int rounds = 6}) {
  final out = <TripSample>[];
  var t = 0.0;
  for (var r = 0; r < rounds; r++) {
    for (final ratio in ratios) {
      for (var v = 15.0; v < 6000 / ratio && v < 100; v += 1.5) {
        out.add(
          TripSample(
            seconds: t++,
            speedKmh: v,
            rpm: ratio * v * (1 + 0.01 * math.sin(t)),
            throttle: 40,
            litresPerHour: 5,
          ),
        );
      }
    }
  }
  return out;
}

void main() {
  group('Gearbox', () {
    test('finds the five gears of a manual from the ratios the revs keep', () {
      final g = Gearbox.from([
        geared([128, 76, 52, 39, 32]),
      ]);
      expect(g.isFan, isFalse);
      expect(g.gears, 5);
      expect(g.ratios.first, closeTo(32, 3));
      expect(g.ratios.last, closeTo(128, 4));
    });

    test('numbers the gears from the shortest, and knows a moment in one', () {
      final g = Gearbox.from([
        geared([128, 76, 52, 39, 32]),
      ]);
      expect(g.gearFor(30, 128.0 * 30), 1);
      expect(g.gearFor(60, 39.0 * 60), 4);
      expect(g.gearFor(80, 32.0 * 80), 5);
      expect(g.gearFor(5, 1500), isNull, reason: 'too slow to say');
      expect(g.gearFor(60, 90.0 * 60), isNull, reason: 'between gears');
    });

    test('how each gear is used: its ratio, its share and the speeds', () {
      final g = Gearbox.from([
        geared([128, 76, 52, 39, 32]),
      ]);
      final use = g.usage();
      expect(use.length, 5);
      expect(use.first.ratio, greaterThan(use.last.ratio));
      expect([for (final u in use) u.gear], [1, 2, 3, 4, 5]);
      expect(use.fold<double>(0, (a, u) => a + u.share), closeTo(1, 0.05));
      for (final u in use) {
        expect(u.fromKmh, lessThan(u.toKmh));
      }
    });

    test('a CVT is a fan and finds no gears', () {
      final rng = math.Random(3);
      final cvt = [
        for (var i = 0; i < 1500; i++)
          TripSample(
            seconds: i.toDouble(),
            speedKmh: 20 + rng.nextDouble() * 70,
            rpm: 1100 + rng.nextDouble() * 3500,
            throttle: 30,
            litresPerHour: 4,
          ),
      ];
      final g = Gearbox.from([cvt]);
      expect(g.isFan, isTrue);
      expect(g.gears, 0);
      expect(g.gearFor(50, 2500), isNull);
    });

    test('with nothing driven there is nothing', () {
      expect(Gearbox.from(const []).isEmpty, isTrue);
    });
  });

  group('PowerCurve', () {
    // Pulls: a hard acceleration from 20 to 80 km/h, repeated.
    List<TripSample> pulls() => madeDrive(
      400,
      kmh: (t) => 20.0 + (t % 20) * 3,
      rpm: (t, v) => 1200 + v * 40,
      throttle: (t) => 60,
    );

    test('the edge rises with the revs the car was taken to', () {
      final c = PowerCurve.from([pulls()]);
      expect(c.isEmpty, isFalse);
      expect(c.edge, isNotEmpty);
      expect(c.highest!.kw, greaterThan(10));
      expect(c.coveredRpm, greaterThan(3000));
      for (var i = 1; i < c.edge.length; i++) {
        expect(c.edge[i].$1, greaterThan(c.edge[i - 1].$1));
      }
    });

    test('revs never reached have no edge', () {
      final c = PowerCurve.from([pulls()]);
      expect(
        c.edge.last.$1,
        lessThanOrEqualTo(c.coveredRpm + PowerCurve.binRpm),
      );
    });

    test('a bin with few dots makes no point', () {
      final few = madeDrive(
        3,
        kmh: (t) => 30.0 + t * 8,
        rpm: (t, v) => 2000,
        throttle: (t) => 60,
      );
      expect(PowerCurve.from([few]).edge, isEmpty);
    });

    test('driving that never pulled has no dots', () {
      expect(PowerCurve.from([madeDrive(120, kmh: (_) => 0)]).isEmpty, isTrue);
    });
  });
}
