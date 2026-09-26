import 'dart:math' as math;

/// One piece of a route.
sealed class RouteSegment {
  const RouteSegment();

  double get lengthM;
}

/// A straight piece of road.
class Straight extends RouteSegment {
  const Straight(this.lengthM);

  @override
  final double lengthM;
}

/// A bend of constant radius. A positive [turnDegrees] turns left and a
/// negative one turns right.
class Arc extends RouteSegment {
  const Arc({required this.radiusM, required this.turnDegrees});

  final double radiusM;
  final double turnDegrees;

  @override
  double get lengthM => radiusM * turnDegrees.abs() * math.pi / 180;
}

/// Where a car is, and where it is heading, at some distance along a route.
class RoutePoint {
  const RoutePoint({
    required this.latitude,
    required this.longitude,
    required this.headingDegrees,
    required this.curvature,
  });

  final double latitude;
  final double longitude;

  /// Compass heading, 0 to 360 degrees clockwise from north.
  final double headingDegrees;

  /// 1 / radius in metres, positive when the road bends left.
  final double curvature;
}

class _Placed {
  _Placed({
    required this.startM,
    required this.lengthM,
    required this.x,
    required this.y,
    required this.heading,
    required this.curvature,
  });

  final double startM;
  final double lengthM;

  /// Metres east and north of the origin, at the start of the piece.
  final double x;
  final double y;

  /// Radians clockwise from north.
  final double heading;

  /// Positive is left.
  final double curvature;
}

/// A road made of straights and arcs, laid out from a fixed origin.
///
/// The vehicle model reads its curvature to work out lateral acceleration, and
/// the simulated GPS reads its position. Both come from the distance the car has
/// travelled, so a car that stops on the route stays where it stopped.
class SimRoute {
  SimRoute(
    List<RouteSegment> segments, {
    this.originLatitude = 12.9716,
    this.originLongitude = 77.5946,
    double startHeadingDegrees = 0,
  }) : _placed = _lay(segments, startHeadingDegrees * math.pi / 180) {
    lengthM = _placed.isEmpty ? 0 : _placed.last.startM + _placed.last.lengthM;
  }

  /// A road of one straight, for a car that goes nowhere much.
  SimRoute.straight(double lengthM) : this([Straight(lengthM)]);

  final double originLatitude;
  final double originLongitude;
  final List<_Placed> _placed;

  /// The total length in metres.
  late final double lengthM;

  static const double _metresPerDegreeOfLatitude = 111320;

  static List<_Placed> _lay(List<RouteSegment> segments, double startHeading) {
    final placed = <_Placed>[];
    var distance = 0.0;
    var x = 0.0;
    var y = 0.0;
    var heading = startHeading;
    for (final segment in segments) {
      final length = segment.lengthM;
      if (length <= 0) continue;
      final curvature = switch (segment) {
        Straight() => 0.0,
        Arc(:final radiusM, :final turnDegrees) =>
          (turnDegrees < 0 ? -1.0 : 1.0) / radiusM,
      };
      placed.add(
        _Placed(
          startM: distance,
          lengthM: length,
          x: x,
          y: y,
          heading: heading,
          curvature: curvature,
        ),
      );
      final end = _advance(placed.last, length);
      x = end.$1;
      y = end.$2;
      heading = end.$3;
      distance += length;
    }
    return placed;
  }

  /// Position and heading after [s] metres along a piece.
  static (double, double, double) _advance(_Placed piece, double s) {
    final k = piece.curvature;
    final h0 = piece.heading;
    if (k == 0) {
      return (piece.x + s * math.sin(h0), piece.y + s * math.cos(h0), h0);
    }
    // A left turn lowers the compass heading: dh/ds = -k.
    final h = h0 - k * s;
    return (
      piece.x + (math.cos(h) - math.cos(h0)) / k,
      piece.y + (math.sin(h0) - math.sin(h)) / k,
      h,
    );
  }

  _Placed _pieceAt(double distanceM) {
    var low = 0;
    var high = _placed.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (_placed[mid].startM <= distanceM) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return _placed[low];
  }

  /// The curvature at [distanceM], 1 / radius, positive to the left. Past the
  /// end of the route the road runs straight on.
  double curvatureAt(double distanceM) {
    if (_placed.isEmpty || distanceM < 0 || distanceM >= lengthM) return 0;
    return _pieceAt(distanceM).curvature;
  }

  /// The position, heading and curvature at [distanceM]. Before the start the
  /// route is at its start, and after the end it carries on straight.
  RoutePoint pointAt(double distanceM) {
    if (_placed.isEmpty) {
      return RoutePoint(
        latitude: originLatitude,
        longitude: originLongitude,
        headingDegrees: 0,
        curvature: 0,
      );
    }
    final d = distanceM < 0 ? 0.0 : distanceM;
    final piece = d >= lengthM ? _placed.last : _pieceAt(d);
    final into = math.min(d - piece.startM, piece.lengthM);
    var (x, y, heading) = _advance(piece, into);
    var curvature = piece.curvature;
    if (d > lengthM) {
      // Run straight on past the end.
      final beyond = d - lengthM;
      x += beyond * math.sin(heading);
      y += beyond * math.cos(heading);
      curvature = 0;
    }
    final latitude = originLatitude + y / _metresPerDegreeOfLatitude;
    final longitude =
        originLongitude +
        x /
            (_metresPerDegreeOfLatitude *
                math.cos(originLatitude * math.pi / 180));
    var degrees = heading * 180 / math.pi % 360;
    if (degrees < 0) degrees += 360;
    return RoutePoint(
      latitude: latitude,
      longitude: longitude,
      headingDegrees: degrees,
      curvature: curvature,
    );
  }
}
