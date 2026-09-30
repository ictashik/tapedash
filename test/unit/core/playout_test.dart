// The playout buffer (DESIGN.md 5.2, step 3): a line through the samples, a little
// in the past, that never goes outside what the car has said.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/dsp/playout.dart';

const _spec = PlayoutSpec(tailCap: 100, min: 0);

Duration ms(int n) => Duration(milliseconds: n);

/// A buffer with a sample every [gapMs], from `start`, of [values].
PlayoutBuffer filled(
  List<double> values, {
  int gapMs = 800,
  PlayoutSpec spec = _spec,
}) {
  final b = PlayoutBuffer(spec);
  for (var i = 0; i < values.length; i++) {
    b.add(values[i], ms(10000 + i * gapMs));
  }
  return b;
}

void main() {
  test('nothing is known before the first sample', () {
    final b = PlayoutBuffer(_spec);

    expect(b.hasSamples, isFalse);
    expect(b.valueAt(ms(1000)), 0);
  });

  test('one sample is the value, at any time', () {
    final b = PlayoutBuffer(_spec)..add(2000, ms(1000));

    expect(b.valueAt(ms(1000)), 2000);
    expect(b.valueAt(ms(5000)), 2000, reason: 'nothing to carry on from');
  });

  test('the delay is two thirds of the usual gap, and at most 600 ms', () {
    expect(
      filled([1, 2, 3, 4, 5], gapMs: 800).delaySeconds,
      closeTo(0.52, 1e-9),
    );
    expect(
      filled([1, 2, 3, 4, 5], gapMs: 100).delaySeconds,
      closeTo(0.065, 1e-9),
    );
    expect(filled([1, 2, 3, 4, 5], gapMs: 2000).delaySeconds, 0.6);
  });

  test('a fast adapter is not held back at all: 10 ms gaps, 6.5 ms behind', () {
    final b = filled([100, 200, 300, 400], gapMs: 10);

    expect(b.delaySeconds, closeTo(0.0065, 1e-9));
    // At the newest sample's own time the line is 6.5 ms back along the last
    // segment: 65 rpm short of 400 at 10 rpm a millisecond.
    expect(b.valueAt(ms(10030)), closeTo(335, 1e-6));
  });

  test('between two samples it is the straight line, a delay behind', () {
    // 1000 at t=10.0 s, 2000 at 10.8 s, 3000 at 11.6 s: the delay is 0.52 s.
    final b = filled([1000, 2000, 3000]);

    // At now = 11.32 s the value shown is the line at 10.8 s: 2000.
    expect(b.valueAt(ms(11320)), closeTo(2000, 1e-6));
    // At now = 10.92 s it is the line at 10.4 s: half way from 1000 to 2000.
    expect(b.valueAt(ms(10920)), closeTo(1500, 1e-6));
  });

  test('it never goes outside the two samples it is between', () {
    final b = filled([1000, 3000, 1500, 2800, 900]);

    for (var t = 10000; t < 10000 + 4 * 800; t += 7) {
      final v = b.valueAt(ms(t + 520));
      expect(v, inInclusiveRange(900, 3000), reason: 'at $t ms');
    }
  });

  test('it moves one way between two samples, however the next ones go', () {
    final b = filled([1000, 3000, 1500]);
    var last = double.negativeInfinity;

    // From the first sample to the second: rising all the way.
    for (var t = 10520; t <= 10800 + 520; t += 5) {
      final v = b.valueAt(ms(t));
      expect(v, greaterThanOrEqualTo(last));
      last = v;
    }
  });

  test(
    'when the next sample is late the last slope carries on, fading, capped',
    () {
      // 1000 -> 2000 over 0.8 s is 1250 rpm/s: a run of up to 250 in 0.2 s, but
      // the cap is 100.
      final b = filled([1000, 2000]);
      final newest = 10000 + 800;

      final soon = b.valueAt(ms(newest + 520 + 50));
      final later = b.valueAt(ms(newest + 520 + 400));
      final muchLater = b.valueAt(ms(newest + 520 + 5000));

      expect(soon, greaterThan(2000));
      expect(later, greaterThan(soon));
      expect(muchLater, 2100, reason: 'held at the cap');
    },
  );

  test('a falling signal is carried down the same way, and not below 0', () {
    final b = filled([200, 20]);

    expect(b.valueAt(ms(10000 + 800 + 520 + 5000)), 0);
  });

  test('a signal is kept to its physical range', () {
    const percent = PlayoutSpec(tailCap: 20, min: 0, max: 100);
    final b = filled([70, 95], spec: percent);

    expect(b.valueAt(ms(10000 + 800 + 520 + 5000)), 100);
  });

  test('a sample that is not a number is ignored', () {
    final b = filled([1000, 2000]);

    b.add(double.nan, ms(20000));
    b.add(double.infinity, ms(20100));

    expect(b.latest, 2000);
  });

  test(
    'a sample at or before the newest replaces it: time only goes forward',
    () {
      final b = filled([1000, 2000]);

      b.add(2100, ms(10800));
      b.add(2200, ms(10790));

      expect(b.latest, 2200);
      expect(b.valueAt(ms(10800 + 520 + 1)), closeTo(2200, 20));
    },
  );

  test('after a long gap the past is forgotten', () {
    final b = filled([1000, 2000, 3000]);

    b.add(500, ms(60000));

    expect(b.latest, 500);
    expect(b.valueAt(ms(60000)), 500);
    expect(b.gapSeconds, 0);
  });

  test('the gap follows the adapter: 0.8 s, then it speeds up to 0.3 s', () {
    final b = filled([1, 2, 3, 4, 5, 6]);
    var t = 10000 + 5 * 800;
    for (var i = 0; i < 20; i++) {
      t += 300;
      b.add(i.toDouble(), ms(t));
    }

    expect(b.gapSeconds, closeTo(0.3, 0.02));
    expect(b.delaySeconds, closeTo(0.195, 0.02));
  });

  test('it keeps only the last twelve samples, however many come', () {
    final b = PlayoutBuffer(_spec);
    for (var i = 0; i < 1000; i++) {
      b.add(i.toDouble() * 10, ms(i * 100));
    }

    expect(b.latest, 9990);
    expect(b.valueAt(ms(999 * 100)), closeTo(9990 - 0.065 * 100, 1));
  });

  test('reset forgets everything', () {
    final b = filled([1, 2, 3])..reset();

    expect(b.hasSamples, isFalse);
    expect(b.gapSeconds, 0);
  });
}
