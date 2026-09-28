// The parked share (DESIGN.md 7.2): rises on spring.reveal, falls on
// spring.snap inside the 300 ms the motion return allows, cancels whatever is
// in flight on a mid-flight flip, starts at rest at the state it is given,
// and its stagger formula.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/motion/parked_share.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';

void main() {
  late ManualMotionClock motion;

  setUp(() => motion = ManualMotionClock());
  tearDown(() => motion.dispose());

  void run(Duration duration) {
    var left = duration.inMicroseconds;
    const frame = 16667;
    while (left > 0) {
      final step = left < frame ? left : frame;
      motion.tick(step / 1e6);
      left -= step;
    }
  }

  group('ParkedShare (DESIGN.md 7.2)', () {
    late ValueNotifier<bool> source;
    late ParkedShare share;

    setUp(() {
      source = ValueNotifier(false);
      share = ParkedShare(
        source: source,
        clock: motion,
        initiallyParked: false,
      );
      addTearDown(share.dispose);
      addTearDown(source.dispose);
    });

    test('starts at rest at the state it is given', () {
      expect(share.value, 0);
      expect(share.isSettled, isTrue);
      expect(motion.isTicking, isFalse);
    });

    test('a parked flip starts it rising, without jumping', () {
      source.value = true;
      motion.tick(0.001);

      expect(share.value, greaterThan(0));
      expect(share.value, lessThan(0.05), reason: 'no jump');
      expect(share.isSettled, isFalse);
    });

    test('the rise is parked on spring.reveal by a scene later', () {
      source.value = true;

      // A scene is the choreography's own budget; spring.reveal is softer
      // than snap, so the settle is judged a little past it, the way the
      // dock's own rise test judges its rise.
      run(TapeDurations.scene + const Duration(milliseconds: 320));

      expect(share.value, closeTo(1, 0.05));
    });

    test(
      'the motion return brings it back inside 300 ms, cancelling the rise',
      () {
        source.value = true;
        run(const Duration(milliseconds: 100));
        expect(share.value, lessThan(0.5), reason: 'the rise is in flight');

        source.value = false;

        run(TapeMotion.motionReturn);

        expect(share.value, closeTo(0, 0.05));
      },
    );

    test('rising and falling twice in a row lands settled both ways', () {
      for (var i = 0; i < 2; i++) {
        source.value = true;
        run(TapeDurations.scene + const Duration(milliseconds: 320));
        expect(share.value, closeTo(1, 0.05));

        source.value = false;
        run(TapeMotion.motionReturn);
        expect(share.value, closeTo(0, 0.05));
      }
    });

    test('never leaves its own 0-to-1 band', () {
      for (var i = 0; i < 40; i++) {
        source.value = i.isEven;
        run(const Duration(milliseconds: 25));
        expect(share.value, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('ParkedShare.staggered (DESIGN.md 5.7)', () {
    test('the first item moves with the group, exactly', () {
      expect(ParkedShare.staggered(0, 0), 0);
      expect(ParkedShare.staggered(1, 0), 1);
      expect(ParkedShare.staggered(0.5, 0), 0.5);
    });

    test('a later item is still parked where the group is only partway', () {
      // Item 1 starts one stagger in, so at the group's own 0.5 it has less
      // than half of its own rise left to run.
      expect(ParkedShare.staggered(0.5, 1), lessThan(0.5));
      expect(ParkedShare.staggered(1, 1), 1);
      expect(ParkedShare.staggered(0, 1), 0);
    });

    test('everything past the stagger budget moves with the last item', () {
      expect(ParkedShare.staggered(1, 6), 1);
      expect(ParkedShare.staggered(1, 40), 1);
      expect(ParkedShare.staggered(0.5, 6), ParkedShare.staggered(0.5, 5));
    });
  });
}
