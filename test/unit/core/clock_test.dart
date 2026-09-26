import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/clock.dart';
import 'package:tapedash/core/fake_clock.dart';

void main() {
  group('SystemClock', () {
    test('now() is the real wall clock', () {
      final before = DateTime.now();
      final now = const SystemClock().now();
      final after = DateTime.now();

      expect(now.isBefore(before), isFalse);
      expect(now.isAfter(after), isFalse);
    });

    test('monotonic() never runs backwards', () {
      const clock = SystemClock();
      var previous = clock.monotonic();
      for (var i = 0; i < 1000; i++) {
        final next = clock.monotonic();
        expect(next, greaterThanOrEqualTo(previous));
        previous = next;
      }
    });

    test('instances share one origin', () {
      final a = const SystemClock().monotonic();
      final b = const SystemClock().monotonic();

      expect(b, greaterThanOrEqualTo(a));
    });
  });

  group('FakeClock', () {
    test('starts at a fixed instant by default, so runs are reproducible', () {
      expect(FakeClock().now(), DateTime.utc(2026));
      expect(FakeClock().monotonic(), Duration.zero);
    });

    test('starts at the given time', () {
      final start = DateTime.utc(2030, 6, 15, 9, 30);

      expect(FakeClock(start: start).now(), start);
    });

    test('time only moves when advanced', () {
      final clock = FakeClock();

      expect(clock.now(), clock.now());
      expect(clock.monotonic(), Duration.zero);

      clock.advance(const Duration(seconds: 90));

      expect(clock.now(), DateTime.utc(2026, 1, 1, 0, 1, 30));
      expect(clock.monotonic(), const Duration(seconds: 90));
    });

    test('advancing by zero changes nothing', () {
      final clock = FakeClock()..advance(Duration.zero);

      expect(clock.monotonic(), Duration.zero);
    });

    test('rejects advancing backwards', () {
      expect(
        () => FakeClock().advance(const Duration(milliseconds: -1)),
        throwsArgumentError,
      );
    });

    test('a wall-clock adjustment leaves monotonic time alone', () {
      final clock = FakeClock()..advance(const Duration(minutes: 1));

      clock.adjustWallClock(const Duration(hours: -3));

      expect(clock.now(), DateTime.utc(2025, 12, 31, 21, 1));
      expect(clock.monotonic(), const Duration(minutes: 1));
    });

    test('a wall-clock adjustment does not move scheduled tasks', () {
      final clock = FakeClock();
      var ran = false;
      clock.runAfter(const Duration(seconds: 10), () => ran = true);

      clock.adjustWallClock(const Duration(days: 30));
      clock.advance(const Duration(seconds: 9));
      expect(ran, isFalse);

      clock.advance(const Duration(seconds: 1));
      expect(ran, isTrue);
    });
  });
}
