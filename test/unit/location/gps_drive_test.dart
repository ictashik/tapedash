// The drive on the phone's GPS alone (CLAUDE.md 6, 7): the receiver's speed on the
// vehicle, a distance and a time worked out from it, and the words for where it
// has got to. Hand-driven fixes for the rules, and the simulator's car for the
// truth.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/location/gps_drive.dart';
import 'package:tapedash/location/sim_location_source.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../../support/fake_location.dart';

void main() {
  late FakeClock clock;
  late FakeLocation location;
  late GpsDrive gps;

  setUp(() {
    clock = FakeClock()..advance(const Duration(seconds: 100));
    location = FakeLocation();
    gps = GpsDrive(location: location, clock: clock, scheduler: clock);
  });

  tearDown(() async {
    await gps.dispose();
    await location.close();
  });

  /// A fix a second after the last, with the clock moving on with it.
  void fix(double kmh, {double accuracyM = 5, double? heading}) {
    clock.advance(const Duration(seconds: 1));
    location.emit(kmh: kmh, accuracyM: accuracyM, heading: heading);
  }

  group('starting', () {
    test('it asks the receiver, and looks for a fix', () async {
      expect(gps.phase.value, GpsPhase.starting);
      await gps.start();
      expect(location.started, 1);
      expect(gps.phase.value, GpsPhase.searching);
      fix(0);
      expect(gps.phase.value, GpsPhase.tracking);
    });

    test(
      'a refused permission is said, and starting again can succeed',
      () async {
        location.permission = false;
        await gps.start();
        expect(gps.phase.value, GpsPhase.needsPermission);
        expect(gps.vehicle.speed.value, isNull, reason: 'nothing invented');

        location.permission = true;
        await gps.start();
        expect(gps.phase.value, GpsPhase.searching);
        fix(40);
        expect(gps.phase.value, GpsPhase.tracking);
      },
    );

    test('a phone with no GPS receiver is said', () async {
      location.unavailable = true;
      await gps.start();
      expect(gps.phase.value, GpsPhase.unavailable);
    });

    test('a fix gone stale is searching again, not tracking', () async {
      await gps.start();
      fix(30);
      expect(gps.phase.value, GpsPhase.tracking);
      clock.advance(const Duration(seconds: 6));
      expect(gps.phase.value, GpsPhase.searching);
    });
  });

  group('the speed', () {
    test('is the receiver\'s, in km/h, on the vehicle', () async {
      await gps.start();
      fix(54);
      expect(gps.vehicle.speed.value!.value, closeTo(54, 0.01));
    });

    test('drift at a standstill is zero, not a crawl', () async {
      await gps.start();
      fix(0.9); // about a quarter of a metre a second
      expect(gps.vehicle.speed.value!.value, 0);
    });

    test('a fix that does not know where it is is not used', () async {
      await gps.start();
      fix(60, accuracyM: 400);
      expect(gps.vehicle.speed.value, isNull);
    });

    test(
      'moving then standing makes Motion then Parked, on the vehicle',
      () async {
        await gps.start();
        for (var i = 0; i < 5; i++) {
          fix(50);
        }
        expect(gps.vehicle.mode.value, DrivingMode.motion);
        for (var i = 0; i < 8; i++) {
          fix(0);
        }
        expect(gps.vehicle.mode.value, DrivingMode.parked);
      },
    );

    test('heading is known while moving and not while standing', () async {
      await gps.start();
      fix(40, heading: 92);
      expect(gps.heading.value, 92);
      fix(0, heading: 92);
      expect(gps.heading.value, isNull);
    });
  });

  group('the figures', () {
    test('distance is the speed over time, not the positions', () async {
      await gps.start();
      // Ten seconds at 36 km/h (10 m/s), the positions never changing: the
      // distance comes from the speed.
      for (var i = 0; i < 11; i++) {
        fix(36);
      }
      final f = gps.figures.value;
      expect(f.distanceKm, closeTo(0.100, 0.002));
      expect(f.movingTime, const Duration(seconds: 10));
      expect(f.maxKmh, closeTo(36, 0.01));
      expect(f.averageKmh, closeTo(36, 0.5));
    });

    test('standing still adds no distance and no moving time', () async {
      await gps.start();
      for (var i = 0; i < 30; i++) {
        fix(0.4);
      }
      expect(gps.figures.value.distanceKm, 0);
      expect(gps.figures.value.movingTime, Duration.zero);
      expect(
        gps.figures.value.averageKmh,
        isNull,
        reason: 'nothing to average',
      );
    });

    test('a gap longer than five seconds is not driven over', () async {
      await gps.start();
      fix(72);
      fix(72);
      final before = gps.figures.value.distanceKm;
      clock.advance(const Duration(seconds: 30));
      location.emit(kmh: 72, after: const Duration(seconds: 30));
      expect(gps.figures.value.distanceKm, before, reason: 'a tunnel');
      fix(72);
      expect(gps.figures.value.distanceKm, greaterThan(before));
    });

    test('the fastest comes only from a fix that knows where it is', () async {
      await gps.start();
      fix(50);
      fix(120, accuracyM: 60);
      expect(gps.figures.value.maxKmh, closeTo(50, 0.01));
    });

    test(
      'Reset trip puts them back to nothing, and the drive carries on',
      () async {
        await gps.start();
        for (var i = 0; i < 6; i++) {
          fix(36);
        }
        expect(gps.figures.value.distanceKm, greaterThan(0));
        gps.resetTrip();
        expect(gps.figures.value, const GpsFigures());
        fix(36);
        fix(36);
        expect(gps.figures.value.distanceKm, greaterThan(0));
        expect(gps.figures.value.distanceKm, lessThan(0.05));
      },
    );
  });

  test(
    'over a simulated city drive the distance is the car\'s, within 3%',
    () async {
      final car = SimulatedCar(
        scenario: DriveScenarios.cityStopGo,
        scheduler: clock,
      )..start();
      final source = SimLocationSource(
        car: car,
        scheduler: clock,
        clock: clock,
      );
      final drive = GpsDrive(location: source, clock: clock, scheduler: clock);
      addTearDown(() async {
        car.stop();
        await drive.dispose();
      });
      await drive.start();
      clock.advance(const Duration(minutes: 12));

      final truth = car.truth.distanceKm;
      expect(truth, greaterThan(2), reason: 'it was a real drive');
      expect(drive.figures.value.distanceKm, closeTo(truth, truth * 0.03));
      expect(drive.phase.value, GpsPhase.tracking);
      expect(drive.figures.value.maxKmh, greaterThan(30));
      expect(drive.figures.value.maxKmh, lessThan(80));
    },
  );
}
