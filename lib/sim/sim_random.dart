import 'dart:math' as math;

/// A small deterministic random source for the simulator (SplitMix64).
///
/// A seed gives the same numbers on every platform and Dart version, which
/// `dart:math`'s `Random` does not promise. That is what makes a simulated
/// drive, and the recordings made from it, reproducible (CLAUDE.md 7.1).
class SimRandom {
  SimRandom(this.seed) : _state = seed;

  final int seed;
  int _state;
  double? _spareGaussian;

  /// The next 64 random bits.
  int nextInt64() {
    _state += 0x9E3779B97F4A7C15;
    var z = _state;
    z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
    z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
    return z ^ (z >>> 31);
  }

  /// A number from 0 (included) to 1 (excluded), with 53 random bits.
  double nextDouble() => (nextInt64() >>> 11) / 9007199254740992.0;

  /// A whole number from 0 (included) to [max] (excluded).
  int nextInt(int max) {
    if (max <= 0) throw ArgumentError.value(max, 'max', 'must be positive');
    return (nextInt64() >>> 1) % max;
  }

  /// True with the given [probability] from 0 to 1.
  bool chance(double probability) => nextDouble() < probability;

  /// A number from [low] to [high].
  double uniform(double low, double high) => low + (high - low) * nextDouble();

  /// A normally distributed number.
  double nextGaussian({double mean = 0, double standardDeviation = 1}) {
    final spare = _spareGaussian;
    if (spare != null) {
      _spareGaussian = null;
      return mean + standardDeviation * spare;
    }
    // Box-Muller. 1 - u keeps the logarithm's argument above zero.
    final radius = math.sqrt(-2 * math.log(1 - nextDouble()));
    final angle = 2 * math.pi * nextDouble();
    _spareGaussian = radius * math.sin(angle);
    return mean + standardDeviation * radius * math.cos(angle);
  }

  /// An independent stream derived from this seed and a [salt]. Give each part
  /// of the simulator its own, so that one part drawing more numbers (because
  /// it was polled more often, say) never changes what another sees.
  SimRandom fork(int salt) =>
      SimRandom(SimRandom(seed ^ (salt * 0x632BE59B)).nextInt64());
}
