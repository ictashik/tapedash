import 'dart:math' as math;

import '../trips/trip.dart';

/// A place on the earth, as a latitude and longitude in degrees.
class GeoPoint {
  const GeoPoint(this.lat, this.lon);
  final double lat;
  final double lon;

  static const double metresPerDegree = 111320;

  /// The distance to [other] in metres, on a flat earth: right to a fraction of a
  /// percent over the few kilometres of a trip.
  double metresTo(GeoPoint other) {
    final dy = (other.lat - lat) * metresPerDegree;
    final dx =
        (other.lon - lon) *
        metresPerDegree *
        math.cos((lat + other.lat) / 2 * math.pi / 180);
    return math.sqrt(dx * dx + dy * dy);
  }
}

/// The route of a trip: the samples that had a fix, in order.
List<(TripSample, GeoPoint)> routeOf(List<TripSample> samples) => [
  for (final s in samples)
    if (s.latitude != null && s.longitude != null)
      (s, GeoPoint(s.latitude!, s.longitude!)),
];

/// [count] points spaced evenly along the length of [route], for comparing the
/// shape of two routes that were sampled at different times.
List<GeoPoint> resample(List<GeoPoint> route, int count) {
  if (route.length < 2 || count < 2) return List.of(route);
  final along = <double>[0];
  for (var i = 1; i < route.length; i++) {
    along.add(along.last + route[i - 1].metresTo(route[i]));
  }
  final total = along.last;
  if (total <= 0) return List.of(route);
  final out = <GeoPoint>[];
  var j = 0;
  for (var k = 0; k < count; k++) {
    final at = total * k / (count - 1);
    while (j < route.length - 2 && along[j + 1] < at) {
      j++;
    }
    final span = along[j + 1] - along[j];
    final f = span <= 0 ? 0.0 : ((at - along[j]) / span).clamp(0.0, 1.0);
    out.add(
      GeoPoint(
        route[j].lat + (route[j + 1].lat - route[j].lat) * f,
        route[j].lon + (route[j + 1].lon - route[j].lon) * f,
      ),
    );
  }
  return out;
}

/// The length of [route] in metres.
double lengthOf(List<GeoPoint> route) {
  var m = 0.0;
  for (var i = 1; i < route.length; i++) {
    m += route[i - 1].metresTo(route[i]);
  }
  return m;
}
