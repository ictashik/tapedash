import 'dart:math' as math;

import 'trip.dart';

/// A route ready to draw (DESIGN.md 6.12): the fixes of a trip, projected,
/// downsampled to what fits on a screen, with the metric of each point.
///
/// **Projection:** equirectangular, `x = lon * cos(lat0)`, `y = lat`, north up,
/// fitted to the panel with 8% padding on every side, and never stretched: a
/// route keeps its shape. Points are then in the panel's own coordinates, y down.
class RouteGeometry {
  RouteGeometry._({
    required this.xs,
    required this.ys,
    required this.sampleIndex,
    required this.lengthMetres,
    required this.unitsPerMetre,
  });

  /// The points, in the panel's coordinates, and which sample each came from.
  final List<double> xs;
  final List<double> ys;
  final List<int> sampleIndex;

  /// The whole route's length, in metres, as drawn.
  final double lengthMetres;

  /// How many of the panel's units a metre of the route is at the whole-route view:
  /// what turns a distance on the ground into one on the panel.
  final double unitsPerMetre;

  int get length => xs.length;

  static const double padding = 0.08;
  static const int maxPoints = 1000;
  static const double _metresPerDegree = 111320;

  /// The route of [samples], fitted to [width] by [height], or null if fewer than
  /// two of them have a position. Points closer than a metre to the last kept are
  /// dropped (a parked car scatters fixes), then the rest are thinned evenly to
  /// [maxPoints].
  static RouteGeometry? build(
    List<TripSample> samples,
    double width,
    double height, {
    int maxPoints = RouteGeometry.maxPoints,
  }) {
    final index = <int>[];
    for (var i = 0; i < samples.length; i++) {
      if (samples[i].latitude != null && samples[i].longitude != null) {
        index.add(i);
      }
    }
    if (index.length < 2) return null;
    final lat0 =
        index.map((i) => samples[i].latitude!).reduce((a, b) => a + b) /
        index.length;
    final k = math.cos(lat0 * math.pi / 180);

    // Project, and drop the points that have not moved.
    final px = <double>[];
    final py = <double>[];
    final kept = <int>[];
    for (final i in index) {
      final x = samples[i].longitude! * k * _metresPerDegree;
      final y = samples[i].latitude! * _metresPerDegree;
      if (px.isNotEmpty) {
        final dx = x - px.last;
        final dy = y - py.last;
        if (dx * dx + dy * dy < 1) continue;
      }
      px.add(x);
      py.add(y);
      kept.add(i);
    }
    if (px.length < 2) return null;

    // Thin evenly, keeping the first and last.
    if (px.length > maxPoints) {
      final step = (px.length - 1) / (maxPoints - 1);
      final tx = <double>[], ty = <double>[];
      final ti = <int>[];
      for (var n = 0; n < maxPoints; n++) {
        final j = (n * step).round();
        tx.add(px[j]);
        ty.add(py[j]);
        ti.add(kept[j]);
      }
      px
        ..clear()
        ..addAll(tx);
      py
        ..clear()
        ..addAll(ty);
      kept
        ..clear()
        ..addAll(ti);
    }

    var minX = px.first, maxX = px.first, minY = py.first, maxY = py.first;
    var total = 0.0;
    for (var n = 0; n < px.length; n++) {
      minX = math.min(minX, px[n]);
      maxX = math.max(maxX, px[n]);
      minY = math.min(minY, py[n]);
      maxY = math.max(maxY, py[n]);
      if (n > 0) {
        total += math.sqrt(
          math.pow(px[n] - px[n - 1], 2) + math.pow(py[n] - py[n - 1], 2),
        );
      }
    }
    final spanX = math.max(maxX - minX, 1);
    final spanY = math.max(maxY - minY, 1);
    final availW = width * (1 - 2 * padding);
    final availH = height * (1 - 2 * padding);
    final scale = math.min(availW / spanX, availH / spanY);
    final offX = (width - spanX * scale) / 2;
    final offY = (height - spanY * scale) / 2;
    return RouteGeometry._(
      xs: [for (final x in px) offX + (x - minX) * scale],
      // North is up: y grows southwards on the screen.
      ys: [for (final y in py) offY + (maxY - y) * scale],
      sampleIndex: kept,
      lengthMetres: total,
      unitsPerMetre: scale,
    );
  }

  /// The share of the route, 0 to 1, at each point, by distance along it: what
  /// the draw-on and the comet head move by.
  List<double> get progress {
    final out = List<double>.filled(length, 0);
    var run = 0.0;
    for (var n = 1; n < length; n++) {
      run += math.sqrt(
        math.pow(xs[n] - xs[n - 1], 2) + math.pow(ys[n] - ys[n - 1], 2),
      );
      out[n] = run;
    }
    final last = out.last;
    if (last <= 0) return out;
    return [for (final v in out) v / last];
  }

  /// The point nearest to the panel position ([x], [y]), and how far it is from it
  /// in panel units: what a tap on the route picks.
  ({int point, double distance}) nearestTo(double x, double y) {
    var best = 0;
    var bestSq = double.infinity;
    for (var n = 0; n < xs.length; n++) {
      final dx = xs[n] - x;
      final dy = ys[n] - y;
      final sq = dx * dx + dy * dy;
      if (sq < bestSq) {
        bestSq = sq;
        best = n;
      }
    }
    return (point: best, distance: math.sqrt(bestSq));
  }

  /// The point nearest to sample [i] (the scrubber's position dot).
  int nearestPoint(int i) {
    var best = 0;
    var bestGap = 1 << 30;
    for (var n = 0; n < sampleIndex.length; n++) {
      final gap = (sampleIndex[n] - i).abs();
      if (gap < bestGap) {
        bestGap = gap;
        best = n;
      }
    }
    return best;
  }

  /// Where a car is on the route at fractional [sample] of the trip: a fractional
  /// index into the points, for [xAt], [yAt] and [headingAt].
  ///
  /// Between two points the car is placed by the distance it had covered ([km] is
  /// the trip's odometer at a fractional sample), not by the time, so that it
  /// stands still while the car did: points a stopped car scattered were dropped,
  /// and a stop must not make it creep. Where the odometer did not move between two
  /// points at all (a GPS that wandered) it goes by the time instead, so it never
  /// jumps.
  double pointAt(double sample, double Function(double sample) km) {
    final last = sampleIndex.length - 1;
    if (last <= 0 || sample <= sampleIndex.first) return 0;
    if (sample >= sampleIndex[last]) return last.toDouble();
    // The last point at or before the sample.
    var lo = 0, hi = last;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (sampleIndex[mid] <= sample) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final s0 = sampleIndex[lo].toDouble();
    final s1 = sampleIndex[lo + 1].toDouble();
    final d0 = km(s0);
    final d1 = km(s1);
    final share = d1 - d0 > 1e-6
        ? (km(sample) - d0) / (d1 - d0)
        : (sample - s0) / (s1 - s0);
    return lo + share.clamp(0.0, 1.0);
  }

  /// The position at fractional point [p], on the panel.
  double xAt(double p) {
    final i = p.floor().clamp(0, length - 1);
    if (i >= length - 1) return xs[length - 1];
    return xs[i] + (xs[i + 1] - xs[i]) * (p - i).clamp(0.0, 1.0);
  }

  double yAt(double p) {
    final i = p.floor().clamp(0, length - 1);
    if (i >= length - 1) return ys[length - 1];
    return ys[i] + (ys[i + 1] - ys[i]) * (p - i).clamp(0.0, 1.0);
  }

  /// The way the route is heading at fractional point [p], in radians on the
  /// panel (0 is to the right, and y is down, so a quarter turn is down the
  /// screen): the direction from [span] points behind to [span] points ahead, so
  /// that a corner turns it over a few points and a scatter of GPS does not jerk
  /// it. [previous] is returned where the route has no direction there (it stood
  /// still).
  double headingAt(double p, {double span = 2, double previous = 0}) {
    final a = (p - span).clamp(0.0, (length - 1).toDouble());
    final b = (p + span).clamp(0.0, (length - 1).toDouble());
    final dx = xAt(b) - xAt(a);
    final dy = yAt(b) - yAt(a);
    if (dx * dx + dy * dy < 1e-9) return previous;
    return math.atan2(dy, dx);
  }
}
