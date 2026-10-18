import 'dart:math' as math;

import '../trips/trip.dart';
import 'geo.dart';

/// A place where the car stood with the engine running, and what it cost there
/// (The Toll Map).
class TollSpot {
  const TollSpot({
    required this.at,
    required this.litres,
    required this.seconds,
    required this.stops,
    this.rupees,
  });

  final GeoPoint at;
  final double litres;
  final double seconds;

  /// How many separate stops added up to it.
  final int stops;

  /// Null while no price is known.
  final double? rupees;
}

/// The money spent standing still, pinned to the places it was spent (The Toll
/// Map): every stop with the engine running is put where the GPS had it, stops
/// close together are one place, and each place adds up its fuel.
///
/// Everything comes from what a trip already keeps: the GPS trail and the fuel
/// flow of each second.
class TollMap {
  TollMap._(this.spots, this.roads, this.totalRupees, this.totalLitres);

  /// Under this speed the car is standing.
  static const double standingKmh = 2;

  /// A stop shorter than this is the car slowing for a bump, not a toll.
  static const double minStopSeconds = 15;

  /// Stops this close are one place.
  static const double clusterMetres = 70;

  /// Places that cost less than this many seconds in all are left off the map.
  static const double minSpotSeconds = 40;

  /// The most places drawn, the dearest first.
  static const int maxSpots = 12;

  /// The most points a road is drawn from.
  static const int roadPoints = 90;

  /// The dearest first.
  final List<TollSpot> spots;

  /// The roads driven, each a line of points, for the map's background.
  final List<List<GeoPoint>> roads;

  final double totalRupees;
  final double totalLitres;

  bool get isEmpty => spots.isEmpty;

  /// [trips] with their samples. [fallbackPrice] is used for a trip that has no
  /// price of its own, and null leaves it unpriced.
  factory TollMap.from(
    Iterable<(Trip, List<TripSample>)> trips, {
    double? fallbackPrice,
  }) {
    final stops = <_Stop>[];
    final roads = <List<GeoPoint>>[];
    for (final (trip, samples) in trips) {
      final price = trip.pricePerLitre ?? fallbackPrice;
      final route = routeOf(samples);
      if (route.length >= 2) {
        roads.add(resample([for (final r in route) r.$2], roadPoints));
      }
      _Stop? open;
      double? lastSeconds;
      for (final s in samples) {
        final dt = lastSeconds == null ? 0.0 : s.seconds - lastSeconds;
        lastSeconds = s.seconds;
        final standing = s.speedKmh < standingKmh && s.rpm > 400;
        if (!standing || dt > 5) {
          if (open != null) _close(stops, open);
          open = null;
          if (!standing) continue;
        }
        if (dt <= 0) {
          continue;
        }
        open ??= _Stop(price);
        open.seconds += dt;
        open.litres += s.litresPerHour * dt / 3600;
        if (s.latitude != null && s.longitude != null) {
          open.lat += s.latitude!;
          open.lon += s.longitude!;
          open.fixes++;
        }
      }
      if (open != null) _close(stops, open);
    }

    final clusters = <_Cluster>[];
    for (final st in stops) {
      final p = GeoPoint(st.lat / st.fixes, st.lon / st.fixes);
      _Cluster? best;
      var gap = clusterMetres;
      for (final c in clusters) {
        final d = c.centre.metresTo(p);
        if (d <= gap) {
          gap = d;
          best = c;
        }
      }
      if (best == null) {
        clusters.add(_Cluster(p)..add(st, p));
      } else {
        best.add(st, p);
      }
    }
    final spots = [
      for (final c in clusters)
        if (c.seconds >= minSpotSeconds)
          TollSpot(
            at: c.centre,
            litres: c.litres,
            seconds: c.seconds,
            stops: c.stops,
            rupees: c.priced ? c.rupees : null,
          ),
    ]..sort((a, b) => (b.rupees ?? b.litres).compareTo(a.rupees ?? a.litres));
    final shown = spots.take(maxSpots).toList();
    return TollMap._(
      shown,
      roads,
      shown.fold(0.0, (a, s) => a + (s.rupees ?? 0)),
      shown.fold(0.0, (a, s) => a + s.litres),
    );
  }

  static void _close(List<_Stop> stops, _Stop s) {
    if (s.seconds >= minStopSeconds && s.fixes > 0) stops.add(s);
  }

  /// The fitting of the map into a panel: metres east and north of the centre
  /// of everything drawn.
  MapFit fit() {
    final all = <GeoPoint>[
      for (final r in roads) ...r,
      for (final s in spots) s.at,
    ];
    return MapFit(all);
  }
}

class _Stop {
  _Stop(this.price);
  final double? price;
  double seconds = 0;
  double litres = 0;
  double lat = 0;
  double lon = 0;
  int fixes = 0;
}

class _Cluster {
  _Cluster(this.centre);
  GeoPoint centre;
  double seconds = 0;
  double litres = 0;
  double rupees = 0;
  int stops = 0;
  int _n = 0;
  bool priced = false;

  void add(_Stop s, GeoPoint p) {
    seconds += s.seconds;
    litres += s.litres;
    if (s.price != null) {
      rupees += s.litres * s.price!;
      priced = true;
    }
    stops++;
    _n++;
    // The centre drifts to the mean of its stops.
    centre = GeoPoint(
      centre.lat + (p.lat - centre.lat) / _n,
      centre.lon + (p.lon - centre.lon) / _n,
    );
  }
}

/// Maps latitudes and longitudes onto a panel: north up, with the same scale on
/// both axes, filled to the panel with a margin.
class MapFit {
  MapFit(Iterable<GeoPoint> points) {
    var minLat = double.infinity, maxLat = -double.infinity;
    var minLon = double.infinity, maxLon = -double.infinity;
    for (final p in points) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLon = math.min(minLon, p.lon);
      maxLon = math.max(maxLon, p.lon);
    }
    if (minLat > maxLat) {
      minLat = maxLat = minLon = maxLon = 0;
    }
    centreLat = (minLat + maxLat) / 2;
    centreLon = (minLon + maxLon) / 2;
    _cos = math.cos(centreLat * math.pi / 180);
    widthM = (maxLon - minLon) * GeoPoint.metresPerDegree * _cos;
    heightM = (maxLat - minLat) * GeoPoint.metresPerDegree;
  }

  late final double centreLat;
  late final double centreLon;
  late final double _cos;

  /// The extent of the points, in metres.
  late final double widthM;
  late final double heightM;

  /// Metres east and north of the centre.
  (double, double) metres(GeoPoint p) => (
    (p.lon - centreLon) * GeoPoint.metresPerDegree * _cos,
    (p.lat - centreLat) * GeoPoint.metresPerDegree,
  );

  /// Pixels for a metre when the points fill [width] by [height] with [margin]
  /// all round. A single place (no extent) gets a scale of 1.
  double scale(double width, double height, double margin) {
    final w = math.max(widthM, 1.0);
    final h = math.max(heightM, 1.0);
    return math.min((width - 2 * margin) / w, (height - 2 * margin) / h);
  }
}
