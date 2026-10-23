import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/trips/route_geometry.dart';
import 'package:tapedash/trips/trip.dart';
import 'package:tapedash/trips/trip_library.dart';

TripSample at(double lat, double lon, [double t = 0]) => TripSample(
  seconds: t,
  speedKmh: 30,
  rpm: 2000,
  throttle: 20,
  litresPerHour: 2,
  latitude: lat,
  longitude: lon,
);

void main() {
  group('RouteGeometry', () {
    test('fewer than two positions is no route', () {
      expect(RouteGeometry.build([], 100, 100), isNull);
      expect(RouteGeometry.build([at(12, 77)], 100, 100), isNull);
      expect(
        RouteGeometry.build(
          const [
            TripSample(
              seconds: 0,
              speedKmh: 0,
              rpm: 0,
              throttle: 0,
              litresPerHour: 0,
            ),
            TripSample(
              seconds: 1,
              speedKmh: 0,
              rpm: 0,
              throttle: 0,
              litresPerHour: 0,
            ),
          ],
          100,
          100,
        ),
        isNull,
      );
    });

    test('north is up and east is right', () {
      final g = RouteGeometry.build(
        [at(12.0, 77.0), at(12.01, 77.0), at(12.01, 77.01)],
        400,
        400,
      )!;
      // The first point is the southwest one: bottom left of the last two.
      expect(g.ys[0], greaterThan(g.ys[1]), reason: 'north is up (smaller y)');
      expect(g.xs[2], greaterThan(g.xs[1]), reason: 'east is right');
    });

    test('it keeps its shape: a square stays a square', () {
      // 0.01 degrees of latitude and the same distance east at 12 N.
      const lat = 12.0;
      final dLon = 0.01 / 0.97815; // cos(12 degrees).
      final g = RouteGeometry.build(
        [
          at(lat, 77.0),
          at(lat + 0.01, 77.0),
          at(lat + 0.01, 77.0 + dLon),
          at(lat, 77.0 + dLon),
        ],
        800,
        300,
      )!;
      final w = (g.xs[2] - g.xs[0]).abs();
      final h = (g.ys[1] - g.ys[0]).abs();
      expect(w / h, closeTo(1, 0.02));
    });

    test('it is fitted inside 8% padding and centred', () {
      final g = RouteGeometry.build(
        [at(12.0, 77.0), at(12.02, 77.0), at(12.02, 77.005)],
        600,
        300,
      )!;
      final minX = g.xs.reduce((a, b) => a < b ? a : b);
      final maxX = g.xs.reduce((a, b) => a > b ? a : b);
      final minY = g.ys.reduce((a, b) => a < b ? a : b);
      final maxY = g.ys.reduce((a, b) => a > b ? a : b);
      expect(minX, greaterThanOrEqualTo(600 * 0.08 - 1e-6));
      expect(maxX, lessThanOrEqualTo(600 * 0.92 + 1e-6));
      expect(minY, greaterThanOrEqualTo(300 * 0.08 - 1e-6));
      expect(maxY, lessThanOrEqualTo(300 * 0.92 + 1e-6));
      // The tall side fills its room; the route is centred across.
      expect(maxY - minY, closeTo(300 * 0.84, 1));
      expect((minX + maxX) / 2, closeTo(300, 1));
    });

    test('a parked car\'s scatter of fixes is dropped', () {
      final g = RouteGeometry.build(
        [
          for (var i = 0; i < 50; i++)
            at(12.0 + (i % 2) * 1e-7, 77.0, i.toDouble()),
          at(12.01, 77.0, 60),
        ],
        400,
        400,
      )!;
      expect(g.length, 2);
    });

    test('a long route is thinned to 1000 points, keeping both ends', () {
      final samples = [
        for (var i = 0; i < 5000; i++) at(12.0 + i * 1e-5, 77.0, i.toDouble()),
      ];
      final g = RouteGeometry.build(samples, 400, 400)!;
      expect(g.length, RouteGeometry.maxPoints);
      expect(g.sampleIndex.first, 0);
      expect(g.sampleIndex.last, 4999);
    });

    test('progress runs 0 to 1 by distance', () {
      final g = RouteGeometry.build(
        [at(12.0, 77.0), at(12.01, 77.0), at(12.03, 77.0)],
        400,
        400,
      )!;
      final p = g.progress;
      expect(p.first, 0);
      expect(p.last, 1);
      // The second leg is twice the first.
      expect(p[1], closeTo(1 / 3, 0.01));
    });

    test('the nearest point to a sample', () {
      final g = RouteGeometry.build(
        [for (var i = 0; i < 100; i++) at(12.0 + i * 1e-4, 77.0, i.toDouble())],
        400,
        400,
      )!;
      expect(g.sampleIndex[g.nearestPoint(0)], 0);
      expect(g.sampleIndex[g.nearestPoint(99)], 99);
      expect(
        (g.sampleIndex[g.nearestPoint(50)] - 50).abs(),
        lessThanOrEqualTo(1),
      );
    });
  });

  group('TripLibrary', () {
    test('holds the real trips newest first, and selects the latest', () async {
      final repo = MemoryTripRepository();
      await repo.create(Trip(startedAt: DateTime(2026, 3, 1)));
      await repo.create(Trip(startedAt: DateTime(2026, 3, 3), isDemo: true));
      await repo.create(Trip(startedAt: DateTime(2026, 3, 2)));
      final lib = TripLibrary(repo);
      await lib.refresh();
      expect([for (final t in lib.trips.value) t.startedAt.day], [2, 1]);
      expect(lib.selected.value!.startedAt.day, 2);
    });

    test('a chosen trip stays chosen across a refresh', () async {
      final repo = MemoryTripRepository();
      await repo.create(Trip(startedAt: DateTime(2026, 3, 1)));
      await repo.create(Trip(startedAt: DateTime(2026, 3, 2)));
      final lib = TripLibrary(repo);
      await lib.refresh();
      lib.select(lib.trips.value.last);
      await repo.create(Trip(startedAt: DateTime(2026, 3, 5)));
      await lib.refresh();
      expect(lib.selected.value!.startedAt.day, 1);
    });

    test('deleting everything empties it', () async {
      final repo = MemoryTripRepository();
      final t = await repo.create(Trip(startedAt: DateTime(2026, 3, 1)));
      await repo.addSamples(t.id!, [at(12, 77)]);
      final lib = TripLibrary(repo);
      await lib.refresh();
      await lib.deleteAll();
      expect(lib.trips.value, isEmpty);
      expect(lib.selected.value, isNull);
      expect(await repo.samples(t.id!), isEmpty);
    });

    test('samples of a trip', () async {
      final repo = MemoryTripRepository();
      final t = await repo.create(Trip(startedAt: DateTime(2026, 3, 1)));
      await repo.addSamples(t.id!, [at(12, 77), at(12.001, 77, 1)]);
      final lib = TripLibrary(repo);
      await lib.refresh();
      expect((await lib.samples(lib.selected.value!)).length, 2);
    });

    test('nearestTo finds the point nearest a panel position, and how far', () {
      final g = RouteGeometry.build(
        [
          for (var i = 0; i < 5; i++)
            at(12.90, 77.60 + i * 0.001, i.toDouble()),
        ],
        400,
        200,
      )!;

      // Right on a point.
      final on = g.nearestTo(g.xs[3], g.ys[3]);
      expect(on.point, 3);
      expect(on.distance, closeTo(0, 1e-9));

      // A little to one side of it.
      final near = g.nearestTo(g.xs[3] + 3, g.ys[3] + 4);
      expect(near.point, 3);
      expect(near.distance, closeTo(5, 1e-9));

      // Far off: still the nearest point, and the distance says how far.
      final far = g.nearestTo(-1000, g.ys[0]);
      expect(far.point, 0);
      expect(far.distance, greaterThan(900));
    });
  });
}
