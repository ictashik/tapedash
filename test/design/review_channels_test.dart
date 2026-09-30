// The scales the telemetry channels are drawn on in Review: a coolant that sat
// at 90 must not look like one that sat at 0.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/trips/trip.dart';
import 'package:tapedash/ui/design/components/route_trail.dart';
import 'package:tapedash/ui/design/components/telemetry_scrubber.dart';

TripSample s({double? coolant, double? volts, double rpm = 1000}) => TripSample(
  seconds: 0,
  speedKmh: 30,
  rpm: rpm,
  throttle: 10,
  litresPerHour: 1,
  coolantC: coolant,
  voltage: volts,
);

void main() {
  group('normaliseSpread', () {
    test('a range wider than the minimum uses its own ends', () {
      expect(normaliseSpread([70, 80, 90], minSpan: 10), [0, 0.5, 1]);
    });

    test('a steady value sits mid-ramp, not at one end', () {
      final out = normaliseSpread([90, 90, 90], minSpan: 10);

      expect(out, [0.5, 0.5, 0.5]);
    });

    test('a small change is a small part of the ramp', () {
      // 90 to 92 over a 10 degree minimum span: 20% of the ramp.
      final out = normaliseSpread([90, 91, 92], minSpan: 10);

      expect(out.last - out.first, closeTo(0.2, 1e-9));
    });

    test('nothing is nothing', () {
      expect(normaliseSpread(const [], minSpan: 10), isEmpty);
    });
  });

  group('ScrubberTrace', () {
    test('spread covers the trip, and at least the minimum', () {
      final t = ScrubberTrace.spread(
        [s(coolant: 60), s(coolant: 88), s(coolant: null)],
        (x) => x.coolantC,
        minSpan: 10,
      );

      expect(t.min, 60);
      expect(t.max, 88);
    });

    test('a flat channel gets the minimum span about its value', () {
      final t = ScrubberTrace.spread(
        [s(volts: 14.1), s(volts: 14.1)],
        (x) => x.voltage,
        minSpan: 1,
      );

      expect(t.min, closeTo(13.6, 1e-9));
      expect(t.max, closeTo(14.6, 1e-9));
    });

    test('with no readings at all it still has a range', () {
      final t = ScrubberTrace.spread(
        [s(), s()],
        (x) => x.coolantC,
        minSpan: 10,
      );

      expect(t.max - t.min, 10);
    });

    test('roundedMax goes up to a step, and is at least one step', () {
      expect(
        ScrubberTrace.roundedMax(
          [s(rpm: 2350), s(rpm: 3100)],
          (x) => x.rpm,
          1000,
        ),
        4000,
      );
      expect(ScrubberTrace.roundedMax([s(rpm: 10)], (x) => x.rpm, 1000), 1000);
    });
  });
}
