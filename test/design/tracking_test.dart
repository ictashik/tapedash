// Smoothing a slow adapter (DESIGN.md 5.2, step 3): the closed-form spring step
// agrees with Flutter's simulation, a tracked signal does not stair-step, and,
// measured against a truth on an adapter that gives 1.3 samples a second, it is
// clearly closer to the truth than a spring that goes to each sample.
import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/dsp/tracking_filter.dart';
import 'package:tapedash/ui/design/motion/smoothing_pipeline.dart';
import 'package:tapedash/ui/design/motion/spring_value.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';
import 'package:tapedash/vehicle/reading.dart';

import 'support/motion_rig.dart';

const _frame = Duration(microseconds: 16667);

void main() {
  late MotionRig rig;

  setUp(() => rig = MotionRig());
  tearDown(() => rig.dispose());

  group('SpringValue.track', () {
    for (final spec in [TapeSprings.needle, TapeSprings.gauge]) {
      test(
        '${spec.name}: a constant target gives the simulation\'s numbers',
        () {
          final value = SpringValue(clock: rig.motion, spec: spec);
          addTearDown(value.dispose);
          final sim = SpringSimulation(spec.description, 0, 100, 0);

          for (var i = 1; i <= 60; i++) {
            value.track(100, _frame.inMicroseconds / 1e6);
            final t = i * _frame.inMicroseconds / 1e6;
            expect(value.value, closeTo(sim.x(t), 1e-6), reason: 'frame $i');
            expect(
              value.velocity,
              closeTo(sim.dx(t), 1e-4),
              reason: 'frame $i',
            );
          }
        },
      );

      test('${spec.name}: one big step is the same as many small ones', () {
        final a = SpringValue(clock: rig.motion, spec: spec);
        final b = SpringValue(clock: rig.motion, spec: spec);
        addTearDown(a.dispose);
        addTearDown(b.dispose);

        a.track(80, 0.5);
        for (var i = 0; i < 50; i++) {
          b.track(80, 0.01);
        }

        expect(a.value, closeTo(b.value, 1e-6));
        expect(a.velocity, closeTo(b.velocity, 1e-4));
      });
    }

    test('a target that is not a number is ignored', () {
      final value = SpringValue(clock: rig.motion, spec: TapeSprings.gauge);
      addTearDown(value.dispose);

      value.track(double.nan, 0.016);
      value.track(10, double.nan);
      value.track(10, 0);

      expect(value.value, 0);
    });
  });

  group('a tracked signal', () {
    SmoothedSignal make({bool tracked = true}) {
      final signal = SmoothedSignal(
        motion: rig.motion,
        clock: rig.clock,
        spring: TapeSprings.needle,
        tracking: tracked ? TapeTracking.rpm : null,
      );
      addTearDown(signal.dispose);
      return signal;
    }

    test('is where the first reading is, and stays there for a steady one', () {
      final signal = make();
      signal.ingest(rig.reading(2000));

      for (var i = 0; i < 90; i++) {
        rig.run(_frame);
        if (i % 45 == 0) signal.ingest(rig.reading(2000));
      }

      expect(signal.value, closeTo(2000, 0.5));
    });

    test(
      'keeps moving between samples, where the plain spring has stopped',
      () {
        final plain = make(tracked: false);
        final tracked = make();
        // A 2000 rpm/s ramp, a sample every 0.75 s.
        const gap = Duration(milliseconds: 750);
        final origin = rig.clock.monotonic();
        double truth() =>
            1000.0 + 2 * (rig.clock.monotonic() - origin).inMilliseconds;
        for (var n = 0; n < 8; n++) {
          for (final s in [plain, tracked]) {
            s.ingest(rig.reading(truth()));
          }
          rig.run(gap);
        }
        // The last sample has just arrived; let the springs arrive at it.
        for (final s in [plain, tracked]) {
          s.ingest(rig.reading(truth()));
        }
        rig.run(const Duration(milliseconds: 400));
        final plainBefore = plain.value, trackedBefore = tracked.value;

        rig.run(const Duration(milliseconds: 200));

        expect(
          (plain.value - plainBefore).abs(),
          lessThan(40),
          reason: 'the plain spring is at rest on the last sample',
        );
        expect(
          tracked.value - trackedBefore,
          greaterThan(100),
          reason: 'the tracked value carries on up the ramp',
        );
      },
    );

    test('is not called stale between the samples of a slow adapter', () {
      final signal = make();
      // A sample every 0.9 s, jittering to 1.7 s once: a plain 1.5 s limit
      // would call that stale.
      final gaps = [900, 900, 900, 900, 1700];
      for (final g in gaps) {
        signal.ingest(rig.reading(2000));
        rig.run(Duration(milliseconds: g));
        if (g != 1700) expect(signal.isStale, isFalse);
      }
      // Learned gap is about 1 s, so the limit is about 2.5 s.
      expect(signal.isStale, isFalse, reason: '1.7 s after a sample');
    });

    test('is still stale after a real silence', () {
      final signal = make();
      for (var i = 0; i < 6; i++) {
        signal.ingest(rig.reading(2000));
        rig.run(const Duration(milliseconds: 500));
      }

      rig.run(const Duration(seconds: 3));

      expect(signal.isStale, isTrue);
      rig.run(const Duration(seconds: 1));
      expect(signal.staleness, 1);
    });
  });

  group('against the truth, on an adapter that gives 1.3 samples a second', () {
    // A truth that a driver could make: revs wandering with gear changes and
    // throttle, and a speed that follows.
    double rpmTruth(double t) =>
        2500 +
        1200 * math.sin(2 * math.pi * t / 7) +
        400 * math.sin(2 * math.pi * t / 2.9);
    double speedTruth(double t) => 45 + 20 * math.sin(2 * math.pi * t / 15);

    ({double plain, double tracked}) rms(
      double Function(double) truth,
      TrackingSpec spec,
      double Function(double) quantise,
    ) {
      final plain = SmoothedSignal(
        motion: rig.motion,
        clock: rig.clock,
        spring: TapeSprings.needle,
      );
      final tracked = SmoothedSignal(
        motion: rig.motion,
        clock: rig.clock,
        spring: TapeSprings.needle,
        tracking: spec,
      );
      addTearDown(plain.dispose);
      addTearDown(tracked.dispose);

      final origin = rig.clock.monotonic();
      double now() => (rig.clock.monotonic() - origin).inMicroseconds / 1e6;
      // Sample every 0.77 s, give or take 0.25 s, each arriving 0.3 s after it
      // was measured (the adapter's round trip and the BLE hop).
      final rng = math.Random(7);
      final arrivals = <(double, double)>[];
      var measured = 0.0;
      while (measured < 120) {
        arrivals.add((measured, measured + 0.3));
        measured += 0.77 + (rng.nextDouble() - 0.5) * 0.5;
      }

      var i = 0;
      var sumPlain = 0.0, sumTracked = 0.0;
      var n = 0;
      while (now() < 118) {
        rig.run(_frame);
        final t = now();
        while (i < arrivals.length && arrivals[i].$2 <= t) {
          final (m, a) = arrivals[i++];
          final r = Reading(
            value: quantise(truth(m)),
            at: origin + Duration(microseconds: (m * 1e6).round()),
            receivedAt: origin + Duration(microseconds: (a * 1e6).round()),
          );
          plain.ingest(r);
          tracked.ingest(r);
        }
        if (t > 10) {
          sumPlain += math.pow(plain.value - truth(t), 2);
          sumTracked += math.pow(tracked.value - truth(t), 2);
          n++;
        }
      }
      return (
        plain: math.sqrt(sumPlain / n),
        tracked: math.sqrt(sumTracked / n),
      );
    }

    test('the tach is much nearer the truth', () {
      final e = rms(rpmTruth, TapeTracking.rpm, (v) => (v * 4).round() / 4);

      // ignore: avoid_print
      print(
        'rpm   RMS error: plain spring ${e.plain.toStringAsFixed(0)} rpm, '
        'tracked ${e.tracked.toStringAsFixed(0)} rpm',
      );
      // 0.77 s between samples and a 2.9 s wobble in the truth leave a floor no
      // filter can get under; what it can do is take the delay out.
      expect(e.tracked, lessThan(e.plain * 0.85));
    });

    test(
      'the speedometer is nearer the truth, and not jumpy from rounding',
      () {
        final e = rms(speedTruth, TapeTracking.speed, (v) => v.roundToDouble());

        // ignore: avoid_print
        print(
          'speed RMS error: plain spring ${e.plain.toStringAsFixed(2)} km/h, '
          'tracked ${e.tracked.toStringAsFixed(2)} km/h',
        );
        expect(e.tracked, lessThan(e.plain * 0.75));
      },
    );
  });
}
