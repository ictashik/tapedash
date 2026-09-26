import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/scheduler.dart';

Duration _ms(int n) => Duration(milliseconds: n);

void main() {
  group('FakeClock as a Scheduler', () {
    late FakeClock clock;

    setUp(() => clock = FakeClock());

    group('runAfter', () {
      test('runs once, at its due time and not before', () {
        var runs = 0;
        clock.runAfter(_ms(100), () => runs++);

        clock.advance(_ms(99));
        expect(runs, 0);

        clock.advance(_ms(1));
        expect(runs, 1);

        clock.advance(const Duration(hours: 1));
        expect(runs, 1);
      });

      test('sees exactly its due time while it runs', () {
        final seen = <Duration>[];
        clock.runAfter(_ms(30), () => seen.add(clock.monotonic()));
        clock.runAfter(_ms(70), () => seen.add(clock.monotonic()));

        clock.advance(_ms(1000));

        expect(seen, [_ms(30), _ms(70)]);
        expect(clock.monotonic(), _ms(1000));
      });

      test('wall time moves with it', () {
        DateTime? seen;
        clock.runAfter(const Duration(minutes: 5), () => seen = clock.now());

        clock.advance(const Duration(minutes: 10));

        expect(seen, DateTime.utc(2026, 1, 1, 0, 5));
      });

      test('runs tasks in due order, whatever order they were added', () {
        final order = <String>[];
        clock.runAfter(_ms(30), () => order.add('c'));
        clock.runAfter(_ms(10), () => order.add('a'));
        clock.runAfter(_ms(20), () => order.add('b'));

        clock.advance(_ms(100));

        expect(order, ['a', 'b', 'c']);
      });

      test('runs tasks due at the same time in the order they were added', () {
        final order = <int>[];
        for (var i = 0; i < 5; i++) {
          clock.runAfter(_ms(10), () => order.add(i));
        }

        clock.advance(_ms(10));

        expect(order, [0, 1, 2, 3, 4]);
      });

      test('a zero delay runs on the next advance, never synchronously', () {
        var ran = false;
        clock.runAfter(Duration.zero, () => ran = true);
        expect(ran, isFalse);

        clock.advance(Duration.zero);

        expect(ran, isTrue);
      });

      test('a negative delay is treated as zero', () {
        Duration? seen;
        clock.advance(_ms(50));
        clock.runAfter(_ms(-20), () => seen = clock.monotonic());

        clock.advance(_ms(5));

        expect(seen, _ms(50));
      });

      test('a task scheduled from a task runs in the same advance if it falls '
          'inside the window', () {
        final seen = <Duration>[];
        clock.runAfter(_ms(10), () {
          seen.add(clock.monotonic());
          clock.runAfter(_ms(15), () => seen.add(clock.monotonic()));
        });

        clock.advance(_ms(100));

        expect(seen, [_ms(10), _ms(25)]);
      });

      test('a task scheduled from a task outside the window waits', () {
        var ran = false;
        clock.runAfter(_ms(10), () {
          clock.runAfter(_ms(100), () => ran = true);
        });

        clock.advance(_ms(50));
        expect(ran, isFalse);
        expect(clock.pendingTasks, 1);

        clock.advance(_ms(60));
        expect(ran, isTrue);
      });

      test('a zero-delay task scheduled from a task runs in the same '
          'advance', () {
        final order = <String>[];
        clock.runAfter(_ms(10), () {
          order.add('first');
          clock.runAfter(Duration.zero, () => order.add('follow-up'));
        });

        clock.advance(_ms(10));

        expect(order, ['first', 'follow-up']);
      });
    });

    group('runEvery', () {
      test('first runs after one period, then every period', () {
        final seen = <Duration>[];
        clock.runEvery(_ms(50), () => seen.add(clock.monotonic()));

        clock.advance(_ms(49));
        expect(seen, isEmpty);

        clock.advance(_ms(200));
        expect(seen, [_ms(50), _ms(100), _ms(150), _ms(200)]);
      });

      test('does not drift across many advances of odd sizes', () {
        final seen = <Duration>[];
        clock.runEvery(_ms(50), () => seen.add(clock.monotonic()));

        for (final step in [7, 93, 1, 149, 50, 3, 97]) {
          clock.advance(_ms(step));
        }

        expect(clock.monotonic(), _ms(400));
        expect(seen, [for (var t = 50; t <= 400; t += 50) _ms(t)]);
      });

      test('a 30 minute drive of 50 ms ticks is 36,000 exact steps', () {
        var ticks = 0;
        clock.runEvery(_ms(50), () => ticks++);

        clock.advance(const Duration(minutes: 30));

        expect(ticks, 36000);
      });

      test('interleaves with one-shot tasks by due time', () {
        final order = <String>[];
        clock.runEvery(_ms(10), () => order.add('tick'));
        clock.runAfter(_ms(25), () => order.add('once'));

        clock.advance(_ms(30));

        expect(order, ['tick', 'tick', 'once', 'tick']);
      });

      test('a periodic and a one-shot task due together run in the order they '
          'were scheduled', () {
        final order = <String>[];
        clock.runEvery(_ms(10), () => order.add('tick'));
        clock.runAfter(_ms(10), () => order.add('once'));

        clock.advance(_ms(10));

        expect(order, ['tick', 'once']);
      });

      test('rejects a zero or negative period', () {
        expect(() => clock.runEvery(Duration.zero, () {}), throwsArgumentError);
        expect(() => clock.runEvery(_ms(-5), () {}), throwsArgumentError);
      });
    });

    group('cancel', () {
      test('before it is due, the task never runs', () {
        var ran = false;
        clock.runAfter(_ms(10), () => ran = true).cancel();

        clock.advance(_ms(100));

        expect(ran, isFalse);
        expect(clock.pendingTasks, 0);
      });

      test('stops a periodic task', () {
        var ticks = 0;
        final task = clock.runEvery(_ms(10), () => ticks++);
        clock.advance(_ms(35));
        expect(ticks, 3);

        task.cancel();
        clock.advance(_ms(100));

        expect(ticks, 3);
      });

      test('a periodic task can cancel itself', () {
        var ticks = 0;
        late ScheduledTask task;
        task = clock.runEvery(_ms(10), () {
          if (++ticks == 3) task.cancel();
        });

        clock.advance(_ms(1000));

        expect(ticks, 3);
        expect(clock.pendingTasks, 0);
      });

      test('a task can cancel another that is due later in the same '
          'advance', () {
        var ran = false;
        final victim = clock.runAfter(_ms(20), () => ran = true);
        clock.runAfter(_ms(10), victim.cancel);

        clock.advance(_ms(100));

        expect(ran, isFalse);
      });

      test('a task can cancel another that is due at the same time', () {
        final order = <String>[];
        late ScheduledTask second;
        clock.runAfter(_ms(10), () {
          order.add('first');
          second.cancel();
        });
        second = clock.runAfter(_ms(10), () => order.add('second'));

        clock.advance(_ms(10));

        expect(order, ['first']);
      });

      test('is safe to call twice and after the task has run', () {
        final task = clock.runAfter(_ms(10), () {});
        clock.advance(_ms(10));

        task
          ..cancel()
          ..cancel();

        expect(clock.pendingTasks, 0);
      });
    });

    group('isActive', () {
      test('is true until a one-shot task starts running', () {
        late ScheduledTask task;
        bool? insideTask;
        task = clock.runAfter(_ms(10), () => insideTask = task.isActive);
        expect(task.isActive, isTrue);

        clock.advance(_ms(10));

        expect(insideTask, isFalse);
        expect(task.isActive, isFalse);
      });

      test('stays true for a periodic task until it is cancelled', () {
        final task = clock.runEvery(_ms(10), () {});
        clock.advance(_ms(100));
        expect(task.isActive, isTrue);

        task.cancel();

        expect(task.isActive, isFalse);
      });

      test('is false after cancel', () {
        final task = clock.runAfter(_ms(10), () {});

        task.cancel();

        expect(task.isActive, isFalse);
      });
    });

    group('advance', () {
      test('cannot be called from inside a task', () {
        Object? error;
        clock.runAfter(_ms(10), () {
          try {
            clock.advance(_ms(1));
          } on StateError catch (e) {
            error = e;
          }
        });

        clock.advance(_ms(10));

        expect(error, isA<StateError>());
      });

      test('an error in a task propagates, and time stays at that task', () {
        clock.runAfter(_ms(10), () => throw StateError('boom'));
        var later = false;
        clock.runAfter(_ms(50), () => later = true);

        expect(() => clock.advance(_ms(100)), throwsStateError);

        expect(clock.monotonic(), _ms(10));
        expect(later, isFalse);
        expect(clock.pendingTasks, 1);

        clock.advance(_ms(100));
        expect(later, isTrue);
      });

      test('a periodic task keeps running after one of its runs throws', () {
        var ticks = 0;
        clock.runEvery(_ms(10), () {
          if (++ticks == 2) throw StateError('boom');
        });

        expect(() => clock.advance(_ms(100)), throwsStateError);
        clock.advance(_ms(100));

        expect(ticks, greaterThan(2));
      });

      test('can be used again after an error', () {
        clock.runAfter(_ms(10), () => throw StateError('boom'));
        expect(() => clock.advance(_ms(10)), throwsStateError);

        expect(() => clock.advance(_ms(10)), returnsNormally);
      });
    });
  });

  group('SystemScheduler', () {
    const scheduler = SystemScheduler();

    test('runAfter runs the task once', () async {
      var runs = 0;
      final ran = Completer<void>();
      scheduler.runAfter(_ms(10), () {
        runs++;
        ran.complete();
      });

      await ran.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(_ms(50));

      expect(runs, 1);
    });

    test('runAfter with a zero delay is not synchronous', () async {
      var ran = false;
      final done = Completer<void>();
      scheduler.runAfter(Duration.zero, () {
        ran = true;
        done.complete();
      });
      expect(ran, isFalse);

      await done.future.timeout(const Duration(seconds: 5));

      expect(ran, isTrue);
    });

    test('cancel stops a task before it runs', () async {
      var ran = false;
      scheduler.runAfter(_ms(20), () => ran = true).cancel();

      await Future<void>.delayed(_ms(80));

      expect(ran, isFalse);
    });

    test('runEvery repeats until cancelled', () async {
      var ticks = 0;
      final enough = Completer<void>();
      late ScheduledTask task;
      task = scheduler.runEvery(_ms(5), () {
        if (++ticks == 3) {
          task.cancel();
          enough.complete();
        }
      });

      await enough.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(_ms(50));

      expect(ticks, 3);
      expect(task.isActive, isFalse);
    });

    test('isActive is false inside a one-shot task and after it', () async {
      late ScheduledTask task;
      bool? inside;
      final done = Completer<void>();
      task = scheduler.runAfter(_ms(5), () {
        inside = task.isActive;
        done.complete();
      });
      expect(task.isActive, isTrue);

      await done.future.timeout(const Duration(seconds: 5));

      expect(inside, isFalse);
      expect(task.isActive, isFalse);
    });

    test('rejects a zero or negative period', () {
      expect(
        () => scheduler.runEvery(Duration.zero, () {}),
        throwsArgumentError,
      );
      expect(() => scheduler.runEvery(_ms(-1), () {}), throwsArgumentError);
    });
  });
}
