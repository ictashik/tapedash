/// How far the fuel estimate has been checked against real fill-ups (CLAUDE.md
/// 8.5).
enum CalibrationConfidence { uncalibrated, calibrating, calibrated }

/// The correction between what the app estimated and what the tank took
/// (CLAUDE.md 8.5): between two full-tank fill-ups, `litres actually filled /
/// litres estimated`. The correction applied to every estimate is the average of
/// the last three, kept within 0.7 to 1.3.
class Calibration {
  Calibration([Iterable<double> factors = const []]) {
    factors.forEach(add);
  }

  static const int keep = 3;
  static const double minFactor = 0.7;
  static const double maxFactor = 1.3;

  final List<double> _factors = [];

  /// The factors in use, oldest first: the last [keep].
  List<double> get factors => List.unmodifiable(_factors);

  /// Adds the factor from a fill-up.
  void add(double factor) {
    if (!factor.isFinite || factor <= 0) return;
    _factors.add(factor);
    if (_factors.length > keep) _factors.removeAt(0);
  }

  /// What to multiply every fuel estimate by: 1 with nothing to go on.
  double get factor {
    if (_factors.isEmpty) return 1;
    final mean = _factors.reduce((a, b) => a + b) / _factors.length;
    return mean.clamp(minFactor, maxFactor);
  }

  /// No factor yet, one, or two or more.
  CalibrationConfidence get confidence => switch (_factors.length) {
    0 => CalibrationConfidence.uncalibrated,
    1 => CalibrationConfidence.calibrating,
    _ => CalibrationConfidence.calibrated,
  };
}
