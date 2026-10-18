import 'dart:math' as math;

import '../trips/trip.dart';

/// The gearbox, found from the driving (Gearbox, found): with the clutch in and a
/// gear chosen, revs and speed keep a fixed ratio, so each gear is a straight
/// line of rpm against km/h. Plot a few drives and the lines show as crowds of dots
/// at a few ratios. On a CVT there are no such ratios: the dots make a fan.
///
/// No gear sensor, no setup. An estimate of the *number* of gears it can see.
class Gearbox {
  Gearbox._(this.ratios, this.isFan, this.points, this.observed);

  /// The width of a bin of ratios, in rpm for each km/h.
  static const double binWidth = 2;

  /// The least speed, and the least revs, that a moment needs to say anything.
  static const double minKmh = 12;
  static const double minRpm = 1000;

  /// The fewest moments a crowd needs, and the share of all moments it needs to
  /// be a gear and not a stray.
  static const int minCrowd = 40;
  static const double minShare = 0.008;

  /// A moment is sweeping if the speed changed by this much in two seconds, and
  /// there have to be this many of them, this share of them near a gear's ratio,
  /// before the sweep says anything.
  static const double sweepKmh = 2;
  static const int minSweeping = 100;
  static const double minSweepNear = 0.5;

  /// How many times the usual bin a crowd's tallest bin must be.
  static const double crowdOverMedian = 3;

  /// The ratios found, in rpm per km/h, from the tallest gear (lowest ratio) to
  /// the shortest. Empty for a fan.
  final List<double> ratios;

  /// Whether the dots spread across the ratios (a CVT) and not into crowds.
  final bool isFan;

  /// Every moment used, as (km/h, rpm).
  final List<(double, double)> points;

  /// How many moments there were.
  final int observed;

  int get gears => ratios.length;

  bool get isEmpty => observed == 0;

  /// The gear number (1 is the shortest) for a moment, or null on a fan, with
  /// nothing found, or when the ratio is not near any gear's.
  int? gearFor(double speedKmh, double rpm) {
    if (isFan || ratios.isEmpty || speedKmh < minKmh) return null;
    final r = rpm / speedKmh;
    var best = -1;
    var gap = double.infinity;
    for (var i = 0; i < ratios.length; i++) {
      final g = (ratios[i] - r).abs();
      if (g < gap) {
        gap = g;
        best = i;
      }
    }
    if (best < 0 || gap > binWidth * 1.5) return null;
    return ratios.length - best;
  }

  factory Gearbox.from(Iterable<List<TripSample>> trips) {
    final points = <(double, double)>[];
    final counts = <int, int>{};
    // The ratios of the moments the speed was changing, which tell a gearbox from
    // a CVT: a gear holds its ratio as the speed climbs, a CVT lets it fall.
    final sweeping = <double>[];
    for (final samples in trips) {
      for (var i = 0; i < samples.length; i++) {
        final s = samples[i];
        // Pulling or cruising, not idling or coasting down with the fuel cut: the
        // clutch is the thing, and a coast keeps the ratio too, but a stop does not.
        if (s.speedKmh < minKmh || s.rpm < minRpm) continue;
        points.add((s.speedKmh, s.rpm));
        final bin = (s.rpm / s.speedKmh / binWidth).floor();
        counts[bin] = (counts[bin] ?? 0) + 1;
        if (i >= 2 &&
            samples[i].seconds - samples[i - 2].seconds <= 3 &&
            (s.speedKmh - samples[i - 2].speedKmh).abs() >= sweepKmh) {
          sweeping.add(s.rpm / s.speedKmh);
        }
      }
    }
    if (points.isEmpty) return Gearbox._(const [], false, const [], 0);
    final total = points.length;
    // A crowd is a bin that is the tallest among its neighbours, with enough in it
    // (and its neighbours, for a gear's ratio drifts a little with tyre slip).
    final peaks = <int>[];
    final keys = counts.keys.toList()..sort();
    // A gear is a crowd that stands well above the usual bin; on a CVT every bin
    // holds about as many as any other, and nothing does.
    // The usual bin is counted over the whole range of ratios, the empty bins
    // included: gears leave most of it empty, and a fan fills all of it.
    final sorted = [
      for (var k = keys.first; k <= keys.last; k++) counts[k] ?? 0,
    ]..sort();
    final median = sorted[sorted.length ~/ 2];
    for (final k in keys) {
      final here = counts[k]!;
      if (here < median * crowdOverMedian) continue;
      // And a spike: well above the bins a few away on at least one side. On a
      // fan both sides are as full as the middle.
      var left = 0, right = 0;
      for (final d in [3, 4, 5, 6]) {
        left += counts[k - d] ?? 0;
        right += counts[k + d] ?? 0;
      }
      if (here < crowdOverMedian * math.min(left, right) / 4) continue;
      final crowd = here + (counts[k - 1] ?? 0) + (counts[k + 1] ?? 0);
      if (crowd < minCrowd || crowd / total < minShare) continue;
      if (here < (counts[k - 1] ?? 0) || here < (counts[k + 1] ?? 0)) continue;
      // Two next-door bins of the same height are one crowd, not two.
      if (peaks.isNotEmpty && k - peaks.last <= 1) continue;
      peaks.add(k);
    }
    final ratios = <double>[];
    for (final k in peaks) {
      var weighted = 0.0, n = 0;
      for (final j in [k - 1, k, k + 1]) {
        final c = counts[j] ?? 0;
        weighted += c * (j + 0.5) * binWidth;
        n += c;
      }
      ratios.add(weighted / n);
    }
    // The share of moments within a gear's ratio: a gearbox puts nearly all of
    // them there, and a CVT only a few.
    var near = 0;
    for (final p in points) {
      final r = p.$2 / p.$1;
      if (ratios.any((g) => (g - r).abs() <= binWidth * 1.5)) near++;
    }
    // And while the speed is changing: a gearbox's moments stay at its ratios.
    final sweepNear = sweeping
        .where((r) => ratios.any((g) => (g - r).abs() <= binWidth * 1.5))
        .length;
    final cvt =
        sweeping.length >= minSweeping &&
        sweepNear / sweeping.length < minSweepNear;
    final fan = ratios.length < 2 || near / total < 0.55 || cvt;
    return Gearbox._(fan ? const [] : ratios, fan, points, total);
  }

  /// The share of the ratio range the dots cover; for a test of the fan.
  static double spread(List<(double, double)> points) {
    if (points.isEmpty) return 0;
    var lo = double.infinity, hi = 0.0;
    for (final p in points) {
      final r = p.$2 / p.$1;
      lo = math.min(lo, r);
      hi = math.max(hi, r);
    }
    return hi - lo;
  }
}
