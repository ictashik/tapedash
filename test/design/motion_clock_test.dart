// The one clock all motion runs on (DESIGN.md 5.9): time from vsync, a frame
// clamped to 50 ms, and no frames at all when nothing is moving.
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/motion/spring_value.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';

/// Counts the frames it is given, and runs for as long as [frames] says.
class _Counter implements MotionDriven {
  _Counter(this.frames);

  int frames;
  int seen = 0;
  double total = 0;
  Duration? lastTime;

  @override
  bool advance(double dt, Duration time) {
    seen++;
    total += dt;
    lastTime = time;
    return --frames > 0;
  }
}

void main() {
  group('ManualMotionClock', () {
    late ManualMotionClock clock;

    setUp(() => clock = ManualMotionClock());
    tearDown(() => clock.dispose());

    test('starts at zero, idle', () {
      expect(clock.now, Duration.zero);
      expect(clock.attachedCount, 0);
      expect(clock.isTicking, isFalse);
    });

    test('runs what is attached on each frame, with the time', () {
      final counter = _Counter(100);
      clock.attach(counter);

      clock.tick(0.02);
      clock.tick(0.03);

      expect(counter.seen, 2);
      expect(counter.total, closeTo(0.05, 1e-9));
      expect(counter.lastTime, const Duration(milliseconds: 50));
      expect(clock.now, const Duration(milliseconds: 50));
    });

    test('a frame is at most 50 ms, however long the stall', () {
      final counter = _Counter(100);
      clock.attach(counter);

      clock.tick(3);

      expect(counter.total, TapeMotion.maxFrameSeconds);
      expect(clock.now, const Duration(milliseconds: 50));
    });

    test(
      'a frame of no length, a negative one or NaN moves time by nothing',
      () {
        final counter = _Counter(100);
        clock.attach(counter);

        clock.tick(0);
        clock.tick(-1);
        clock.tick(double.nan);

        expect(counter.total, 0);
        expect(clock.now, Duration.zero);
      },
    );

    test('lets go of what says it has come to rest, and is then idle', () {
      final counter = _Counter(3);
      clock.attach(counter);
      expect(clock.isTicking, isTrue);

      clock.advance(const Duration(seconds: 1));

      expect(counter.seen, 3);
      expect(clock.attachedCount, 0);
      expect(clock.isTicking, isFalse);
    });

    test('attaching the same thing twice runs it once a frame', () {
      final counter = _Counter(100);
      clock.attach(counter);
      clock.attach(counter);

      clock.tick();

      expect(counter.seen, 1);
      expect(clock.attachedCount, 1);
    });

    test('a detached thing is not run', () {
      final counter = _Counter(100);
      clock.attach(counter);
      clock.detach(counter);

      clock.tick();

      expect(counter.seen, 0);
    });

    test('time only moves forward, and keeps going after a rest', () {
      final first = _Counter(1);
      clock.attach(first);
      clock.tick(0.02);
      expect(clock.attachedCount, 0);

      clock.attach(_Counter(1));
      clock.tick(0.02);

      expect(clock.now, const Duration(milliseconds: 40));
    });

    test('advance runs whole frames of 1/60 s, and then the remainder', () {
      final counter = _Counter(1000);
      clock.attach(counter);

      clock.advance(const Duration(milliseconds: 110));

      expect(counter.total, closeTo(0.11, 1e-6));
      expect(counter.seen, 7, reason: 'six frames and a short one');
    });

    test('a thing may attach another while it is being run', () {
      final late = _Counter(100);
      final adder = _Adder(clock, late);
      clock.attach(adder);

      clock.tick();

      expect(late.seen, 0, reason: 'it waits for the next frame');
      clock.tick();
      expect(late.seen, 1);
    });

    test('a thing may detach another while it is being run', () {
      final victim = _Counter(100);
      final remover = _Remover(clock, victim);
      clock.attach(victim);
      clock.attach(remover);

      clock.tick();
      clock.tick();

      expect(victim.seen, lessThanOrEqualTo(1));
      expect(clock.attachedCount, lessThanOrEqualTo(2));
    });

    test('dispose lets go of everything', () {
      clock.attach(_Counter(100));

      clock.dispose();

      expect(clock.attachedCount, 0);
    });
  });

  group('VsyncMotionClock', () {
    testWidgets(
      'ticks on vsync while something is attached, and stops when it rests',
      (tester) async {
        final clock = VsyncMotionClock();
        addTearDown(clock.dispose);
        expect(clock.isTicking, isFalse);

        final counter = _Counter(5);
        clock.attach(counter);
        expect(clock.isTicking, isTrue);

        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(counter.seen, 5);
        expect(clock.isTicking, isFalse);
        expect(
          tester.binding.hasScheduledFrame,
          isFalse,
          reason: 'a rested clock asks for no frames',
        );
      },
    );

    testWidgets('time follows the frames', (tester) async {
      final clock = VsyncMotionClock();
      addTearDown(clock.dispose);
      final counter = _Counter(1000);
      clock.attach(counter);

      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(clock.now.inMilliseconds, closeTo(160, 1));
      clock.detach(counter);
    });

    testWidgets('a stalled frame counts as 50 ms', (tester) async {
      final clock = VsyncMotionClock();
      addTearDown(clock.dispose);
      final counter = _Counter(1000);
      clock.attach(counter);

      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(clock.now, const Duration(milliseconds: 50));
      clock.detach(counter);
    });

    testWidgets(
      'slow motion slows it: timeDilation of 4 makes time run at a quarter',
      (tester) async {
        final clock = VsyncMotionClock();
        addTearDown(clock.dispose);
        final counter = _Counter(1000);
        clock.attach(counter);
        timeDilation = 4;
        try {
          await tester.pump();
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          // 320 ms of wall time, at a quarter speed.
          expect(clock.now.inMilliseconds, closeTo(80, 8));
        } finally {
          timeDilation = 1;
        }
        clock.detach(counter);
      },
    );

    testWidgets('a spring on it moves, and rests', (tester) async {
      final clock = VsyncMotionClock();
      addTearDown(clock.dispose);
      final spring = SpringValue(clock: clock, spec: TapeSprings.gauge)
        ..retarget(10);
      addTearDown(spring.dispose);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(spring.value, inExclusiveRange(0, 10));

      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(spring.value, 10);
      expect(clock.isTicking, isFalse);
    });
  });
}

class _Adder implements MotionDriven {
  _Adder(this.clock, this.other);

  final MotionClock clock;
  final MotionDriven other;

  @override
  bool advance(double dt, Duration time) {
    clock.attach(other);
    return false;
  }
}

class _Remover implements MotionDriven {
  _Remover(this.clock, this.victim);

  final MotionClock clock;
  final MotionDriven victim;

  @override
  bool advance(double dt, Duration time) {
    clock.detach(victim);
    return true;
  }
}
