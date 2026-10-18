// The insight charts' own arithmetic (DESIGN.md 6.18): what a painter keeps of a
// long trace, so that a short dip is never averaged away.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/insights/gearbox.dart';
import 'package:tapedash/insights/power_curve.dart';
import 'package:tapedash/insights/powerflow.dart';
import 'package:tapedash/trips/trip.dart';
import 'package:tapedash/ui/design/components/insights/gear_chart.dart';
import 'package:tapedash/ui/design/components/insights/power_curve_chart.dart';
import 'package:tapedash/ui/design/components/insights/powerflow_chart.dart';
import 'package:tapedash/ui/design/components/insights/voltage_chart.dart';

void main() {
  group('VoltageChartPainter.decimate', () {
    test('keeps a two-second dip in a twenty-minute trace', () {
      final points = [
        for (var t = 0; t < 1200; t++)
          (t.toDouble(), t == 600 || t == 601 ? 12.4 : 14.0),
      ];
      final out = VoltageChartPainter.decimate(points, 300);
      expect(out.length, lessThanOrEqualTo(600));
      expect(out.map((p) => p.$2).reduce((a, b) => a < b ? a : b), 12.4);
    });

    test('keeps the points in time order', () {
      final points = [
        for (var t = 0; t < 900; t++) (t.toDouble(), 13.5 + (t % 7) * 0.1),
      ];
      final out = VoltageChartPainter.decimate(points, 100);
      for (var i = 1; i < out.length; i++) {
        expect(out[i].$1, greaterThanOrEqualTo(out[i - 1].$1));
      }
    });

    test('a short trace is drawn as it is', () {
      final points = [for (var t = 0; t < 50; t++) (t.toDouble(), 14.0)];
      expect(VoltageChartPainter.decimate(points, 300), points);
    });
  });

  group('PowerflowLayout', () {
    const flow = Powerflow(
      fuelKwh: 12,
      idleShare: 0.08,
      wheelShare: 0.22,
      heatShare: 0.70,
      tyreShare: 0.4,
      airShare: 0.35,
      brakeShare: 0.25,
    );

    for (final size in const [Size(380, 262), Size(420, 262), Size(300, 240)]) {
      test('every node is inside the panel and none touch, at $size', () {
        final l = PowerflowLayout(flow, size);
        final nodes = [
          l.fuel,
          l.wheels,
          l.idle,
          l.heat,
          l.tyres,
          l.air,
          l.brakes,
        ];
        for (final n in nodes) {
          expect(n.left, greaterThanOrEqualTo(0));
          expect(n.bottom, lessThanOrEqualTo(size.height));
          expect(
            n.right,
            lessThanOrEqualTo(size.width - 80),
            reason: 'room for the labels',
          );
        }
        for (final (a, b) in [
          (l.wheels, l.idle),
          (l.idle, l.heat),
          (l.tyres, l.air),
          (l.air, l.brakes),
        ]) {
          expect(a.bottom, lessThan(b.top));
        }
      });
    }

    test('a node is as tall as its share of the fuel', () {
      final l = PowerflowLayout(flow, const Size(380, 262));
      expect(l.wheels.height / l.fuel.height, closeTo(0.22, 0.01));
      expect(l.heat.height / l.fuel.height, closeTo(0.70, 0.01));
      expect(l.idle.height / l.fuel.height, closeTo(0.08, 0.01));
    });

    test('the brake discs, in rupees, follow the share', () {
      const priced = Powerflow(
        fuelKwh: 12,
        idleShare: 0.08,
        wheelShare: 0.22,
        heatShare: 0.70,
        tyreShare: 0.4,
        airShare: 0.35,
        brakeShare: 0.25,
        cost: 175,
      );
      expect(
        priced.rupees(priced.brakeOfFuel),
        closeTo(175 * 0.22 * 0.25, 1e-9),
      );
    });
  });

  group('PowerCurvePainter axes', () {
    List<TripSample> pull(double toRpm) => [
      for (var i = 0; i < 40; i++)
        TripSample(
          seconds: i.toDouble(),
          speedKmh: 30.0 + i * 2,
          rpm: 1500 + (toRpm - 1500) * i / 39,
          throttle: 70,
          litresPerHour: 8,
        ),
    ];

    test(
      'the rev axis reaches 7,000 and goes past the revs the car reached',
      () {
        expect(PowerCurvePainter.rpmMax(PowerCurve.from([pull(3000)])), 7000);
        expect(PowerCurvePainter.rpmMax(PowerCurve.from([pull(7200)])), 8000);
        expect(PowerCurvePainter.rpmMax(PowerCurve.from(const [])), 7000);
      },
    );

    test(
      'the power axis is in steps of 20 kW, 40 at least, above the highest',
      () {
        expect(PowerCurvePainter.kwMax(PowerCurve.from(const [])), 40);
        final c = PowerCurve.from([pull(5000)]);
        final top = c.highest!.kw;
        final m = PowerCurvePainter.kwMax(c);
        expect(m % 20, 0);
        expect(m, greaterThan(top));
        expect(m, greaterThanOrEqualTo(40));
      },
    );
  });

  group('GearChartPainter', () {
    test('the speed axis is to the next 20 km/h, 80 at least', () {
      expect(GearChartPainter.kmhMax(Gearbox.from(const [])), 80);
      final fast = Gearbox.from([
        [
          for (var i = 0; i < 60; i++)
            TripSample(
              seconds: i.toDouble(),
              speedKmh: 90.0 + i,
              rpm: 3000,
              throttle: 20,
              litresPerHour: 5,
            ),
        ],
      ]);
      expect(GearChartPainter.kmhMax(fast), 160);
    });
  });
}
