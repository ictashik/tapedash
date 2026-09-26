import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/sim/drive_style.dart';
import 'package:tapedash/sim/driver.dart';
import 'package:tapedash/sim/driver_inputs.dart';
import 'package:tapedash/sim/ground_truth.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/sim_route.dart';
import 'package:tapedash/sim/vehicle_model.dart';

const _dt = VehicleModel.stepSeconds;

VehicleModel _car({SimRoute? route}) => VehicleModel(
  profile: VehicleProfiles.petrolCvtMaf,
  route: route,
  engineRunning: true,
  coolantC: 90,
);

/// Runs a plan until it finishes or [limit] seconds pass, calling [each] after
/// every step.
void _drive(
  VehicleModel car,
  List<DriveLeg> legs, {
  double limit = 600,
  void Function(VehicleSnapshot s)? each,
}) {
  final driver = ScriptedDriver(legs);
  var steps = 0;
  while (!driver.isFinished && steps < limit / _dt) {
    car.step(driver.decide(car));
    // The step on which the plan finishes is the driver holding still, not
    // the plan, so it is not shown to the observer.
    if (!driver.isFinished) each?.call(car.state);
    steps++;
  }
}

void main() {
  group('PedalController', () {
    test('a request for the coasting acceleration leaves both pedals up', () {
      final car = _car();
      for (var i = 0; i < 400; i++) {
        car.step(DriverInputs(throttle: car.pedalForAcceleration(0.8)));
      }
      final pedals = PedalController();

      final inputs = pedals.drive(
        car,
        car.accelerationFor(pedal: 0),
        DriveStyle.normal,
      );

      expect(inputs.throttle, 0);
      expect(inputs.brake, 0);
    });

    test(
      'a request to accelerate presses the accelerator, and one to slow down the brake',
      () {
        final car = _car();
        for (var i = 0; i < 400; i++) {
          car.step(DriverInputs(throttle: car.pedalForAcceleration(0.8)));
        }

        final accelerating = PedalController();
        final braking = PedalController();
        DriverInputs? a;
        DriverInputs? b;
        for (var i = 0; i < 40; i++) {
          a = accelerating.drive(car, 1.2, DriveStyle.hardDriving);
          b = braking.drive(car, -2.5, DriveStyle.hardDriving);
        }

        expect(a!.throttle, greaterThan(0.1));
        expect(a.brake, 0);
        expect(b!.brake, greaterThan(0.1));
        expect(b.throttle, 0);
      },
    );

    test('the pedals move no faster than the style allows', () {
      final car = _car();
      final gentle = PedalController();
      final hard = PedalController();
      final gentleFirst = gentle.drive(car, 3, DriveStyle.gentle);
      final hardFirst = hard.drive(car, 3, DriveStyle.hardDriving);

      expect(
        gentleFirst.throttle,
        lessThanOrEqualTo(DriveStyle.gentle.pedalRatePerSecond * _dt + 1e-12),
      );
      expect(
        hardFirst.throttle,
        lessThanOrEqualTo(
          DriveStyle.hardDriving.pedalRatePerSecond * _dt + 1e-12,
        ),
      );
      expect(hardFirst.throttle, greaterThan(gentleFirst.throttle));
    });

    test('the accelerator is released quickly even by a gentle driver', () {
      final car = _car();
      final pedals = PedalController();
      for (var i = 0; i < 200; i++) {
        pedals.drive(car, 3, DriveStyle.hardDriving);
      }
      var released = false;
      for (var i = 0; i < 12; i++) {
        final inputs = pedals.drive(
          car,
          car.accelerationFor(pedal: 0),
          DriveStyle.gentle,
        );
        if (inputs.throttle == 0) released = true;
      }

      expect(released, isTrue, reason: 'within 0.6 s');
    });

    test('it never presses both pedals at once', () {
      final car = _car();
      for (var i = 0; i < 300; i++) {
        car.step(DriverInputs(throttle: car.pedalForAcceleration(0.9)));
      }
      final pedals = PedalController();
      for (var i = 0; i < 100; i++) {
        pedals.drive(car, -3, DriveStyle.hardDriving);
      }
      for (var i = 0; i < 100; i++) {
        final inputs = pedals.drive(car, 1.5, DriveStyle.hardDriving);

        expect(inputs.throttle > 0 && inputs.brake > 0.02, isFalse);
      }
    });

    test('hold sets the brake and lifts the accelerator', () {
      final pedals = PedalController();

      expect(pedals.hold(brake: 0.6).brake, 0.6);
      expect(pedals.hold(brake: 0.6).throttle, 0);
      expect(pedals.hold(ignitionOn: false).ignitionOn, isFalse);
    });
  });

  group('IdleFor and IgnitionOffFor', () {
    test('IdleFor sits still for its time with the engine running', () {
      final car = _car();
      final start = car.state.timeSeconds;
      _drive(car, [IdleFor(30)]);

      expect(car.state.timeSeconds - start, closeTo(30, 0.1));
      expect(car.state.speedMs, 0);
      expect(car.state.engineRunning, isTrue);
    });

    test(
      'IgnitionOffFor stops the engine for its time, and the next leg restarts it',
      () {
        final car = _car();
        var sawOff = false;
        final states = <EngineState>[];
        _drive(
          car,
          [IgnitionOffFor(20), IdleFor(6)],
          each: (s) {
            if (s.engineState == EngineState.off) sawOff = true;
            if (states.isEmpty || states.last != s.engineState) {
              states.add(s.engineState);
            }
          },
        );

        expect(sawOff, isTrue);
        expect(states.last, EngineState.running);
        expect(
          states,
          containsAllInOrder([
            EngineState.off,
            EngineState.keyOn,
            EngineState.cranking,
            EngineState.running,
          ]),
        );
      },
    );
  });

  group('GoToSpeed', () {
    test('reaches the speed and holds it for the hold time', () {
      final car = _car();
      final holdSamples = <double>[];
      final driver = ScriptedDriver([GoToSpeed(60, holdSeconds: 20)]);
      double? reachedAt;
      while (!driver.isFinished) {
        car.step(driver.decide(car));
        if (reachedAt == null && (car.state.speedKmh - 60).abs() < 1.5) {
          reachedAt = car.state.timeSeconds;
        }
        if (reachedAt != null && car.state.timeSeconds > reachedAt + 3) {
          holdSamples.add(car.state.speedKmh);
        }
      }

      expect(reachedAt, isNotNull);
      expect(holdSamples, isNotEmpty);
      for (final v in holdSamples) {
        expect(v, closeTo(60, 1.5));
      }
    });

    test('slows down to a lower speed', () {
      final car = _car();
      _drive(car, [GoToSpeed(80), GoToSpeed(40, holdSeconds: 5)]);

      expect(car.state.speedKmh, closeTo(40, 2));
    });

    test(
      'a gentle driver takes longer than a hard one, and accelerates less',
      () {
        double timeTo(DriveStyle style) {
          final car = _car();
          var peak = 0.0;
          final driver = ScriptedDriver([GoToSpeed(50, style: style)]);
          while (!driver.isFinished) {
            car.step(driver.decide(car));
            if (!driver.isFinished) {
              peak = math.max(peak, car.state.accelerationMs2);
            }
          }
          expect(
            peak,
            lessThanOrEqualTo(style.accelerationMs2 + 0.35),
            reason: 'never much beyond what the style asks',
          );
          return car.state.timeSeconds;
        }

        expect(
          timeTo(DriveStyle.gentle),
          greaterThan(timeTo(DriveStyle.normal)),
        );
        expect(
          timeTo(DriveStyle.normal),
          greaterThan(timeTo(DriveStyle.hardDriving)),
        );
      },
    );

    test(
      'a hard driver is logged as a hard acceleration, and a gentle one is not',
      () {
        GroundTruth truthFor(DriveStyle style) {
          final car = _car();
          _drive(car, [GoToSpeed(60, style: style, holdSeconds: 2)]);
          return car.truth;
        }

        final hard = truthFor(DriveStyle.hardDriving);
        expect(hard.hardAccelerationCount, 1);
        expect(hard.events.single.peakAccelerationMs2, greaterThan(2.5));
        expect(hard.events.single.durationSeconds, greaterThan(1));
        expect(truthFor(DriveStyle.gentle).events, isEmpty);
        expect(truthFor(DriveStyle.normal).events, isEmpty);
      },
    );

    test('a hard driver slowing down is logged as hard braking', () {
      final car = _car();
      _drive(car, [
        GoToSpeed(80),
        GoToSpeed(10, style: DriveStyle.hardDriving, holdSeconds: 1),
      ]);

      final truth = car.truth;
      expect(truth.hardBrakingCount, 1);
      expect(
        truth.events
            .where((e) => e.type == TruthEventType.hardBraking)
            .single
            .peakAccelerationMs2,
        greaterThan(3.5),
      );
    });
  });

  group('StopFor', () {
    test('brakes to a stop and waits there for its time', () {
      final car = _car();
      var stoppedFor = 0.0;
      _drive(
        car,
        [GoToSpeed(50, holdSeconds: 3), StopFor(15)],
        each: (s) {
          if (s.speedMs == 0 && s.timeSeconds > 10) stoppedFor += _dt;
        },
      );

      expect(car.state.speedMs, 0);
      expect(stoppedFor, closeTo(15, 1));
    });

    test('never lets the speed go negative or the car roll on', () {
      final car = _car();
      var minSpeed = 1.0;
      _drive(car, [
        GoToSpeed(30, holdSeconds: 2),
        StopFor(5),
      ], each: (s) => minSpeed = math.min(minSpeed, s.speedMs));

      expect(minSpeed, greaterThanOrEqualTo(0));
    });
  });

  group('PullTo and LiftTo', () {
    test(
      'a pull holds the pedal flat until the speed is reached, and is a hard acceleration',
      () {
        final car = VehicleModel(
          profile: VehicleProfiles.petrolManualSporty,
          engineRunning: true,
          coolantC: 90,
        );
        var fastest = 0.0;
        _drive(car, [
          PullTo(100),
        ], each: (s) => fastest = math.max(fastest, s.speedKmh));

        expect(fastest, greaterThanOrEqualTo(99.5));
        expect(car.truth.hardAccelerationCount, 1);
      },
    );

    test('a lift coasts down to the speed with both pedals up', () {
      final car = VehicleModel(
        profile: VehicleProfiles.petrolManualSporty,
        engineRunning: true,
        coolantC: 90,
      );
      var brakeUsed = 0.0;
      var fuelCutSeen = false;
      _drive(
        car,
        [PullTo(100), LiftTo(60)],
        each: (s) {
          brakeUsed = math.max(brakeUsed, s.brake);
          if (s.fuelCut) fuelCutSeen = true;
        },
      );

      expect(car.state.speedKmh, lessThanOrEqualTo(60.5));
      expect(brakeUsed, 0);
      expect(fuelCutSeen, isTrue);
    });
  });

  group('RouteCruise', () {
    test('drives at the speed until it has gone the distance', () {
      final car = _car();
      _drive(car, [RouteCruise(untilDistanceM: 1500, kmh: 60)]);

      expect(car.state.distanceM, greaterThanOrEqualTo(1500));
      expect(car.state.distanceM, lessThan(1500 + 30));
      expect(car.state.speedKmh, closeTo(60, 2));
    });
  });

  group('RouteBlock', () {
    // A 400 m straight and a corner of radius 18 m, then the same again.
    SimRoute route() => SimRoute([
      const Straight(400),
      const Arc(radiusM: 18, turnDegrees: 90),
      const Straight(400),
      const Arc(radiusM: 18, turnDegrees: -90),
    ]);
    const arc = 18 * math.pi / 2;

    List<DriveLeg> blocks({
      DriveStyle style = DriveStyle.normal,
      double stop1 = 0,
      double stop2 = 0,
      double cruise = 50,
      double turn = 20,
    }) => [
      IdleFor(3),
      RouteBlock(
        straightEndM: 400,
        arcEndM: 400 + arc,
        cruiseKmh: cruise,
        turnKmh: turn,
        stopSeconds: stop1,
        style: style,
      ),
      RouteBlock(
        straightEndM: 800 + arc,
        arcEndM: 800 + 2 * arc,
        cruiseKmh: cruise,
        turnKmh: turn,
        stopSeconds: stop2,
        style: style,
      ),
    ];

    test(
      'stops at the end of the straight, not before and not far past it, and waits',
      () {
        final car = _car(route: route());
        var stopDistance = -1.0;
        var waited = 0.0;
        _drive(
          car,
          blocks(stop1: 25),
          each: (s) {
            if (s.speedMs == 0 && s.distanceM > 300 && s.distanceM < 420) {
              stopDistance = s.distanceM;
              waited += _dt;
            }
          },
        );

        expect(stopDistance, inInclusiveRange(392, 403));
        expect(waited, closeTo(25, 1.5));
      },
    );

    test('goes on through the bend and finishes the route', () {
      final car = _car(route: route());
      _drive(car, blocks(stop1: 10, stop2: 10));

      expect(car.state.distanceM, greaterThan(800 + 2 * arc - 3));
    });

    test('without a stop it arrives at the corner at the turning speed', () {
      final car = _car(route: route());
      var atCorner = -1.0;
      _drive(
        car,
        blocks(),
        each: (s) {
          if (atCorner < 0 && s.distanceM >= 400) atCorner = s.speedKmh;
        },
      );

      expect(atCorner, closeTo(20, 3));
    });

    test(
      'lateral acceleration in the bend is v squared over 18 m, well within grip',
      () {
        final car = _car(route: route());
        var peak = 0.0;
        _drive(
          car,
          blocks(),
          each: (s) => peak = math.max(peak, s.lateralAccelerationMs2.abs()),
        );

        expect(peak, inInclusiveRange(1.0, 2.5));
      },
    );

    test(
      'stops within a few metres of the stop line, and never runs past it, at any style',
      () {
        for (final style in [
          DriveStyle.gentle,
          DriveStyle.normal,
          DriveStyle.hardDriving,
        ]) {
          final car = _car(route: route());
          var furthest = 0.0;
          double? stoppedAt;
          _drive(
            car,
            blocks(style: style, stop1: 20),
            each: (s) {
              if (stoppedAt != null || s.timeSeconds > 200) return;
              furthest = math.max(furthest, s.distanceM);
              if (s.speedMs == 0 && s.distanceM > 300) stoppedAt = s.distanceM;
            },
          );

          expect(
            stoppedAt,
            inInclusiveRange(392, 404),
            reason: 'style with acceleration ${style.accelerationMs2}',
          );
          expect(furthest, lessThan(404), reason: '${style.accelerationMs2}');
        }
      },
    );

    test(
      'a hard driver brakes hard enough, for long enough, to be detected',
      () {
        final car = _car(route: route());
        var above = 0.0;
        var peak = 0.0;
        _drive(
          car,
          blocks(
            style: DriveStyle.hardDriving,
            stop1: 10,
            cruise: 58,
            turn: 24,
          ),
          each: (s) {
            if (s.timeSeconds < 60) {
              peak = math.max(peak, -s.accelerationMs2);
              if (-s.accelerationMs2 > 3.5) above += _dt;
            }
          },
        );

        expect(peak, greaterThan(3.5));
        expect(above, greaterThan(0.5));
      },
    );

    test(
      'a hard driver accelerates hard enough, for long enough, to be detected',
      () {
        final car = _car(route: route());
        var above = 0.0;
        var streak = 0.0;
        var longest = 0.0;
        _drive(
          car,
          blocks(
            style: DriveStyle.hardDriving,
            stop1: 10,
            stop2: 10,
            cruise: 58,
            turn: 24,
          ),
          each: (s) {
            if (s.accelerationMs2 > 2.5) {
              streak += _dt;
              above += _dt;
            } else {
              longest = math.max(longest, streak);
              streak = 0;
            }
          },
        );

        expect(longest, greaterThan(1));
        expect(above, greaterThan(1));
      },
    );

    test(
      'logs one hard acceleration and one hard braking per block for a hard driver',
      () {
        final car = _car(route: route());
        _drive(
          car,
          blocks(
            style: DriveStyle.hardDriving,
            stop1: 10,
            stop2: 10,
            cruise: 58,
            turn: 24,
          ),
        );

        final truth = car.truth;
        expect(truth.hardAccelerationCount, 2);
        expect(truth.hardBrakingCount, 2);
      },
    );

    test(
      'a gentle driver never comes near the hard thresholds and logs no events',
      () {
        final car = _car(route: route());
        var peakAccel = 0.0;
        var peakDecel = 0.0;
        _drive(
          car,
          blocks(
            style: DriveStyle.gentle,
            stop1: 10,
            stop2: 10,
            cruise: 45,
            turn: 18,
          ),
          each: (s) {
            peakAccel = math.max(peakAccel, s.accelerationMs2);
            peakDecel = math.max(peakDecel, -s.accelerationMs2);
          },
        );

        expect(peakAccel, lessThan(1.6));
        expect(peakDecel, lessThan(2.0));
        expect(car.truth.events, isEmpty);
      },
    );

    test('a gentle driver coasts before braking, with both pedals up', () {
      final car = _car(route: route());
      var coastSeconds = 0.0;
      _drive(
        car,
        blocks(style: DriveStyle.gentle, stop1: 10, cruise: 45),
        each: (s) {
          final beforeStop = s.distanceM > 250 && s.distanceM < 400;
          if (beforeStop &&
              s.speedKmh > 20 &&
              s.brake == 0 &&
              s.accelerationMs2 < 0) {
            coastSeconds += _dt;
          }
        },
      );

      expect(coastSeconds, greaterThan(1.5));
    });

    test('a normal driver does not coast early', () {
      final gentle = _car(route: route());
      final normal = _car(route: route());
      double coast(VehicleModel car, DriveStyle style) {
        var seconds = 0.0;
        _drive(
          car,
          blocks(style: style, stop1: 10, cruise: 45),
          each: (s) {
            final beforeStop = s.distanceM > 250 && s.distanceM < 400;
            if (beforeStop &&
                s.speedKmh > 20 &&
                s.brake == 0 &&
                s.accelerationMs2 < 0) {
              seconds += _dt;
            }
          },
        );
        return seconds;
      }

      expect(
        coast(gentle, DriveStyle.gentle),
        greaterThan(coast(normal, DriveStyle.normal)),
      );
    });
  });

  group('ScriptedDriver', () {
    test('runs its legs in order and finishes', () {
      final car = _car();
      final driver = ScriptedDriver([
        IdleFor(2),
        GoToSpeed(30, holdSeconds: 2),
        StopFor(2),
      ]);
      expect(driver.isFinished, isFalse);
      var maxSpeed = 0.0;
      var steps = 0;
      while (!driver.isFinished && steps++ < 4000) {
        car.step(driver.decide(car));
        maxSpeed = math.max(maxSpeed, car.state.speedKmh);
      }

      expect(driver.isFinished, isTrue);
      expect(maxSpeed, greaterThan(25));
    });

    test('holds the car still once the plan is done', () {
      final car = _car();
      final driver = ScriptedDriver([
        GoToSpeed(30, holdSeconds: 1),
        StopFor(1),
      ]);
      for (var i = 0; i < 1500; i++) {
        car.step(driver.decide(car));
      }

      expect(driver.isFinished, isTrue);
      expect(car.state.speedMs, 0);
      expect(driver.decide(car).brake, greaterThan(0));
    });

    test('an empty plan is finished at once and holds still', () {
      final driver = ScriptedDriver([]);

      expect(driver.isFinished, isTrue);
      expect(driver.decide(_car()).brake, greaterThan(0));
    });
  });
}
