import 'dart:math' as math;

import 'drive_style.dart';
import 'driver_inputs.dart';
import 'vehicle_model.dart';

/// Something that drives the simulated car: it looks at the car and decides the
/// inputs for the next step.
abstract interface class Driver {
  DriverInputs decide(VehicleModel car);

  /// True once the plan is complete. The car is then held still.
  bool get isFinished;
}

/// How firmly a driver corrects a speed error, per second.
const double _speedGain = 0.7;

/// Turns the acceleration a driver wants into pedal positions.
///
/// It asks the car which pedal gives that acceleration, so it holds a speed
/// smoothly, and moves the pedals no faster than the [DriveStyle] allows. That
/// pace, together with the acceleration asked for, is what makes one driver
/// gentle and another hard.
class PedalController {
  double _pedal = 0;
  double _brake = 0;

  void reset() {
    _pedal = 0;
    _brake = 0;
  }

  /// The inputs that give [acceleration] (negative to slow down), carrying
  /// [intent] so the ground truth can log scripted hard driving.
  DriverInputs drive(
    VehicleModel car,
    double acceleration,
    DriveStyle style, {
    DriverIntent intent = DriverIntent.normal,
  }) {
    const dt = VehicleModel.stepSeconds;
    final coast = car.accelerationFor(pedal: 0);
    var pedalGoal = 0.0;
    var brakeGoal = 0.0;
    if (acceleration > coast + 0.03) {
      pedalGoal = car.pedalForAcceleration(acceleration);
    } else if (acceleration < coast - 0.05) {
      brakeGoal = car.brakeForDeceleration(-acceleration);
    }

    _pedal = _approach(
      _pedal,
      pedalGoal,
      up: style.pedalRatePerSecond * dt,
      down: math.max(style.pedalRatePerSecond, 4) * dt,
    );
    _brake = _approach(
      _brake,
      brakeGoal,
      up: style.brakeRatePerSecond * dt,
      down: math.max(style.brakeRatePerSecond, 4) * dt,
    );
    // Do not drive against the brakes.
    if (_brake > 0.02 && pedalGoal > 0) _pedal = 0;

    return DriverInputs(throttle: _pedal, brake: _brake, intent: intent);
  }

  /// Holds the brake at [brake] with the pedal up.
  DriverInputs hold({double brake = 0.4, bool ignitionOn = true}) {
    _pedal = 0;
    _brake = brake;
    return DriverInputs(brake: brake, ignitionOn: ignitionOn);
  }

  static double _approach(
    double value,
    double goal, {
    required double up,
    required double down,
  }) {
    if (goal > value) return math.min(goal, value + up);
    return math.max(goal, value - down);
  }
}

/// One stage of a drive.
abstract class DriveLeg {
  /// Called once, as the leg begins.
  void start(VehicleModel car) {}

  /// The inputs for the next step, or null when the leg is over.
  DriverInputs? update(VehicleModel car, PedalController pedals);
}

DriverIntent _intentFor(double acceleration, DriveStyle style) {
  if (!style.hard) return DriverIntent.normal;
  if (acceleration > 0.6 * style.accelerationMs2) {
    return DriverIntent.hardAcceleration;
  }
  if (acceleration < -0.6 * style.brakeDecelerationMs2) {
    return DriverIntent.hardBraking;
  }
  return DriverIntent.normal;
}

/// Sits with the brake held and the engine running, for [seconds].
class IdleFor extends DriveLeg {
  IdleFor(this.seconds, {this.brake = 0.35});

  final double seconds;
  final double brake;
  late double _endsAt;

  @override
  void start(VehicleModel car) => _endsAt = car.state.timeSeconds + seconds;

  @override
  DriverInputs? update(VehicleModel car, PedalController pedals) =>
      car.state.timeSeconds >= _endsAt ? null : pedals.hold(brake: brake);
}

/// Switches the ignition off for [seconds], holding the brake.
class IgnitionOffFor extends DriveLeg {
  IgnitionOffFor(this.seconds);

  final double seconds;
  late double _endsAt;

  @override
  void start(VehicleModel car) => _endsAt = car.state.timeSeconds + seconds;

  @override
  DriverInputs? update(VehicleModel car, PedalController pedals) =>
      car.state.timeSeconds >= _endsAt
      ? null
      : pedals.hold(brake: 0.5, ignitionOn: false);
}

/// Brakes to a stop and waits there for [seconds].
class StopFor extends DriveLeg {
  StopFor(this.seconds, {this.style = DriveStyle.normal});

  final double seconds;
  final DriveStyle style;
  bool _stopped = false;
  late double _endsAt;

  @override
  void start(VehicleModel car) => _stopped = false;

  @override
  DriverInputs? update(VehicleModel car, PedalController pedals) {
    final s = car.state;
    if (!_stopped && s.speedMs < 0.06) {
      _stopped = true;
      _endsAt = s.timeSeconds + seconds;
    }
    if (_stopped) {
      return s.timeSeconds >= _endsAt ? null : pedals.hold(brake: 0.4);
    }
    // Ease off the brake as the car comes to rest, so it does not stop dead.
    final wanted = -math.min(
      style.brakeDecelerationMs2,
      math.max(0.4, s.speedMs / 0.8),
    );
    return pedals.drive(car, wanted, style, intent: _intentFor(wanted, style));
  }
}

/// Goes to [kmh], up or down, and holds it for [holdSeconds].
class GoToSpeed extends DriveLeg {
  GoToSpeed(this.kmh, {this.style = DriveStyle.normal, this.holdSeconds = 0});

  final double kmh;
  final DriveStyle style;
  final double holdSeconds;
  bool _holding = false;
  late double _holdEndsAt;

  @override
  void start(VehicleModel car) => _holding = false;

  @override
  DriverInputs? update(VehicleModel car, PedalController pedals) {
    final s = car.state;
    final error = kmh / 3.6 - s.speedMs;
    if (!_holding && error.abs() < 0.4) {
      _holding = true;
      _holdEndsAt = s.timeSeconds + holdSeconds;
    }
    if (_holding && s.timeSeconds >= _holdEndsAt) return null;

    final wanted = (_speedGain * error).clamp(
      -style.brakeDecelerationMs2,
      style.accelerationMs2,
    );
    return pedals.drive(car, wanted, style, intent: _intentFor(wanted, style));
  }
}

/// Puts the pedal flat until [kmh] is reached. It is the "pull" of a spirited
/// drive, and is logged as a hard acceleration.
class PullTo extends DriveLeg {
  PullTo(this.kmh);

  final double kmh;

  @override
  DriverInputs? update(VehicleModel car, PedalController pedals) {
    if (car.state.speedKmh >= kmh) return null;
    pedals.reset();
    return const DriverInputs(
      throttle: 1,
      intent: DriverIntent.hardAcceleration,
    );
  }
}

/// Lifts off and lets the car slow to [kmh] on engine braking and drag alone.
class LiftTo extends DriveLeg {
  LiftTo(this.kmh);

  final double kmh;

  @override
  DriverInputs? update(VehicleModel car, PedalController pedals) {
    if (car.state.speedKmh <= kmh) return null;
    return pedals.hold(brake: 0);
  }
}

/// Drives at [kmh] until the car has gone [untilDistanceM] along the route.
class RouteCruise extends DriveLeg {
  RouteCruise({
    required this.untilDistanceM,
    required this.kmh,
    this.style = DriveStyle.normal,
  });

  final double untilDistanceM;
  final double kmh;
  final DriveStyle style;

  @override
  DriverInputs? update(VehicleModel car, PedalController pedals) {
    final s = car.state;
    if (s.distanceM >= untilDistanceM) return null;
    final wanted = (_speedGain * (kmh / 3.6 - s.speedMs)).clamp(
      -style.brakeDecelerationMs2,
      style.accelerationMs2,
    );
    return pedals.drive(car, wanted, style, intent: _intentFor(wanted, style));
  }
}

enum _BlockPhase { approach, waiting, turning }

/// One city block: drive along a straight to a turn, slowing to a stop or to
/// the turning speed by planning the braking from the distance left, then go
/// round the bend.
///
/// The distances are along the route, so the plan stays lined up with the road
/// however the car is driven. With a [DriveStyle.hard] style the run-up is a
/// hard acceleration and the approach a hard braking, one of each per block,
/// and the ground truth logs them. A [DriveStyle.coastEarly] driver lifts off
/// well ahead and coasts down.
class RouteBlock extends DriveLeg {
  RouteBlock({
    required this.straightEndM,
    required this.arcEndM,
    required this.cruiseKmh,
    this.turnKmh = 20,
    this.stopSeconds = 0,
    this.style = DriveStyle.normal,
  });

  /// Where the straight ends and the bend begins, and where the bend ends.
  final double straightEndM;
  final double arcEndM;

  final double cruiseKmh;
  final double turnKmh;

  /// How long to wait at the end of the straight, at a signal or sign. Zero
  /// means drive on through the bend.
  final double stopSeconds;

  final DriveStyle style;

  _BlockPhase _phase = _BlockPhase.approach;
  late double _waitEndsAt;

  @override
  void start(VehicleModel car) => _phase = _BlockPhase.approach;

  @override
  DriverInputs? update(VehicleModel car, PedalController pedals) {
    final s = car.state;
    switch (_phase) {
      case _BlockPhase.approach:
        return _approach(car, pedals);
      case _BlockPhase.waiting:
        if (s.timeSeconds >= _waitEndsAt) {
          _phase = _BlockPhase.turning;
          return _turn(car, pedals);
        }
        return pedals.hold(brake: 0.4);
      case _BlockPhase.turning:
        return _turn(car, pedals);
    }
  }

  DriverInputs? _approach(VehicleModel car, PedalController pedals) {
    final s = car.state;
    final v = s.speedMs;
    final remaining = straightEndM - s.distanceM;
    final stopping = stopSeconds > 0;
    final endSpeed = stopping ? 0.0 : turnKmh / 3.6;

    if (stopping && v < 0.06 && remaining < 15) {
      _phase = _BlockPhase.waiting;
      _waitEndsAt = s.timeSeconds + stopSeconds;
      return pedals.hold(brake: 0.4);
    }
    if (!stopping && remaining <= 0) {
      _phase = _BlockPhase.turning;
      return _turn(car, pedals);
    }

    final brakingIntent = style.hard
        ? DriverIntent.hardBraking
        : DriverIntent.normal;
    final plannedBrake = style.brakeDecelerationMs2 * 0.9;
    final brakingDistance = v > endSpeed
        ? (v * v - endSpeed * endSpeed) / (2 * plannedBrake)
        : 0.0;
    final cruise = cruiseKmh / 3.6;

    if (stopping) {
      // Past the line and still moving: stop at once.
      if (remaining <= 0 && v > 0.06) {
        return pedals.drive(
          car,
          -style.brakeDecelerationMs2 * 1.1,
          style,
          intent: brakingIntent,
        );
      }
      // Close to the line and nearly stopped: come to rest without creeping
      // on, gently for an ordinary driver and firmly for a hard one.
      if (remaining < 6 && v < 1.0) {
        final least = style.hard ? 1.5 : 0.4;
        final settle = style.hard ? 0.3 : 0.8;
        return pedals.drive(
          car,
          -math.min(style.brakeDecelerationMs2, math.max(least, v / settle)),
          style,
          intent: brakingIntent,
        );
      }
    }

    if (remaining <= brakingDistance + 2 && v > endSpeed - 0.3) {
      // Brake so as to arrive at the end speed exactly at the end.
      final wanted = v > endSpeed
          ? (-(v * v - endSpeed * endSpeed) / (2 * math.max(remaining, 0.5)))
                .clamp(-style.brakeDecelerationMs2 * 1.1, 0.0)
          : (_speedGain * (endSpeed - v)).clamp(-1.0, 1.0);
      // One hard braking, from the first hard press until the car has slowed to
      // its target, however the wanted deceleration varies on the way.
      return pedals.drive(
        car,
        wanted,
        style,
        intent: v > endSpeed + 0.5 ? brakingIntent : DriverIntent.normal,
      );
    }
    if (style.coastEarly &&
        remaining <= brakingDistance + 3.0 * v + 2 &&
        v > endSpeed + 0.5) {
      // Lift off early and let the car run down.
      return pedals.drive(car, car.accelerationFor(pedal: 0), style);
    }
    final wanted = (_speedGain * (cruise - v)).clamp(
      -style.brakeDecelerationMs2,
      style.accelerationMs2,
    );
    return pedals.drive(car, wanted, style, intent: _intentFor(wanted, style));
  }

  DriverInputs? _turn(VehicleModel car, PedalController pedals) {
    final s = car.state;
    if (s.distanceM >= arcEndM) return null;
    // Round the bend at the turning speed, in the driver's own style but never
    // with a hard pull: the hard acceleration is the one on the next straight.
    final turnStyle = style.hard ? DriveStyle.normal : style;
    final wanted = (_speedGain * (turnKmh / 3.6 - s.speedMs)).clamp(
      -turnStyle.brakeDecelerationMs2,
      turnStyle.accelerationMs2,
    );
    return pedals.drive(car, wanted, turnStyle);
  }
}

/// Drives the legs of a plan one after another.
class ScriptedDriver implements Driver {
  ScriptedDriver(this.legs);

  final List<DriveLeg> legs;
  final PedalController _pedals = PedalController();
  int _index = 0;
  bool _started = false;

  @override
  bool get isFinished => _index >= legs.length;

  @override
  DriverInputs decide(VehicleModel car) {
    while (_index < legs.length) {
      final leg = legs[_index];
      if (!_started) {
        leg.start(car);
        _started = true;
      }
      final inputs = leg.update(car, _pedals);
      if (inputs != null) return inputs;
      _index++;
      _started = false;
    }
    // Plan finished: hold still.
    return _pedals.hold();
  }
}
