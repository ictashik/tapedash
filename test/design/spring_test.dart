// The spring tokens and SpringValue against DESIGN.md 5.3 and 14.2: overshoot
// and settle times, no overshoot on the gauge and snap springs, momentum kept
// on a retarget, and no NaN.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/motion/spring_value.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';

/// What a step response looks like: how far it overshoots, and when it has
/// settled within 2% for good.
class _Step {
  _Step(this.overshoot, this.settleSeconds, this.trace);

  /// How far past the target it goes, as a share of the step (0 if it never does).
  final double overshoot;

  final double settleSeconds;
  final List<double> trace;
}

_Step _stepResponse(SpringSpec spec, {double to = 1, double from = 0}) {
  final motion = ManualMotionClock();
  final spring = SpringValue(clock: motion, spec: spec, initial: from)
    ..retarget(to);
  final trace = <double>[from];
  var peak = 0.0;
  var lastOutside = 0.0;
  const dt = 0.001;
  final size = (to - from).abs();
  for (var i = 1; i <= 3000; i++) {
    motion.tick(dt);
    final x = spring.value;
    trace.add(x);
    final past = (x - to) * (to - from).sign;
    peak = math.max(peak, past);
    if ((x - to).abs() > 0.02 * size) lastOutside = i * dt;
  }
  spring.dispose();
  motion.dispose();
  return _Step(peak / size, lastOutside, trace);
}

void main() {
  group('the springs of DESIGN.md 5.3', () {
    test('needle: about 4% overshoot, settled within 0.45 s', () {
      final step = _stepResponse(TapeSprings.needle);

      expect(step.overshoot, inInclusiveRange(0.03, 0.06));
      expect(step.settleSeconds, lessThanOrEqualTo(0.45));
      expect(step.settleSeconds, greaterThan(0.25), reason: 'not a snap');
    });

    test('gauge and snap never overshoot', () {
      for (final spec in [TapeSprings.gauge, TapeSprings.snap]) {
        final step = _stepResponse(spec);
        expect(step.overshoot, 0, reason: spec.name);
      }
    });

    test('snap is quick, and gauge is only a little slower', () {
      final snap = _stepResponse(TapeSprings.snap);
      final gauge = _stepResponse(TapeSprings.gauge);

      // Critically damped springs settle in about 5.8 / omega: 0.24 s and 0.30 s.
      expect(snap.settleSeconds, lessThan(gauge.settleSeconds));
      expect(snap.settleSeconds, inInclusiveRange(0.2, 0.26));
      expect(gauge.settleSeconds, inInclusiveRange(0.27, 0.33));
    });

    test('page has a tiny settle, and reveal is softer and slower', () {
      final page = _stepResponse(TapeSprings.page);
      final reveal = _stepResponse(TapeSprings.reveal);

      // "A tiny settle": under a tenth of a percent, which is only just a settle.
      expect(page.overshoot, inExclusiveRange(0, 0.01));
      expect(reveal.overshoot, inExclusiveRange(0, 0.01));
      expect(reveal.settleSeconds, greaterThan(page.settleSeconds));
      expect(reveal.settleSeconds, lessThan(0.6));
    });

    test('overshoot follows the damping ratio, as the theory says', () {
      for (final spec in TapeSprings.all) {
        if (spec.dampingRatio >= 1) continue;
        final z = spec.dampingRatio;
        final expected = math.exp(-math.pi * z / math.sqrt(1 - z * z));

        expect(
          _stepResponse(spec).overshoot,
          closeTo(expected, expected * 0.05),
          reason: spec.name,
        );
      }
    });

    test('reduce motion removes the overshoot from every spring', () {
      for (final spec in TapeSprings.all) {
        expect(
          _stepResponse(spec.withoutOvershoot).overshoot,
          0,
          reason: spec.name,
        );
      }
    });

    test('a step down behaves like a step up', () {
      final up = _stepResponse(TapeSprings.needle);
      final down = _stepResponse(TapeSprings.needle, from: 1, to: 0);

      expect(down.overshoot, closeTo(up.overshoot, 1e-9));
      expect(down.settleSeconds, up.settleSeconds);
    });

    test('the scale of the step does not change the shape', () {
      final small = _stepResponse(TapeSprings.needle, to: 1);
      final big = _stepResponse(TapeSprings.needle, to: 7000);

      expect(big.overshoot, closeTo(small.overshoot, 1e-6));
      expect(big.settleSeconds, small.settleSeconds);
    });
  });

  group('SpringValue', () {
    late ManualMotionClock motion;

    setUp(() => motion = ManualMotionClock());
    tearDown(() => motion.dispose());

    SpringValue make({
      SpringSpec spec = TapeSprings.needle,
      double initial = 0,
    }) {
      final spring = SpringValue(clock: motion, spec: spec, initial: initial);
      addTearDown(spring.dispose);
      return spring;
    }

    test('starts at rest at its initial value', () {
      final spring = make(initial: 5);

      expect(spring.value, 5);
      expect(spring.velocity, 0);
      expect(spring.target, 5);
      expect(spring.isSettled, isTrue);
    });

    test('moves towards its target and comes to rest on it exactly', () {
      final spring = make()..retarget(100);

      motion.advance(const Duration(seconds: 2));

      expect(spring.value, 100);
      expect(spring.velocity, 0);
      expect(spring.isSettled, isTrue);
    });

    test('a retarget in flight keeps position and velocity', () {
      final spring = make()..retarget(100);
      motion.advance(const Duration(milliseconds: 120));
      final before = spring.value;
      final velocity = spring.velocity;
      expect(velocity, greaterThan(50), reason: 'it is moving');

      spring.retarget(40);
      // One tiny frame later, nothing has jumped.
      motion.tick(0.001);

      expect(spring.value, closeTo(before + velocity * 0.001, 0.5));
      expect(spring.velocity, closeTo(velocity, velocity * 0.15));
      expect(spring.target, 40);
    });

    test('a retarget in the direction of travel does not stop and restart', () {
      final spring = make(spec: TapeSprings.gauge)..retarget(100);
      motion.advance(const Duration(milliseconds: 100));
      final velocity = spring.velocity;

      spring.retarget(200);
      motion.tick(0.001);

      expect(spring.velocity, greaterThan(velocity * 0.9));
    });

    test(
      'a stream of retargets is smooth: no step in the value between frames',
      () {
        final spring = make(spec: TapeSprings.gauge);
        var last = spring.value;
        var biggest = 0.0;
        // A speed climbing 0 to 60 in whole km/h, one sample every 100 ms.
        for (var v = 1; v <= 60; v++) {
          spring.retarget(v.toDouble());
          for (var f = 0; f < 6; f++) {
            motion.tick();
            biggest = math.max(biggest, (spring.value - last).abs());
            last = spring.value;
          }
        }

        expect(
          biggest,
          lessThan(1.5),
          reason: 'about 1 km/h per 100 ms of climb',
        );
      },
    );

    test('a stall does not make it jump: a long frame counts as 50 ms', () {
      final steady = ManualMotionClock();
      final stalled = ManualMotionClock();
      final a = SpringValue(clock: steady, spec: TapeSprings.needle)
        ..retarget(100);
      final b = SpringValue(clock: stalled, spec: TapeSprings.needle)
        ..retarget(100);
      addTearDown(() {
        a.dispose();
        b.dispose();
        steady.dispose();
        stalled.dispose();
      });

      steady.tick(0.05);
      stalled.tick(5); // a 5 s stall, in one frame

      expect(b.value, closeTo(a.value, 1e-9));
      expect(b.value, lessThan(60), reason: 'it has not jumped to the target');
    });

    test('ignores a target that is not a finite number', () {
      final spring = make()..retarget(50);
      motion.advance(const Duration(milliseconds: 100));

      for (final bad in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        spring.retarget(bad);
      }

      expect(spring.target, 50);
      motion.advance(const Duration(seconds: 2));
      expect(spring.value, 50);
    });

    test('stays finite on extreme values', () {
      final spring = make()..retarget(1e12);
      motion.advance(const Duration(milliseconds: 200));
      expect(spring.value.isFinite, isTrue);
      expect(spring.velocity.isFinite, isTrue);

      spring.retarget(-1e12);
      motion.advance(const Duration(milliseconds: 200));
      expect(spring.value.isFinite, isTrue);

      spring.retarget(0);
      motion.advance(const Duration(seconds: 5));
      expect(spring.value, 0);
    });

    test('a negative or NaN frame does nothing', () {
      final spring = make()..retarget(100);
      motion.tick(0.02);
      final value = spring.value;

      motion.tick(-1);
      motion.tick(double.nan);

      expect(spring.value, value);
    });

    test('jumpTo puts it somewhere at rest and stops the clock', () {
      final spring = make()..retarget(100);
      motion.advance(const Duration(milliseconds: 50));

      spring.jumpTo(3);

      expect(spring.value, 3);
      expect(spring.velocity, 0);
      expect(spring.isSettled, isTrue);
      expect(motion.attachedCount, 0);
    });

    test('tells its listeners while it moves and not once it has rested', () {
      final spring = make()..retarget(10);
      var notified = 0;
      spring.addListener(() => notified++);

      motion.advance(const Duration(seconds: 2));
      final whileMoving = notified;
      expect(whileMoving, greaterThan(10));

      motion.advance(const Duration(seconds: 2));
      expect(notified, whileMoving, reason: 'at rest, nothing more is said');
    });

    test('at rest it costs the clock nothing', () {
      final spring = make()..retarget(10);
      expect(motion.attachedCount, 1);

      motion.advance(const Duration(seconds: 3));

      expect(spring.isSettled, isTrue);
      expect(motion.attachedCount, 0);
      expect(motion.isTicking, isFalse);
    });

    test('changing the spring restarts the one in flight on it', () {
      final spring = make()..retarget(100);
      motion.advance(const Duration(milliseconds: 100));

      spring.setSpec(TapeSprings.needle.withoutOvershoot);
      var peak = 0.0;
      for (var i = 0; i < 300; i++) {
        motion.tick(0.005);
        peak = math.max(peak, spring.value);
      }

      expect(peak, lessThanOrEqualTo(100 + 1e-6));
    });

    test('disposed, it ignores more targets and lets go of the clock', () {
      final spring = SpringValue(clock: motion, spec: TapeSprings.needle)
        ..retarget(10);
      spring.dispose();

      spring.retarget(20);

      expect(motion.attachedCount, 0);
    });
  });
}
