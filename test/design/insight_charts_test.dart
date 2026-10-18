// The insight charts' own arithmetic (DESIGN.md 6.18): what a painter keeps of a
// long trace, so that a short dip is never averaged away.
import 'package:flutter_test/flutter_test.dart';
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
}
