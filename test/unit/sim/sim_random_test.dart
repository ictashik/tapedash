import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/sim/sim_random.dart';

void main() {
  group('the sequence', () {
    // From an independent SplitMix64 written in Python.
    test('matches the reference implementation', () {
      expect(_first(0, 3), [
        0xe220a8397b1dcdaf,
        0x6e789e6aa1b965f4,
        0x06c45d188009454f,
      ]);
      expect(_first(42, 3), [
        0xbdd732262feb6e95,
        0x28efe333b266f103,
        0x47526757130f9f52,
      ]);
      expect(_first(1234567, 3), [
        0x599ed017fb08fc85,
        0x2c73f08458540fa5,
        0x883ebce5a3f27c77,
      ]);
    });

    test('nextDouble uses the top 53 bits', () {
      final random = SimRandom(7);

      expect(random.nextDouble(), closeTo(0.3898297483912715, 1e-15));
      expect(random.nextDouble(), closeTo(0.01678829452815611, 1e-15));
      expect(random.nextDouble(), closeTo(0.9007606806068834, 1e-15));
    });

    test('is the same every time for a seed, and different for another', () {
      List<double> run(int seed) {
        final random = SimRandom(seed);
        return List.generate(50, (_) => random.nextDouble());
      }

      expect(run(1), run(1));
      expect(run(1), isNot(run(2)));
    });
  });

  group('ranges', () {
    test('nextDouble stays in [0, 1)', () {
      final random = SimRandom(3);
      for (var i = 0; i < 10000; i++) {
        final v = random.nextDouble();
        expect(v, greaterThanOrEqualTo(0));
        expect(v, lessThan(1));
      }
    });

    test('nextInt stays in range and reaches every value', () {
      final random = SimRandom(4);
      final seen = <int>{};
      for (var i = 0; i < 2000; i++) {
        final v = random.nextInt(6);
        expect(v, inInclusiveRange(0, 5));
        seen.add(v);
      }
      expect(seen, {0, 1, 2, 3, 4, 5});
    });

    test('nextInt rejects a non-positive limit', () {
      expect(() => SimRandom(1).nextInt(0), throwsArgumentError);
      expect(() => SimRandom(1).nextInt(-3), throwsArgumentError);
    });

    test('uniform stays between its limits', () {
      final random = SimRandom(5);
      for (var i = 0; i < 1000; i++) {
        expect(random.uniform(-2, 3), inInclusiveRange(-2, 3));
      }
    });

    test('chance is false at 0 and true at 1', () {
      final random = SimRandom(6);
      for (var i = 0; i < 100; i++) {
        expect(random.chance(0), isFalse);
        expect(random.chance(1), isTrue);
      }
    });

    test('chance matches its probability', () {
      final random = SimRandom(8);
      final hits = List.generate(
        20000,
        (_) => random.chance(0.25),
      ).where((b) => b).length;

      expect(hits / 20000, closeTo(0.25, 0.01));
    });
  });

  group('nextGaussian', () {
    test('has the requested mean and spread', () {
      final random = SimRandom(9);
      final values = List.generate(
        40000,
        (_) => random.nextGaussian(mean: 5, standardDeviation: 2),
      );
      final mean = values.reduce((a, b) => a + b) / values.length;
      final variance =
          values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
          values.length;

      expect(mean, closeTo(5, 0.05));
      expect(variance, closeTo(4, 0.15));
    });

    test('never returns NaN or infinity', () {
      final random = SimRandom(10);
      for (var i = 0; i < 20000; i++) {
        expect(random.nextGaussian().isFinite, isTrue);
      }
    });
  });

  group('fork', () {
    test('gives the same stream for the same salt', () {
      final a = SimRandom(11).fork(1);
      final b = SimRandom(11).fork(1);

      expect(
        List.generate(20, (_) => a.nextInt64()),
        List.generate(20, (_) => b.nextInt64()),
      );
    });

    test('gives different streams for different salts or seeds', () {
      List<int> take(SimRandom r) => List.generate(10, (_) => r.nextInt64());

      expect(take(SimRandom(11).fork(1)), isNot(take(SimRandom(11).fork(2))));
      expect(take(SimRandom(11).fork(1)), isNot(take(SimRandom(12).fork(1))));
    });

    test('is not affected by draws from the parent', () {
      final parent = SimRandom(13);
      final before = parent.fork(3);
      for (var i = 0; i < 100; i++) {
        parent.nextDouble();
      }
      final after = parent.fork(3);

      expect(after.nextInt64(), before.nextInt64());
    });
  });
}

List<int> _first(int seed, int count) {
  final random = SimRandom(seed);
  return List.generate(count, (_) => random.nextInt64());
}
