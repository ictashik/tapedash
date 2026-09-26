import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/location/location_source.dart';
import 'package:tapedash/location/sim_location_source.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';

/// Metres from [a] to [b], on the flat: east and north.
(double, double) _offsetM(double lat1, double lon1, double lat2, double lon2) {
  const metresPerDegree = 111320.0;
  final north = (lat2 - lat1) * metresPerDegree;
  final east = (lon2 - lon1) * metresPerDegree * math.cos(lat1 * math.pi / 180);
  return (east, north);
}

/// A city drive with a GPS on it, run to its end, and each fix with the
/// truth it was a fix of.
class _Drive {
  _Drive({int seed = 1, String scenario = 'city_stop_go'}) {
    car = SimulatedCar(
      scenario: DriveScenarios.byName(scenario)!,
      scheduler: clock,
    )..start();
    gps = SimLocationSource(
      car: car,
      scheduler: clock,
      clock: clock,
      seed: seed,
    );
    gps.fixes.listen((fix) {
      fixes.add(fix);
      final onRoute = car.scenario.route.pointAt(car.state.distanceM);
      truth.add((onRoute.latitude, onRoute.longitude, car.state.speedMs));
      headings.add(onRoute.headingDegrees);
    });
  }

  final clock = FakeClock();
  late final SimulatedCar car;
  late final SimLocationSource gps;
  final List<LocationFix> fixes = [];
  final List<(double, double, double)> truth = [];
  final List<double> headings = [];

  Future<void> run(Duration duration) async {
    await gps.start();
    clock.advance(duration);
  }

  /// How far fix [i] is from where the car was.
  double errorM(int i) {
    final (east, north) = _offsetM(
      truth[i].$1,
      truth[i].$2,
      fixes[i].latitude,
      fixes[i].longitude,
    );
    return math.sqrt(east * east + north * north);
  }

  void close() {
    car.stop();
    gps.dispose();
  }
}

void main() {
  group('running', () {
    test('there is one fix a second, and none before start', () async {
      final drive = _Drive();
      addTearDown(drive.close);

      drive.clock.advance(const Duration(seconds: 5));
      expect(drive.fixes, isEmpty);

      await drive.run(const Duration(seconds: 10));

      expect(drive.fixes.length, 10);
      expect(drive.gps.isRunning, isTrue);
    });

    test('the fixes are stamped with the clock', () async {
      final drive = _Drive();
      addTearDown(drive.close);

      await drive.run(const Duration(seconds: 3));

      expect(
        drive.fixes.map((f) => f.time),
        [1, 2, 3].map((s) => DateTime.utc(2026).add(Duration(seconds: s))),
      );
    });

    test('stopping stops them, and starting again resumes', () async {
      final drive = _Drive();
      addTearDown(drive.close);
      await drive.run(const Duration(seconds: 5));

      await drive.gps.stop();
      drive.clock.advance(const Duration(seconds: 5));
      expect(drive.fixes.length, 5);
      expect(drive.gps.isRunning, isFalse);

      await drive.gps.start();
      drive.clock.advance(const Duration(seconds: 5));
      expect(drive.fixes.length, 10);
    });

    test('starting twice does not double the rate', () async {
      final drive = _Drive();
      addTearDown(drive.close);

      await drive.gps.start();
      await drive.gps.start();
      drive.clock.advance(const Duration(seconds: 10));

      expect(drive.fixes.length, 10);
    });

    test('nothing is left scheduled after it is stopped', () async {
      final drive = _Drive();
      await drive.run(const Duration(seconds: 3));

      drive.car.stop();
      await drive.gps.dispose();

      expect(drive.clock.pendingTasks, 0);
    });
  });

  group('the position', () {
    test('the fix at the start is by the start of the route', () async {
      final drive = _Drive();
      addTearDown(drive.close);
      await drive.run(const Duration(seconds: 1));

      final route = drive.car.scenario.route;
      final (east, north) = _offsetM(
        route.originLatitude,
        route.originLongitude,
        drive.fixes.first.latitude,
        drive.fixes.first.longitude,
      );

      expect(math.sqrt(east * east + north * north), lessThan(15));
    });

    test('it follows the car along the route', () async {
      final drive = _Drive();
      addTearDown(drive.close);
      await drive.run(const Duration(minutes: 10));

      // The car has gone a good way, and the last fix is near where it is.
      expect(drive.car.truth.distanceKm, greaterThan(1));
      expect(drive.errorM(drive.fixes.length - 1), lessThan(60));
      final last = drive.fixes.last;
      final route = drive.car.scenario.route;
      final (east, north) = _offsetM(
        route.originLatitude,
        route.originLongitude,
        last.latitude,
        last.longitude,
      );
      expect(math.sqrt(east * east + north * north), greaterThan(300));
    });

    test('a car that stops stays where it stopped', () async {
      final drive = _Drive(scenario: 'traffic_jam');
      addTearDown(drive.close);
      await drive.run(const Duration(minutes: 3));
      final stopped = [
        for (var i = 0; i < drive.fixes.length; i++)
          if (drive.truth[i].$3 == 0) i,
      ];

      // While at rest the truth does not move, so the fixes only wander.
      expect(stopped.length, greaterThan(10));
      final first = stopped.first;
      for (final i in stopped.where((i) => i < first + 10)) {
        expect(drive.errorM(i), lessThan(60));
      }
    });

    test(
      'the error is a few metres in the open, with a spread like GPS',
      () async {
        final drive = _Drive();
        addTearDown(drive.close);
        await drive.run(const Duration(minutes: 20));
        final open = [
          for (var i = 0; i < drive.fixes.length; i++)
            if (drive.fixes[i].accuracyM < 8) drive.errorM(i),
        ]..sort();

        expect(open.length, greaterThan(800));
        final median = open[open.length ~/ 2];
        final p95 = open[(open.length * 0.95).floor()];
        // 2D error with sigma 2.5 m per axis: median 2.9 m, 95% about 6 m.
        expect(median, inInclusiveRange(2.0, 4.0));
        expect(p95, lessThan(9));
      },
    );

    test('the error wanders: a fix is like the one before it', () async {
      final drive = _Drive();
      addTearDown(drive.close);
      await drive.run(const Duration(minutes: 20));

      // Take the error of each axis and correlate each fix with the next.
      final errors = <(double, double)>[];
      for (var i = 0; i < drive.fixes.length; i++) {
        errors.add(
          _offsetM(
            drive.truth[i].$1,
            drive.truth[i].$2,
            drive.fixes[i].latitude,
            drive.fixes[i].longitude,
          ),
        );
      }
      var sumProduct = 0.0;
      var sumSquare = 0.0;
      for (var i = 1; i < errors.length; i++) {
        sumProduct += errors[i].$1 * errors[i - 1].$1;
        sumSquare += errors[i - 1].$1 * errors[i - 1].$1;
      }

      expect(sumProduct / sumSquare, closeTo(0.85, 0.12));
    });
  });

  group('the accuracy it reports', () {
    test('it is honest: about two fixes in three are within it', () async {
      final drive = _Drive();
      addTearDown(drive.close);
      await drive.run(const Duration(minutes: 40));

      var within = 0;
      for (var i = 0; i < drive.fixes.length; i++) {
        if (drive.errorM(i) <= drive.fixes[i].accuracyM) within++;
      }

      expect(within / drive.fixes.length, closeTo(0.68, 0.08));
    });

    test(
      'there are spells of bad fixes, with the accuracy saying so',
      () async {
        final drive = _Drive();
        addTearDown(drive.close);
        await drive.run(const Duration(minutes: 40));

        final bad = [
          for (var i = 0; i < drive.fixes.length; i++)
            if (drive.fixes[i].accuracyM > 15) i,
        ];
        final good = [
          for (var i = 0; i < drive.fixes.length; i++)
            if (drive.fixes[i].accuracyM < 6) i,
        ];

        expect(bad, isNotEmpty);
        expect(bad.length / drive.fixes.length, lessThan(0.12));
        double mean(List<int> ids) =>
            ids.map(drive.errorM).reduce((a, b) => a + b) / ids.length;
        expect(mean(bad), greaterThan(4 * mean(good)));
      },
    );

    test('a spell of bad fixes lasts a few seconds, not one', () async {
      final drive = _Drive();
      addTearDown(drive.close);
      await drive.run(const Duration(minutes: 40));

      var longest = 0;
      var run = 0;
      for (final fix in drive.fixes) {
        run = fix.accuracyM > 15 ? run + 1 : 0;
        longest = math.max(longest, run);
      }

      expect(longest, greaterThanOrEqualTo(3));
    });

    test('it is never better than 2 m', () async {
      final drive = _Drive();
      addTearDown(drive.close);
      await drive.run(const Duration(minutes: 20));

      expect(
        drive.fixes.map((f) => f.accuracyM).reduce(math.min),
        greaterThanOrEqualTo(2),
      );
    });
  });

  group('speed and heading', () {
    test('the speed is the car\'s, with a little noise', () async {
      final drive = _Drive();
      addTearDown(drive.close);
      await drive.run(const Duration(minutes: 20));
      final errors = [
        for (var i = 0; i < drive.fixes.length; i++)
          if (drive.truth[i].$3 > 2) drive.fixes[i].speedMs - drive.truth[i].$3,
      ];

      final mean = errors.reduce((a, b) => a + b) / errors.length;
      final variance =
          errors.map((e) => (e - mean) * (e - mean)).reduce((a, b) => a + b) /
          errors.length;

      expect(mean.abs(), lessThan(0.02));
      expect(math.sqrt(variance), closeTo(0.12, 0.03));
    });

    test('at rest the speed is about zero, and never negative', () async {
      final drive = _Drive(scenario: 'traffic_jam');
      addTearDown(drive.close);
      await drive.run(const Duration(minutes: 3));

      for (var i = 0; i < drive.fixes.length; i++) {
        expect(drive.fixes[i].speedMs, greaterThanOrEqualTo(0));
        if (drive.truth[i].$3 == 0) {
          expect(drive.fixes[i].speedMs, lessThan(0.3));
        }
      }
    });

    test(
      'the heading is the road\'s while moving, and unknown at rest',
      () async {
        final drive = _Drive();
        addTearDown(drive.close);
        await drive.run(const Duration(minutes: 15));
        var moving = 0;
        var unknown = 0;

        for (var i = 0; i < drive.fixes.length; i++) {
          final heading = drive.fixes[i].headingDegrees;
          if (drive.truth[i].$3 > 1) {
            moving++;
            expect(heading, isNotNull);
            var difference = (heading! - drive.headings[i]).abs() % 360;
            if (difference > 180) difference = 360 - difference;
            expect(difference, lessThan(8));
          } else if (drive.truth[i].$3 < 0.1) {
            unknown++;
            expect(heading, isNull);
          }
        }

        expect(moving, greaterThan(100));
        expect(unknown, greaterThan(10));
      },
    );

    test('the heading is always within 0 to 360', () async {
      final drive = _Drive();
      addTearDown(drive.close);
      await drive.run(const Duration(minutes: 15));

      for (final fix in drive.fixes) {
        final heading = fix.headingDegrees;
        if (heading != null) {
          expect(heading, inInclusiveRange(0, 360));
        }
      }
    });

    test('the altitude is about that of the road', () async {
      final drive = _Drive();
      addTearDown(drive.close);
      await drive.run(const Duration(minutes: 10));

      for (final fix in drive.fixes) {
        expect(fix.altitudeM, closeTo(920, 12));
      }
    });
  });

  group('determinism', () {
    test('the same seed gives the same fixes', () async {
      final a = _Drive(seed: 4);
      final b = _Drive(seed: 4);
      addTearDown(a.close);
      addTearDown(b.close);
      await a.run(const Duration(minutes: 5));
      await b.run(const Duration(minutes: 5));

      expect(
        a.fixes.map((f) => (f.latitude, f.longitude, f.accuracyM)),
        b.fixes.map((f) => (f.latitude, f.longitude, f.accuracyM)),
      );
    });

    test('another seed gives other noise on the same drive', () async {
      final a = _Drive(seed: 4);
      final b = _Drive(seed: 5);
      addTearDown(a.close);
      addTearDown(b.close);
      await a.run(const Duration(minutes: 5));
      await b.run(const Duration(minutes: 5));

      expect(a.fixes.first.latitude, isNot(b.fixes.first.latitude));
      // The car itself is the same.
      expect(a.car.truth.distanceKm, b.car.truth.distanceKm);
    });
  });
}
