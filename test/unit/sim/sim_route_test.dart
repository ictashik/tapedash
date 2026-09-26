import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/sim/sim_route.dart';

const _lat0 = 12.9716;
const _lon0 = 77.5946;
const _metresPerDegree = 111320.0;

/// Metres east and north of the origin, worked out the way the route does, so
/// tests can state positions in metres.
({double east, double north}) _offset(RoutePoint p) => (
  east:
      (p.longitude - _lon0) *
      _metresPerDegree *
      math.cos(_lat0 * math.pi / 180),
  north: (p.latitude - _lat0) * _metresPerDegree,
);

/// The angle between two headings, allowing for the wrap from 360 back to 0.
double _headingGap(RoutePoint a, RoutePoint b) {
  final gap = (a.headingDegrees - b.headingDegrees).abs() % 360;
  return math.min(gap, 360 - gap);
}

void main() {
  group('a straight road', () {
    final route = SimRoute.straight(1000);

    test('is as long as it was made', () {
      expect(route.lengthM, 1000);
    });

    test('runs north from the origin by default', () {
      final start = route.pointAt(0);
      final end = route.pointAt(1000);

      expect(start.latitude, _lat0);
      expect(start.longitude, _lon0);
      expect(start.headingDegrees, 0);
      expect(_offset(end).north, closeTo(1000, 1e-6));
      expect(_offset(end).east, closeTo(0, 1e-6));
    });

    test('has no curvature anywhere', () {
      for (final d in [0.0, 1.0, 500.0, 999.0]) {
        expect(route.curvatureAt(d), 0);
      }
    });

    test('one degree of latitude is about 111 km', () {
      final end = route.pointAt(1000);

      expect(end.latitude - _lat0, closeTo(1000 / 111320, 1e-9));
    });

    test('runs east when it starts east, and the longitude grows', () {
      final east = SimRoute([const Straight(500)], startHeadingDegrees: 90);
      final end = east.pointAt(500);

      expect(_offset(end).east, closeTo(500, 1e-6));
      expect(_offset(end).north, closeTo(0, 1e-6));
      expect(end.headingDegrees, closeTo(90, 1e-9));
    });
  });

  group('an arc', () {
    test(
      'a left turn of 90 degrees at radius 50 ends 50 m west and 50 m north',
      () {
        final route = SimRoute([const Arc(radiusM: 50, turnDegrees: 90)]);
        final end = route.pointAt(route.lengthM);

        expect(route.lengthM, closeTo(50 * math.pi / 2, 1e-9));
        expect(_offset(end).east, closeTo(-50, 1e-6));
        expect(_offset(end).north, closeTo(50, 1e-6));
        expect(end.headingDegrees, closeTo(270, 1e-9));
      },
    );

    test(
      'a right turn of 90 degrees at radius 50 ends 50 m east and 50 m north',
      () {
        final route = SimRoute([const Arc(radiusM: 50, turnDegrees: -90)]);
        final end = route.pointAt(route.lengthM);

        expect(_offset(end).east, closeTo(50, 1e-6));
        expect(_offset(end).north, closeTo(50, 1e-6));
        expect(end.headingDegrees, closeTo(90, 1e-9));
      },
    );

    test(
      'curvature is 1 / radius, positive to the left and negative to the right',
      () {
        final left = SimRoute([const Arc(radiusM: 25, turnDegrees: 90)]);
        final right = SimRoute([const Arc(radiusM: 25, turnDegrees: -90)]);

        expect(left.curvatureAt(5), closeTo(0.04, 1e-12));
        expect(right.curvatureAt(5), closeTo(-0.04, 1e-12));
      },
    );

    test('the point halfway round a quarter turn is where geometry says', () {
      final route = SimRoute([const Arc(radiusM: 100, turnDegrees: 90)]);
      final half = route.pointAt(route.lengthM / 2);

      // 45 degrees round a left-hand circle of radius 100 that starts heading north.
      expect(
        _offset(half).east,
        closeTo(-100 * (1 - math.cos(math.pi / 4)), 1e-6),
      );
      expect(_offset(half).north, closeTo(100 * math.sin(math.pi / 4), 1e-6));
      expect(half.headingDegrees, closeTo(315, 1e-9));
    });

    test('a full circle comes back to where it started', () {
      final route = SimRoute([
        const Arc(radiusM: 30, turnDegrees: 180),
        const Arc(radiusM: 30, turnDegrees: 180),
      ]);
      final end = route.pointAt(route.lengthM);

      expect(_offset(end).east, closeTo(0, 1e-5));
      expect(_offset(end).north, closeTo(0, 1e-5));
      expect(end.headingDegrees, closeTo(0, 1e-6));
    });
  });

  group('a route made of several pieces', () {
    // A square of 200 m sides with four left turns of radius 20 m.
    final square = SimRoute([
      for (var i = 0; i < 4; i++) ...[
        const Straight(160),
        const Arc(radiusM: 20, turnDegrees: 90),
      ],
    ]);

    test('closes on itself', () {
      final end = square.pointAt(square.lengthM);

      expect(_offset(end).east, closeTo(0, 1e-4));
      expect(_offset(end).north, closeTo(0, 1e-4));
      expect(end.headingDegrees % 360, closeTo(0, 1e-6));
    });

    test('is the sum of its pieces', () {
      expect(square.lengthM, closeTo(4 * (160 + 20 * math.pi / 2), 1e-9));
    });

    test('is continuous in position and heading at every join', () {
      var d = 0.0;
      for (var i = 0; i < 4; i++) {
        d += 160;
        var before = square.pointAt(d - 1e-6);
        var after = square.pointAt(d + 1e-6);
        expect(
          (_offset(before).east - _offset(after).east).abs(),
          lessThan(1e-4),
        );
        expect(
          (_offset(before).north - _offset(after).north).abs(),
          lessThan(1e-4),
        );
        expect(_headingGap(before, after), lessThan(1e-3));

        d += 20 * math.pi / 2;
        before = square.pointAt(d - 1e-6);
        after = square.pointAt(d + 1e-6);
        expect(
          (_offset(before).east - _offset(after).east).abs(),
          lessThan(1e-4),
        );
        expect(
          (_offset(before).north - _offset(after).north).abs(),
          lessThan(1e-4),
        );
      }
    });

    test('is straight on the straights and curved on the bends', () {
      const arc = 20 * math.pi / 2;

      expect(square.curvatureAt(80), 0);
      expect(square.curvatureAt(160 + 10), closeTo(0.05, 1e-12));
      expect(square.curvatureAt(160 + arc + 80), 0);
      expect(square.curvatureAt(2 * (160 + arc) - 10), closeTo(0.05, 1e-12));
    });

    test('headings stay in 0 to 360', () {
      for (var d = 0.0; d <= square.lengthM; d += 7) {
        expect(square.pointAt(d).headingDegrees, inInclusiveRange(0, 360));
      }
    });

    test('the second side heads west after the first left turn', () {
      final onSecondSide = square.pointAt(160 + 20 * math.pi / 2 + 80);

      expect(onSecondSide.headingDegrees, closeTo(270, 1e-6));
    });
  });

  group('outside the route', () {
    final route = SimRoute([
      const Straight(100),
      const Arc(radiusM: 50, turnDegrees: 90),
    ]);

    test('before the start it is at the start', () {
      final p = route.pointAt(-50);

      expect(p.latitude, _lat0);
      expect(p.longitude, _lon0);
    });

    test('past the end it carries on straight in the final heading', () {
      final end = route.pointAt(route.lengthM);
      final beyond = route.pointAt(route.lengthM + 100);

      // The arc turned left to face west, so 100 m further is 100 m more west.
      expect(_offset(beyond).east - _offset(end).east, closeTo(-100, 1e-6));
      expect(_offset(beyond).north - _offset(end).north, closeTo(0, 1e-6));
      expect(beyond.curvature, 0);
    });

    test('there is no curvature past the end or before the start', () {
      expect(route.curvatureAt(route.lengthM + 10), 0);
      expect(route.curvatureAt(-10), 0);
    });

    test('an empty route stays at the origin', () {
      final empty = SimRoute([]);

      expect(empty.lengthM, 0);
      expect(empty.pointAt(500).latitude, _lat0);
      expect(empty.curvatureAt(5), 0);
    });

    test('pieces of no length are ignored', () {
      final route = SimRoute([
        const Straight(0),
        const Straight(10),
        const Arc(radiusM: 5, turnDegrees: 0),
      ]);

      expect(route.lengthM, 10);
    });
  });

  test('a different origin moves every point with it', () {
    final route = SimRoute(
      [const Straight(100)],
      originLatitude: 51.5,
      originLongitude: -0.12,
    );
    final start = route.pointAt(0);

    expect(start.latitude, 51.5);
    expect(start.longitude, -0.12);
    expect(route.pointAt(100).latitude, closeTo(51.5 + 100 / 111320, 1e-9));
  });
}
