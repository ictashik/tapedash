// The ignition sequence (DESIGN.md 7.13): the needle sweeps to redline and
// back, the numerals roll up from 0, the arc lights in a wave, the horizon
// and flanks come in -- and none of it ever delays or loses live data.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/motion/ignition_sequence.dart';
import 'package:tapedash/ui/design/motion/smoothing_pipeline.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';

import 'support/motion_rig.dart';

void main() {
  late MotionRig rig;
  late SmoothedSignal rpm;
  late SmoothedSignal speed;

  setUp(() {
    rig = MotionRig();
    rpm = SmoothedSignal(
      motion: rig.motion,
      clock: rig.clock,
      spring: TapeSprings.needle,
    )..ingest(rig.reading(900));
    speed = SmoothedSignal(
      motion: rig.motion,
      clock: rig.clock,
      spring: TapeSprings.gauge,
    )..ingest(rig.reading(60));
  });
  tearDown(() {
    rpm.dispose();
    speed.dispose();
    rig.dispose();
  });

  IgnitionSequence make({
    IgnitionMode mode = IgnitionMode.full,
    bool reduceMotion = false,
  }) {
    final sequence = IgnitionSequence(
      clock: rig.motion,
      rpm: rpm,
      speed: speed,
      mode: mode,
      reduceMotion: reduceMotion,
    );
    addTearDown(sequence.dispose);
    return sequence;
  }

  group('SmoothedSignal.hold', () {
    test(
      'keeps the target off the readings until released, then retargets',
      () {
        rpm.hold(6500);
        rpm.ingest(rig.reading(1200));
        expect(rpm.target, 6500);

        rpm.release();

        expect(rpm.isHeld, isFalse);
        expect(
          rpm.target,
          1200,
          reason: 'the newest reading, not the stale one',
        );
      },
    );
  });

  group('Full', () {
    test('the needle goes to redline and comes back to the live rpm', () {
      final sequence = make()..play();

      rig.run(const Duration(milliseconds: 500));
      expect(rpm.value, greaterThan(3000), reason: 'sweeping up');
      expect(rpm.isHeld, isTrue);

      rig.run(const Duration(milliseconds: 1500));
      expect(rpm.isHeld, isFalse);
      expect(rpm.value, closeTo(900, 20), reason: 'settled on the live value');
      expect(sequence.isRunning, isFalse);
    });

    test('the numerals roll up from 0 to the live value', () {
      make().play();

      rig.run(const Duration(milliseconds: 100));
      expect(speed.value, lessThan(1), reason: 'held at 0 first');

      rig.run(const Duration(milliseconds: 700));
      expect(speed.value, inExclusiveRange(1, 60), reason: 'rolling');

      rig.run(const Duration(milliseconds: 1500));
      expect(speed.value, closeTo(60, 0.5));
    });

    test('live data arriving mid-sequence simply retargets', () {
      make().play();
      rig.run(const Duration(milliseconds: 100));

      rpm.ingest(rig.reading(2500));
      rig.run(const Duration(milliseconds: 2000));

      expect(rpm.value, closeTo(2500, 30));
    });

    test('the shares run their windows: wave, then horizon and flanks', () {
      final sequence = make()..play();
      expect(sequence.arcWave, 0);
      expect(sequence.horizonDraw, 0);

      rig.run(const Duration(milliseconds: 300));
      expect(sequence.arcWave, inExclusiveRange(0.5, 1));
      expect(sequence.horizonDraw, 0, reason: 'starts at 600 ms');

      rig.run(const Duration(milliseconds: 500));
      expect(sequence.arcWave, 1);
      expect(sequence.horizonDraw, inExclusiveRange(0, 1));

      rig.run(const Duration(milliseconds: 1000));
      expect(sequence.arcWave, 1);
      expect(sequence.horizonDraw, 1);
      expect(sequence.flank(0), 1);
    });

    test(
      'the flanks are staggered: the second starts later than the first',
      () {
        final sequence = make()..play();
        rig.run(const Duration(milliseconds: 700));

        expect(sequence.flank(0), greaterThan(sequence.flank(3)));
      },
    );
  });

  group('Subtle, Off and reduced motion', () {
    test(
      'Subtle leaves the needle and the arc alone, and rolls the numerals',
      () {
        final sequence = make(mode: IgnitionMode.subtle)..play();

        rig.run(const Duration(milliseconds: 100));
        expect(rpm.isHeld, isFalse);
        expect(rpm.value, closeTo(900, 1));
        expect(sequence.arcWave, 1);
        expect(speed.value, lessThan(1));
        expect(sequence.horizonDraw, lessThan(1));
      },
    );

    test('Off plays nothing at all', () {
      final sequence = make(mode: IgnitionMode.off)..play();

      expect(sequence.isRunning, isFalse);
      expect(speed.value, 60);
      expect(sequence.horizonDraw, 1);
    });

    test('reduced motion is a 200 ms fade, with no sweep and no roll', () {
      final sequence = make(reduceMotion: true)..play();

      expect(rpm.isHeld, isFalse);
      expect(speed.isHeld, isFalse);
      rig.run(const Duration(milliseconds: 100));
      expect(sequence.horizonDraw, inExclusiveRange(0, 1));

      rig.run(const Duration(milliseconds: 200));
      expect(sequence.horizonDraw, 1);
      expect(sequence.isRunning, isFalse);
    });
  });

  test('playing again restarts, and never leaves a signal held', () {
    final sequence = IgnitionSequence(clock: rig.motion, rpm: rpm, speed: speed)
      ..play();
    rig.run(const Duration(milliseconds: 200));
    sequence.play();
    sequence.dispose();

    expect(rpm.isHeld, isFalse);
    expect(speed.isHeld, isFalse);
  });
}
