import '../trips/trip.dart';
import 'geo.dart';

/// The same route driven twice (Ghost commute): the trip, the earlier one beside
/// it, and what separates them in rupees, never in minutes.
class GhostMatch {
  const GhostMatch({
    required this.now,
    required this.before,
    required this.nowRoute,
    required this.beforeRoute,
  });

  final Trip now;
  final Trip before;

  /// The two routes, [points] points each, spaced along their length.
  final List<GeoPoint> nowRoute;
  final List<GeoPoint> beforeRoute;

  /// Rupees saved against the earlier drive (negative when this one cost more),
  /// or null when either was unpriced.
  double? get rupeesSaved =>
      now.cost == null || before.cost == null ? null : before.cost! - now.cost!;

  double get idleSecondsSaved => before.idleSeconds - now.idleSeconds;
  int get hardStartsSaved => before.hardAccelerations - now.hardAccelerations;

  static const int points = 24;

  /// The ends must be within this many metres of each other, and the shape within
  /// [shapeMetres] on average along the way.
  static const double endMetres = 400;
  static const double shapeMetres = 180;

  /// A route this much longer or shorter is another route.
  static const double lengthRatio = 1.3;

  /// The least a route can be to count as a commute, in metres.
  static const double minMetres = 800;

  /// The latest earlier trip over the same route as [trip], among [others]
  /// (each with its samples), or null.
  static GhostMatch? find(
    Trip trip,
    List<TripSample> samples,
    Iterable<(Trip, List<TripSample>)> others,
  ) {
    final mine = _shape(samples);
    if (mine == null) return null;
    final myLength = lengthOf(mine);
    (Trip, List<GeoPoint>)? best;
    for (final (other, otherSamples) in others) {
      if (other.id == trip.id || other.isDemo != trip.isDemo) continue;
      if (!other.startedAt.isBefore(trip.startedAt)) continue;
      if (best != null && other.startedAt.isBefore(best.$1.startedAt)) {
        continue;
      }
      final theirs = _shape(otherSamples);
      if (theirs == null) continue;
      final ratio = lengthOf(theirs) / myLength;
      if (ratio > lengthRatio || ratio < 1 / lengthRatio) continue;
      if (mine.first.metresTo(theirs.first) > endMetres ||
          mine.last.metresTo(theirs.last) > endMetres) {
        continue;
      }
      var sum = 0.0;
      for (var i = 0; i < points; i++) {
        sum += mine[i].metresTo(theirs[i]);
      }
      if (sum / points > shapeMetres) continue;
      best = (other, theirs);
    }
    if (best == null) return null;
    return GhostMatch(
      now: trip,
      before: best.$1,
      nowRoute: mine,
      beforeRoute: best.$2,
    );
  }

  static List<GeoPoint>? _shape(List<TripSample> samples) {
    final route = [for (final r in routeOf(samples)) r.$2];
    if (route.length < 10 || lengthOf(route) < minMetres) return null;
    return resample(route, points);
  }
}
