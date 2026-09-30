// The tracking filter (DESIGN.md 5.2, step 3): a Kalman filter on value and
// velocity, for signals that arrive once or twice a second from a cheap adapter.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/dsp/tracking_filter.dart';

const _spec = TrackingSpec(
  measurementSigma: 20,
  accelerationSigma: 3500,
  maxExtrapolation: 500,
);

Duration ms(int n) => Duration(milliseconds: n);

void main() {
  test('nothing is known before the first sample', () {
    final f = TrackingFilter(_spec);

    expect(f.hasEstimate, isFalse);
    expect(f.predict(ms(1000)), 0);
  });

  test('the first sample is where it starts, at rest', () {
    final f = TrackingFilter(_spec)..update(2000, ms(0));

    expect(f.value, 2000);
    expect(f.velocity, 0);
    expect(f.predict(ms(500)), 2000);
  });

  test('a steady ramp is learned: the velocity comes out right', () {
    final f = TrackingFilter(_spec);
    // 1000 rpm/s, sampled every 750 ms (a slow adapter).
    for (var i = 0; i < 12; i++) {
      f.update(1000 + 1000 * (i * 0.75), ms(i * 750));
    }

    expect(f.velocity, closeTo(1000, 60));
    expect(f.value, closeTo(1000 + 1000 * 11 * 0.75, 60));
  });

  test('between samples the estimate runs ahead, and fades, and is capped', () {
    final f = TrackingFilter(_spec);
    for (var i = 0; i < 12; i++) {
      f.update(1000 + 1000 * (i * 0.75), ms(i * 750));
    }
    final last = f.at;

    final soon = f.predict(last + ms(100)) - f.value;
    final later = f.predict(last + ms(600)) - f.value;
    final forever = f.predict(last + const Duration(seconds: 30)) - f.value;

    expect(soon, greaterThan(0));
    expect(later, greaterThan(soon));
    // The run at 1000 rpm/s and a 0.5 s fade is at most 500 (the cap).
    expect(forever, lessThanOrEqualTo(500));
    expect(
      f.predict(last + ms(1500)),
      f.predict(last + const Duration(seconds: 30)),
    );
  });

  test('the correction is bigger the further apart the samples are', () {
    double gain(int gapMs, [TrackingSpec spec = _spec]) {
      final f = TrackingFilter(spec);
      // Settled on a steady value, then one sample 200 off.
      for (var i = 0; i < 30; i++) {
        f.update(1000, ms(i * gapMs));
      }
      final before = f.value;
      f.update(1200, ms(30 * gapMs));
      return (f.value - before) / 200;
    }

    expect(gain(1000), greaterThan(0.95));
    expect(gain(1000), greaterThan(gain(100) + 0.1));
  });

  test('a signal that cannot move fast is smoothed harder at a fast rate', () {
    const speed = TrackingSpec(
      measurementSigma: 0.7,
      accelerationSigma: 6,
      maxExtrapolation: 4,
    );
    final f = TrackingFilter(speed);
    for (var i = 0; i < 30; i++) {
      f.update(50, ms(i * 100));
    }
    final before = f.value;

    // One sample a whole km/h off, at 10 Hz: mostly rounding, so mostly ignored.
    f.update(51, ms(3000));

    expect(f.value - before, lessThan(0.5));
  });

  test('a sample that is not a number is ignored', () {
    final f = TrackingFilter(_spec)..update(1000, ms(0));

    f.update(double.nan, ms(500));
    f.update(double.infinity, ms(600));

    expect(f.value, 1000);
    expect(f.at, ms(0));
  });

  test('samples out of order or at the same time do no harm', () {
    final f = TrackingFilter(_spec)
      ..update(1000, ms(0))
      ..update(1010, ms(500))
      ..update(1020, ms(500))
      ..update(1015, ms(495));

    expect(f.value.isFinite, isTrue);
    expect(f.velocity.isFinite, isTrue);
    expect(f.value, closeTo(1015, 30));
  });

  test('after a long gap the past is forgotten', () {
    final f = TrackingFilter(_spec);
    for (var i = 0; i < 10; i++) {
      f.update(1000.0 + 1000 * i * 0.5, ms(i * 500));
    }

    f.update(900, const Duration(seconds: 30));

    expect(f.value, 900);
    expect(f.velocity, 0);
  });

  test('reset forgets everything', () {
    final f = TrackingFilter(_spec)..update(1000, ms(0));

    f.reset();

    expect(f.hasEstimate, isFalse);
  });
}
