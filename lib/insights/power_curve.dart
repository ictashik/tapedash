import 'dart:math' as math;

import '../trips/trip.dart';
import 'insight_constants.dart';
import 'wheel_power.dart';

/// One dot of the power curve: wheel power at some revs, and the throttle then.
class PowerDot {
  const PowerDot(this.rpm, this.kw, this.throttle);
  final double rpm;
  final double kw;
  final double throttle;
}

/// A dyno chart from ordinary driving (Power curve): every moment the engine was
/// pulling is a dot of wheel power against revs, and the highest the dots reach at
/// each rev is the edge of what the car has shown it can do.
///
/// An estimate. Revs the car has never been taken to have no dots, and the chart
/// says so rather than draw a line across them.
class PowerCurve {
  PowerCurve._(this.dots, this.edge, this.highest, this.coveredRpm);

  /// The width of an rpm bin.
  static const double binRpm = 200;

  /// Dots under this many kW are the engine barely pulling, and say nothing.
  static const double minKw = 1.5;

  /// The fewest dots a bin needs to give a point of the edge.
  static const int minDotsPerBin = 4;

  final List<PowerDot> dots;

  /// The upper edge: the 95th percentile of each bin's dots, smoothed, as
  /// (rpm, kW) from the lowest bin with data to the highest.
  final List<(double, double)> edge;

  /// The highest wheel power seen, and the revs it was seen at: the peak of the
  /// edge, which a single bad reading cannot make.
  final PowerDot? highest;

  /// The highest revs the car has been taken to while pulling.
  final double coveredRpm;

  bool get isEmpty => dots.isEmpty;

  factory PowerCurve.from(
    Iterable<List<TripSample>> trips, {
    InsightConstants constants = const InsightConstants(),
  }) {
    final dots = <PowerDot>[];
    for (final samples in trips) {
      for (final m in WheelPower.moments(samples, constants: constants)) {
        if (m.tractionKw < minKw || m.rpm < 800 || m.speedKmh < 5) continue;
        dots.add(PowerDot(m.rpm, m.tractionKw, m.throttle));
      }
    }
    final bins = <int, List<double>>{};
    for (final d in dots) {
      bins.putIfAbsent((d.rpm / binRpm).floor(), () => []).add(d.kw);
    }
    final keys = [
      for (final k in bins.keys)
        if (bins[k]!.length >= minDotsPerBin) k,
    ]..sort();
    final raw = <(double, double)>[];
    for (final k in keys) {
      final v = bins[k]!..sort();
      final p = v[math.min(v.length - 1, (v.length * 0.95).floor())];
      raw.add(((k + 0.5) * binRpm, p));
    }
    // A three-bin average, so that one lucky bin does not make a spike.
    final edge = <(double, double)>[];
    for (var i = 0; i < raw.length; i++) {
      final a = raw[math.max(0, i - 1)].$2;
      final b = raw[i].$2;
      final c = raw[math.min(raw.length - 1, i + 1)].$2;
      edge.add((raw[i].$1, (a + b + c) / 3));
    }
    // The highest is the peak of the edge, not the single highest dot: one wrong
    // speed reading makes one absurd dot, and a headline must not stand on it.
    PowerDot? highest;
    for (final (rpm, kw) in edge) {
      if (highest == null || kw > highest.kw) highest = PowerDot(rpm, kw, 0);
    }
    final covered = dots.fold<double>(0, (m, d) => math.max(m, d.rpm));
    return PowerCurve._(dots, edge, highest, covered);
  }
}
