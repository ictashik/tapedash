// The replay of a trip (DESIGN.md 6.12): values between the samples, the totals a
// replay ends on, a gap skipped rather than waited out, and where on the route the
// car is.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/trips/route_geometry.dart';
import 'package:tapedash/trips/trip.dart';
import 'package:tapedash/trips/trip_playback.dart';

TripSample sample(
  double t, {
  double speed = 36,
  double rpm = 2000,
  double throttle = 20,
  double lph = 3.6,
  double? lat,
  double? lon,
  double? load,
}) => TripSample(
  seconds: t,
  speedKmh: speed,
  rpm: rpm,
  throttle: throttle,
  litresPerHour: lph,
  latitude: lat,
  longitude: lon,
  load: load,
);

void main() {
  group('the line in time', () {
    test('a trip of a hundred one-second samples lasts 99 s', () {
      final p = TripPlayback([for (var i = 0; i < 100; i++) sample(i + 1)]);

      expect(p.isReplayable, isTrue);
      expect(p.duration, closeTo(99, 1e-9));
    });

    test('fewer than two samples is nothing to replay', () {
      expect(TripPlayback(const []).isReplayable, isFalse);
      expect(TripPlayback([sample(0)]).isReplayable, isFalse);
      expect(TripPlayback([sample(0)]).duration, 0);
    });

    test('between two samples a value is the straight line between them', () {
      final p = TripPlayback([
        sample(0, speed: 0, rpm: 1000, throttle: 0),
        sample(1, speed: 10, rpm: 3000, throttle: 40),
      ]);
      final f = PlaybackFrame();

      p.fill(f, 0.25);

      expect(f.speedKmh, closeTo(2.5, 1e-9));
      expect(f.rpm, closeTo(1500, 1e-9));
      expect(f.throttle, closeTo(10, 1e-9));
      expect(f.sample, closeTo(0.25, 1e-9));
    });

    test('before the start and after the end it is the first and the last', () {
      final p = TripPlayback([sample(0, speed: 5), sample(1, speed: 50)]);
      final f = PlaybackFrame();

      p.fill(f, -3);
      expect(f.speedKmh, 5);
      expect(f.seconds, 0);

      p.fill(f, 99);
      expect(f.speedKmh, 50);
      expect(f.seconds, 1);
    });

    test('asked in any order, it gives the same moment', () {
      final p = TripPlayback([
        for (var i = 0; i < 50; i++) sample(i.toDouble(), speed: i * 2.0),
      ]);
      final f = PlaybackFrame();

      p.fill(f, 40.5);
      expect(f.speedKmh, closeTo(81, 1e-9));
      p.fill(f, 3.25);
      expect(f.speedKmh, closeTo(6.5, 1e-9));
      p.fill(f, 40.5);
      expect(f.speedKmh, closeTo(81, 1e-9));
      p.fill(f, 12);
      expect(f.speedKmh, closeTo(24, 1e-9));
    });

    test(
      'a channel the car did not give is NaN, and one it gave briefly is held',
      () {
        final p = TripPlayback([sample(0), sample(1, load: 50), sample(2)]);
        final f = PlaybackFrame();

        p.fill(f, 0.2);
        expect(
          f.load,
          closeTo(50, 1e-9),
          reason: 'only one side has it: it holds',
        );
        p.fill(f, 1.6);
        expect(f.load, closeTo(50, 1e-9));

        final none = TripPlayback([sample(0), sample(1)]);
        none.fill(f, 0.5);
        expect(f.load.isNaN, isTrue);
      },
    );
  });

  group('a gap is skipped, not waited out', () {
    final samples = [
      sample(0, speed: 36),
      sample(1, speed: 36),
      // The engine was off for five minutes.
      sample(301, speed: 0, rpm: 800),
      sample(302, speed: 0, rpm: 800),
    ];

    test('it takes half a second of the replay', () {
      final p = TripPlayback(samples);

      expect(p.duration, closeTo(1 + TripPlayback.gapSeconds + 1, 1e-9));
    });

    test('no distance and no fuel are counted across it', () {
      final p = TripPlayback(samples);
      final f = PlaybackFrame();

      p.fill(f, 1);
      final before = f.distanceKm;
      final litresBefore = f.litres;
      p.fill(f, 1 + TripPlayback.gapSeconds);

      expect(f.distanceKm, closeTo(before, 1e-9));
      expect(f.litres, closeTo(litresBefore, 1e-9));
    });
  });

  group('the totals', () {
    test('36 km/h for 100 s is one kilometre; 3.6 L/h for 100 s is 0.1 L', () {
      final p = TripPlayback([
        for (var i = 0; i <= 100; i++) sample(i.toDouble()),
      ]);
      final f = PlaybackFrame();

      p.fill(f, p.duration);

      expect(f.distanceKm, closeTo(1.0, 1e-9));
      expect(f.litres, closeTo(0.1, 1e-9));
    });

    test('the replay ends on the trip\'s own distance and litres', () {
      final p = TripPlayback(
        [for (var i = 0; i <= 100; i++) sample(i.toDouble())],
        pricePerLitre: 100,
        tripDistanceKm: 1.04,
        tripLitres: 0.11,
      );
      final f = PlaybackFrame();

      p.fill(f, p.duration);

      expect(f.distanceKm, closeTo(1.04, 1e-9));
      expect(f.litres, closeTo(0.11, 1e-9));
      expect(f.cost, closeTo(11, 1e-9), reason: 'the receipt\'s ₹');
    });

    test('the running cost rises with the fuel and never falls', () {
      final p = TripPlayback([
        for (var i = 0; i <= 100; i++) sample(i.toDouble()),
      ], pricePerLitre: 100);
      final f = PlaybackFrame();
      var last = -1.0;

      for (var t = 0.0; t <= p.duration; t += 0.7) {
        p.fill(f, t);
        expect(f.cost, greaterThanOrEqualTo(last));
        last = f.cost;
      }
    });

    test('with no price there is no cost, and litres are still counted', () {
      final p = TripPlayback([
        for (var i = 0; i <= 10; i++) sample(i.toDouble()),
      ]);
      final f = PlaybackFrame();

      p.fill(f, 10);

      expect(f.cost.isNaN, isTrue);
      expect(f.costPerKm.isNaN, isTrue);
      expect(f.litres, greaterThan(0));
    });

    test('₹/km is what each kilometre costs now, and nothing below 5 km/h', () {
      final p = TripPlayback([
        sample(0, speed: 50, lph: 5),
        sample(1, speed: 50, lph: 5),
        sample(2, speed: 2, lph: 1),
      ], pricePerLitre: 100);
      final f = PlaybackFrame();

      p.fill(f, 0.5);
      expect(f.costPerKm, closeTo(5 * 100 / 50, 1e-9));
      p.fill(f, 2);
      expect(f.costPerKm.isNaN, isTrue);
    });
  });

  group('the fractional sample', () {
    test('goes both ways', () {
      final p = TripPlayback([
        sample(0),
        sample(1),
        sample(500), // a gap
        sample(501),
      ]);

      expect(p.sampleAt(0.5), closeTo(0.5, 1e-9));
      expect(
        p.sampleAt(1.25),
        closeTo(1.5, 1e-9),
        reason: 'half way over the gap',
      );
      expect(p.timeOfFractionalSample(1.5), closeTo(1.25, 1e-9));
      expect(p.timeOfSample(3), closeTo(p.duration, 1e-9));
      for (final s in [0.0, 0.3, 1.0, 1.5, 2.2, 3.0]) {
        expect(p.sampleAt(p.timeOfFractionalSample(s)), closeTo(s, 1e-9));
      }
    });

    test('the odometer at a fractional sample', () {
      final p = TripPlayback([
        for (var i = 0; i <= 10; i++) sample(i.toDouble()),
      ]);

      expect(p.kmAtSample(0), 0);
      expect(p.kmAtSample(5), closeTo(0.05, 1e-9));
      expect(p.kmAtSample(2.5), closeTo(0.025, 1e-9));
      expect(p.kmAtSample(99), closeTo(0.1, 1e-9));
    });
  });

  group('where on the route the car is', () {
    // A straight road east at 10 m/s (36 km/h), a fix each second, with a stop of
    // 20 s in the middle: the stopped car's fixes scatter by less than a metre, so
    // the geometry drops them.
    const dLon = 0.0001; // about 10.9 m at 12 N
    final samples = <TripSample>[];
    void add(double t, double speed, double lon) =>
        samples.add(sample(t, speed: speed, lat: 12.0, lon: 77.0 + lon));
    setUp(() {
      samples.clear();
      for (var i = 0; i <= 10; i++) {
        add(i.toDouble(), 36, i * dLon);
      }
      for (var i = 11; i <= 30; i++) {
        add(i.toDouble(), 0, 10 * dLon);
      }
      for (var i = 31; i <= 40; i++) {
        add(i.toDouble(), 36, (10 + i - 30) * dLon);
      }
    });

    test('the stopped car\'s points are dropped', () {
      final g = RouteGeometry.build(samples, 400, 100)!;

      expect(g.length, lessThan(25));
    });

    test('it stands still while the car stood, and moves on when it did', () {
      final g = RouteGeometry.build(samples, 400, 100)!;
      final p = TripPlayback(samples);

      double x(double sample) => g.xAt(g.pointAt(sample, p.kmAtSample));
      expect(x(12), closeTo(x(29), 1e-6), reason: 'no creeping in the stop');
      expect(x(35), greaterThan(x(31)));
      expect(x(5), lessThan(x(9)));
    });

    test('it runs from the first point to the last', () {
      final g = RouteGeometry.build(samples, 400, 100)!;
      final p = TripPlayback(samples);

      expect(g.pointAt(-1, p.kmAtSample), 0);
      expect(g.pointAt(0, p.kmAtSample), 0);
      expect(g.pointAt(40, p.kmAtSample), (g.length - 1).toDouble());
      expect(g.pointAt(99, p.kmAtSample), (g.length - 1).toDouble());
    });

    test('it never goes backwards along the road', () {
      final g = RouteGeometry.build(samples, 400, 100)!;
      final p = TripPlayback(samples);
      var last = -1.0;

      for (var s = 0.0; s <= 40; s += 0.25) {
        final at = g.pointAt(s, p.kmAtSample);
        expect(at, greaterThanOrEqualTo(last));
        last = at;
      }
    });

    test('where the odometer did not move at all it goes by the time', () {
      // Wandering GPS at a standstill: two points a few metres apart.
      final wander = [
        sample(0, speed: 0, lat: 12.0, lon: 77.0),
        sample(10, speed: 0, lat: 12.0, lon: 77.00005),
      ];
      final g = RouteGeometry.build(wander, 100, 100)!;
      final p = TripPlayback(wander);

      expect(g.pointAt(0.5, p.kmAtSample), closeTo(0.5, 1e-9));
    });

    test('the heading of an eastward road is 0, and a northward one is up', () {
      final g = RouteGeometry.build(samples, 400, 100)!;
      expect(g.headingAt(3), closeTo(0, 1e-6));

      final north = RouteGeometry.build(
        [
          sample(0, lat: 12.0, lon: 77.0),
          sample(1, lat: 12.001, lon: 77.0),
          sample(2, lat: 12.002, lon: 77.0),
        ],
        100,
        100,
      )!;
      // y is down the panel, so north is a quarter turn back.
      expect(north.headingAt(1), closeTo(-1.5707963, 1e-6));
    });

    test('it keeps the last heading where the route has none', () {
      final g = RouteGeometry.build(samples, 400, 100)!;

      expect(g.headingAt(0, span: 0, previous: 1.25), 1.25);
    });

    test('a metre is so many panel units', () {
      final g = RouteGeometry.build(samples, 400, 100)!;

      expect(g.unitsPerMetre, greaterThan(0));
      // The route spans its width less 8% padding on each side.
      expect(g.xs.last - g.xs.first, closeTo(400 * 0.84, 1e-6));
      expect(g.lengthMetres * g.unitsPerMetre, closeTo(400 * 0.84, 1e-3));
    });
  });
}
