import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/apportion.dart';

void main() {
  test('the first real drive: 24.6 and 3.7 add up to 28, not 29', () {
    expect(apportion([24.6, 3.7, 0, 0]), [24, 4, 0, 0]);
    expect(apportion([24.6, 3.7, 0, 0]).fold<int>(0, (a, b) => a + b), 28);
  });

  test('parts that already round to their total are left alone', () {
    expect(apportion([10.6, 5.6, 1.4, 0.2]), [11, 6, 1, 0]);
  });

  test('the largest remainders get the extra one', () {
    expect(apportion([1.5, 1.5, 1.5, 1.5]), [2, 2, 1, 1]);
  });

  test('every part stays within one of its own rounding', () {
    final values = [33.34, 33.33, 33.33, 0.0];
    final parts = apportion(values);
    expect(parts.fold<int>(0, (a, b) => a + b), 100);
    for (var i = 0; i < values.length; i++) {
      expect((parts[i] - values[i]).abs(), lessThan(1));
    }
  });

  test('a given total is met', () {
    expect(
      apportion([2.4, 2.4, 2.4], total: 8).fold<int>(0, (a, b) => a + b),
      8,
    );
    expect(
      apportion([2.4, 2.4, 2.4], total: 6).fold<int>(0, (a, b) => a + b),
      6,
    );
    expect(apportion([2.9, 0.1], total: 2).fold<int>(0, (a, b) => a + b), 2);
  });

  test('nothing, negative and not-a-number are 0', () {
    expect(apportion([]), <int>[]);
    expect(apportion([0, 0]), [0, 0]);
    expect(apportion([-3, double.nan, 2.6]), [0, 0, 3]);
  });

  test('a sweep: the parts always add up to the rounded total', () {
    var seed = 12345;
    double next() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed / 0x7fffffff;
    }

    for (var n = 0; n < 500; n++) {
      final values = [for (var i = 0; i < 4; i++) next() * 40 * next()];
      final want = values.fold<double>(0, (a, b) => a + b).round();
      final parts = apportion(values);
      expect(parts.fold<int>(0, (a, b) => a + b), want, reason: '$values');
      for (var i = 0; i < 4; i++) {
        expect((parts[i] - values[i]).abs(), lessThan(1), reason: '$values');
      }
    }
  });
}
