// Phosphor persistence (DESIGN.md 5.5 and 14.2): the decay matches its time
// constant within 5%, at any frame rate.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/motion/phosphor.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';

void main() {
  group('Phosphor', () {
    const phosphor = Phosphor();

    test('uses the time constants of DESIGN.md 5.5', () {
      expect(phosphor.riseSeconds, 0.030);
      expect(phosphor.decaySeconds, 0.180);
    });

    test('decay: after one time constant, 1/e of the level is left', () {
      final level = phosphor.step(1, 0, TapeMotion.phosphorDecaySeconds);

      expect(level, closeTo(math.exp(-1), math.exp(-1) * 0.05));
    });

    test('decay follows an exponential at every time', () {
      for (final t in [0.03, 0.09, 0.18, 0.36, 0.54]) {
        final level = phosphor.step(1, 0, t);
        final expected = math.exp(-t / 0.180);
        expect(level, closeTo(expected, expected * 0.05), reason: '$t s');
      }
    });

    test('rise: after one time constant, 1 - 1/e of the way up', () {
      final level = phosphor.step(0, 1, TapeMotion.phosphorRiseSeconds);

      expect(level, closeTo(1 - math.exp(-1), (1 - math.exp(-1)) * 0.05));
    });

    test('rise is quicker than decay', () {
      final up = phosphor.step(0, 1, 0.05);
      final down = phosphor.step(1, 0, 0.05);

      expect(up, greaterThan(0.8));
      expect(down, greaterThan(0.7));
      expect(1 - up, lessThan(down));
    });

    test('is the same at any frame rate', () {
      // 0.4 s is a whole number of frames at each of these rates.
      double run(int framesPerSecond) {
        var level = 1.0;
        for (var i = 0; i < 0.4 * framesPerSecond; i++) {
          level = phosphor.step(level, 0, 1 / framesPerSecond);
        }
        return level;
      }

      final at60 = run(60);

      expect(run(30), closeTo(at60, 1e-9));
      expect(run(240), closeTo(at60, 1e-9));
      expect(run(120), closeTo(at60, 1e-9));
      expect(at60, closeTo(math.exp(-0.4 / 0.18), 1e-9));
    });

    test('never overshoots or leaves 0 to 1', () {
      for (final dt in [0.0, 0.001, 0.05, 1.0, 100.0]) {
        for (final (from, to) in [
          (0.0, 1.0),
          (1.0, 0.0),
          (0.4, 0.9),
          (0.9, 0.4),
        ]) {
          final level = phosphor.step(from, to, dt);
          expect(
            level,
            inInclusiveRange(math.min(from, to), math.max(from, to)),
          );
        }
      }
    });

    test('a level already on its target stays', () {
      expect(phosphor.step(0.5, 0.5, 0.1), 0.5);
    });
  });

  group('PhosphorBank', () {
    late ManualMotionClock clock;
    late PhosphorBank bank;

    setUp(() {
      clock = ManualMotionClock();
      bank = PhosphorBank(clock: clock, count: 8);
    });

    tearDown(() {
      bank.dispose();
      clock.dispose();
    });

    test('starts dark', () {
      expect(bank.levels, everyElement(0));
    });

    test('a lit segment rises fast, and decays slowly when switched off', () {
      bank.setTarget(3, 1);
      clock.advance(const Duration(milliseconds: 100));
      expect(bank.levels[3], greaterThan(0.95));
      expect(bank.levels[2], 0, reason: 'the others are untouched');

      bank.setTarget(3, 0);
      clock.advance(const Duration(milliseconds: 180));

      expect(bank.levels[3], closeTo(math.exp(-1), math.exp(-1) * 0.06));
    });

    test('every segment decays on its own clock from where it was', () {
      bank.setAll((i) => 1);
      clock.advance(const Duration(milliseconds: 200));
      // Switch them off one after another, as a needle falling past them does.
      for (var i = 0; i < 8; i++) {
        bank.setTarget(i, 0);
        clock.advance(const Duration(milliseconds: 30));
      }

      for (var i = 0; i < 7; i++) {
        expect(bank.levels[i], lessThan(bank.levels[i + 1]));
      }
    });

    test('settles exactly, and then asks for no frames', () {
      bank.setAll((i) => i.isEven ? 1.0 : 0.0);
      expect(clock.attachedCount, 1);

      clock.advance(const Duration(seconds: 3));

      for (var i = 0; i < 8; i++) {
        expect(bank.levels[i], i.isEven ? 1.0 : 0.0);
      }
      expect(clock.attachedCount, 0);
      expect(clock.isTicking, isFalse);
    });

    test('tells its listeners while it moves and not at rest', () {
      var notified = 0;
      bank.addListener(() => notified++);

      bank.setTarget(0, 1);
      clock.advance(const Duration(seconds: 2));
      final whileMoving = notified;
      expect(whileMoving, greaterThan(3));

      clock.advance(const Duration(seconds: 2));
      expect(notified, whileMoving);
    });

    test('reset puts every segment at a level at once', () {
      bank.setAll((i) => 1);
      clock.advance(const Duration(milliseconds: 500));

      bank.reset(0.25);

      expect(bank.levels, everyElement(0.25));
      expect(bank.targetOf(0), 0.25);
    });

    test('a slow frame decays as far as it should and no further', () {
      bank.setAll((i) => 1);
      clock.advance(const Duration(milliseconds: 300));
      bank.setAll((i) => 0);

      clock.tick(0.05);
      final one = bank.levels[0];
      // The frame was clamped to 50 ms, so it is 1 * exp(-0.05 / 0.18).
      expect(one, closeTo(math.exp(-0.05 / 0.18), 1e-3));
    });

    test('stays between 0 and 1 whatever the frames do', () {
      bank.setAll((i) => i / 7);
      for (final dt in [0.0, 0.016, 0.05, 5.0, 0.001]) {
        clock.tick(dt);
        for (final level in bank.levels) {
          expect(level, inInclusiveRange(0, 1));
        }
      }
    });
  });
}
