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
  });

  /// The points, in the panel's coordinates, and which sample each came from.
  final List<double> xs;
  final List<double> ys;
  final List<int> sampleIndex;

  /// The whole route's length, in metres, as drawn.
  final double lengthMetres;

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
    double height,
  ) {
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
}
