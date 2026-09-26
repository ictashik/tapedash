import 'dart:math' as math;

import 'driver_inputs.dart';
import 'engine_model.dart';
import 'ground_truth.dart';
import 'sim_random.dart';
import 'sim_route.dart';
import 'vehicle_profile.dart';

/// Where the engine is in its start-up.
enum EngineState {
  /// Ignition off.
  off,

  /// Ignition on, engine not turning yet.
  keyOn,

  cranking,
  running,
}

/// Everything the simulated car is doing at one instant, in SI units.
class VehicleSnapshot {
  const VehicleSnapshot({
    required this.timeSeconds,
    required this.ignitionOn,
    required this.engineState,
    required this.speedMs,
    required this.distanceM,
    required this.accelerationMs2,
    required this.lateralAccelerationMs2,
    required this.rpm,
    required this.throttleFraction,
    required this.loadFraction,
    required this.manifoldKpa,
    required this.airGramsPerSecond,
    required this.fuelGramsPerSecond,
    required this.fuelRateLitresPerHour,
    required this.coolantC,
    required this.intakeAirC,
    required this.voltage,
    required this.fuelLevelFraction,
    required this.fuelCut,
    required this.gear,
    required this.brake,
  });

  final double timeSeconds;
  final bool ignitionOn;
  final EngineState engineState;

  final double speedMs;
  final double distanceM;

  /// Longitudinal acceleration over the last step, m/s2.
  final double accelerationMs2;

  /// Sideways acceleration, m/s2, positive when the car is turning left.
  final double lateralAccelerationMs2;

  final double rpm;

  /// The throttle position PID's value, 0 to 1.
  final double throttleFraction;

  /// Calculated engine load, 0 to 1.
  final double loadFraction;

  final double manifoldKpa;

  /// Air through the intake, g/s: what a MAF sensor reads.
  final double airGramsPerSecond;

  /// Fuel injected, g/s.
  final double fuelGramsPerSecond;

  /// Fuel injected, in litres an hour: what PID 5E reads.
  final double fuelRateLitresPerHour;

  final double coolantC;
  final double intakeAirC;
  final double voltage;
  final double fuelLevelFraction;

  /// True while the fuel is cut off on the overrun or by the rev limiter.
  final bool fuelCut;

  /// The gear a manual car is in. Zero for a CVT, and while the clutch is out.
  final int gear;

  /// Brake pedal, 0 to 1.
  final double brake;

  double get speedKmh => speedMs * 3.6;

  bool get engineRunning => engineState == EngineState.running;
}

class _OpenEvent {
  _OpenEvent(this.type, this.startSeconds, this.startSpeedKmh);

  final TruthEventType type;
  final double startSeconds;
  final double startSpeedKmh;
  double peak = 0;
}

/// What one step of the powertrain works out. Nothing is changed by computing
/// one, so the driver can also ask what would happen with other pedals.
class _Drive {
  const _Drive({
    required this.rpm,
    required this.gear,
    required this.shiftRemaining,
    required this.sinceShift,
    required this.fuelCut,
    required this.demand,
    required this.output,
    required this.driveForceN,
  });

  final double rpm;
  final int gear;
  final double shiftRemaining;
  final double sinceShift;
  final bool fuelCut;
  final double demand;
  final EngineOutput output;

  /// Force at the wheels from the engine and the torque converter, N.
  final double driveForceN;
}

/// A simple physical car (CLAUDE.md 7.1).
///
/// It is deterministic for a seed and a stream of [DriverInputs], and steps at a
/// fixed [stepSeconds]. It keeps exact ground truth, so tests can compare the
/// app's estimates with what really happened.
///
/// MAF, MAP and the fuel rate come from one run of the engine model, so they are
/// physically consistent, and the car's acceleration comes from the same
/// torque, so a hard pull burns hard.
class VehicleModel {
  VehicleModel({
    required this.profile,
    this.seed = 1,
    SimRoute? route,
    this.ambientC = 30,
    double? coolantC,
    double fuelLevelFraction = 0.7,
    bool engineRunning = false,
  }) : route = route ?? SimRoute.straight(1000000),
       _engine = EngineModel.forSpec(profile.engine),
       _random = SimRandom(seed).fork(1) {
    _coolantC = coolantC ?? ambientC;
    _intakeAirC = ambientC;
    _fuelStartLitres = profile.tankLitres * fuelLevelFraction;
    _wobblePhase = _random.nextDouble() * 2 * math.pi;
    _ripplePhase = _random.nextDouble() * 2 * math.pi;
    _output = _engine.run(
      rpm: 0,
      demand: 0,
      intakeAirC: ambientC,
      fuelCut: true,
    );
    if (engineRunning) {
      _ignition = true;
      _state = EngineState.running;
      _runSeconds = 600;
      _rpm = profile.idleRpm;
      _gear = profile.transmission is ManualTransmission ? 1 : 0;
      _refreshGovernor();
      _output = _engine.run(
        rpm: _rpm,
        demand: _governorDemand,
        intakeAirC: _intakeAirC,
        frictionScale: _frictionScale(),
      );
    }
  }

  /// The fixed time step, 50 ms (CLAUDE.md 7.1).
  static const double stepSeconds = 0.05;

  final VehicleProfile profile;
  final int seed;
  final SimRoute route;
  final double ambientC;

  final EngineModel _engine;
  final SimRandom _random;

  // Engine start-up.
  bool _ignition = false;
  EngineState _state = EngineState.off;
  double _keyOnSeconds = 0;
  double _crankSeconds = 0;
  double _runSeconds = 0;

  // Motion.
  double _timeSeconds = 0;
  double _speedMs = 0;
  double _distanceM = 0;
  double _accelerationMs2 = 0;
  double _lateralMs2 = 0;

  // Powertrain.
  double _rpm = 0;
  int _gear = 0;
  double _shiftRemaining = 0;
  double _sinceShift = 10;
  bool _fuelCut = false;
  double _governorDemand = 0;
  double _brake = 0;
  late EngineOutput _output;
  double _demand = 0;

  // Thermal, electrical and fuel.
  late double _coolantC;
  late double _intakeAirC;
  double _voltage = 12.4;
  late final double _fuelStartLitres;
  double _fuelUsedLitres = 0;

  // A little idle wobble and electrical ripple, from the seed.
  late final double _wobblePhase;
  late final double _ripplePhase;

  // Ground truth.
  double _truthFuelLitres = 0;
  double _engineOnSeconds = 0;
  double _idleSeconds = 0;
  double _idleFuelLitres = 0;
  final List<TruthEvent> _closedEvents = [];
  _OpenEvent? _openEvent;

  // What the idle governor does, and the torque it covers.
  static const double _idleLoadNm = 1.5;

  // Coolant heat balance: the engine's thermal mass, the share of fuel energy
  // that goes into the coolant, and what carries it away.
  static const double _heatCapacityJoulesPerKelvin = 40000;
  static const double _heatToCoolant = 0.32;
  static const double _ambientLossWattsPerKelvin = 12;
  static const double _airflowLossWattsPerKelvinPerMs = 6;
  static const double _thermostatC = 89;
  static const double _radiatorLossWattsPerKelvin = 5000;

  static const double _gravity = 9.81;
  static const double _airDensity = 1.2;
  static const double _keyOnDelaySeconds = 1.5;
  static const double _crankSecondsToStart = 0.9;

  /// A snapshot of the car as it is now.
  VehicleSnapshot get state {
    final running = _state == EngineState.running;
    final density = profile.fuel.densityGramsPerLitre;
    return VehicleSnapshot(
      timeSeconds: _timeSeconds,
      ignitionOn: _ignition,
      engineState: _state,
      speedMs: _speedMs,
      distanceM: _distanceM,
      accelerationMs2: _accelerationMs2,
      lateralAccelerationMs2: _lateralMs2,
      rpm: _reportedRpm(),
      throttleFraction: running
          ? _engine.reportedThrottleFraction(_demand)
          : _engine.reportedThrottleFraction(0),
      loadFraction: running ? _output.loadFraction : 0,
      manifoldKpa: running ? _output.manifoldKpa : atmosphereKpa,
      airGramsPerSecond: running ? _output.airGramsPerSecond : 0,
      fuelGramsPerSecond: running ? _output.fuelGramsPerSecond : 0,
      fuelRateLitresPerHour: running
          ? _output.fuelGramsPerSecond * 3600 / density
          : 0,
      coolantC: _coolantC,
      intakeAirC: _intakeAirC,
      voltage: _voltage,
      fuelLevelFraction: _fuelLevelFraction,
      fuelCut: running && _fuelCut,
      gear: _shiftRemaining > 0 ? 0 : _gear,
      brake: _brake,
    );
  }

  /// The ground truth so far.
  GroundTruth get truth {
    final open = _openEvent;
    return GroundTruth(
      fuelLitres: _truthFuelLitres,
      distanceKm: _distanceM / 1000,
      engineOnSeconds: _engineOnSeconds,
      idleSeconds: _idleSeconds,
      idleFuelLitres: _idleFuelLitres,
      events: List.unmodifiable([
        ..._closedEvents,
        if (open != null)
          TruthEvent(
            type: open.type,
            startSeconds: open.startSeconds,
            startSpeedKmh: open.startSpeedKmh,
            peakAccelerationMs2: open.peak,
          ),
      ]),
    );
  }

  double get _fuelLeftLitres => _fuelStartLitres - _fuelUsedLitres;

  double get _fuelLevelFraction =>
      (_fuelLeftLitres / profile.tankLitres).clamp(0.0, 1.0);

  /// Idle speed: the warm idle plus a fast idle that fades over the first
  /// minute or two after starting, and only when the engine is cold.
  double get _idleTargetRpm {
    final cold = ((80 - _coolantC) / 50).clamp(0.0, 1.0);
    return profile.idleRpm + 450 * cold * math.exp(-_runSeconds / 90);
  }

  double _frictionScale() => 1 + 0.35 * ((90 - _coolantC) / 60).clamp(0.0, 1.0);

  double _reportedRpm() {
    if (_state != EngineState.running || _rpm <= 0) return _rpm;
    // A gentle idle wobble that dies away as the revs rise.
    final amplitude = 7 * ((1400 - _rpm) / 700).clamp(0.0, 1.0);
    return _rpm +
        amplitude * math.sin(2 * math.pi * 0.7 * _timeSeconds + _wobblePhase);
  }

  // ---------------------------------------------------------------- driving

  /// Moves the car on by one step. The pedals are held for the whole step.
  void step(DriverInputs input, {double dt = stepSeconds}) {
    assert(dt > 0 && dt <= 0.1, 'The model is stable for steps up to 100 ms');
    _timeSeconds += dt;
    _updateEngineState(input.ignitionOn, dt);

    final running = _state == EngineState.running;
    final pedal = running ? input.throttle.clamp(0.0, 1.0) : 0.0;
    final brake = input.brake.clamp(0.0, 1.0);
    _brake = brake;

    var driveForce = 0.0;
    if (running) {
      final drive = _drive(pedal: pedal, speed: _speedMs, dt: dt);
      _rpm = drive.rpm;
      _gear = drive.gear;
      _shiftRemaining = drive.shiftRemaining;
      _sinceShift = drive.sinceShift;
      _fuelCut = drive.fuelCut;
      _demand = drive.demand;
      _output = drive.output;
      driveForce = drive.driveForceN;
    } else {
      _spinDownOrCrank(dt);
      _fuelCut = true;
      _demand = 0;
    }

    final speedBefore = _speedMs;
    final force = _netForce(driveForce, brake, speedBefore);
    var speed = speedBefore + force / profile.massKg * dt;
    if (speed < 0) speed = 0;
    if (speedBefore == 0 && force <= 0) speed = 0;
    _speedMs = speed;
    _accelerationMs2 = (speed - speedBefore) / dt;
    final travelled = (speedBefore + speed) / 2 * dt;
    _distanceM += travelled;
    _lateralMs2 = speed * speed * route.curvatureAt(_distanceM);

    _updateFuelAndTruth(running, speedBefore, speed, dt);
    _updateThermalAndElectrical(running, dt);
    _trackEvents(input.intent, speedBefore, dt);
    _refreshGovernor();
  }

  void _updateEngineState(bool ignitionOn, double dt) {
    _ignition = ignitionOn;
    if (!ignitionOn) {
      _state = EngineState.off;
      _keyOnSeconds = 0;
      _crankSeconds = 0;
      return;
    }
    switch (_state) {
      case EngineState.off:
        _state = EngineState.keyOn;
        _keyOnSeconds = 0;
      case EngineState.keyOn:
        _keyOnSeconds += dt;
        if (_keyOnSeconds >= _keyOnDelaySeconds && _fuelLeftLitres > 0) {
          _state = EngineState.cranking;
          _crankSeconds = 0;
        }
      case EngineState.cranking:
        _crankSeconds += dt;
        if (_crankSeconds >= _crankSecondsToStart) {
          _state = EngineState.running;
          _runSeconds = 0;
          _rpm = math.max(_rpm, 500);
          _gear = profile.transmission is ManualTransmission ? 1 : 0;
          _shiftRemaining = 0;
        }
      case EngineState.running:
        _runSeconds += dt;
        if (_fuelLeftLitres <= 0) {
          _state = EngineState.keyOn;
          _keyOnSeconds = 0;
        }
    }
  }

  void _spinDownOrCrank(double dt) {
    if (_state == EngineState.cranking) {
      _rpm += (210 - _rpm) * math.min(1.0, dt / 0.1);
    } else {
      _rpm *= math.exp(-dt / 0.35);
      if (_rpm < 20) _rpm = 0;
    }
  }

  // ---------------------------------------------------------- the powertrain

  /// Works out one step of the powertrain for a pedal position and a speed,
  /// without changing anything.
  ///
  /// With [allowShift] false the gear stays as it is, which is what a what-if
  /// question about the pedal needs: it asks about the current gear and must
  /// never trigger a gear change of its own.
  _Drive _drive({
    required double pedal,
    required double speed,
    required double dt,
    bool allowShift = true,
  }) => switch (profile.transmission) {
    final CvtTransmission cvt => _driveCvt(cvt, pedal, speed, dt),
    final ManualTransmission manual => _driveManual(
      manual,
      pedal,
      speed,
      dt,
      allowShift,
    ),
  };

  /// Moves [current] towards [target] with a first-order lag, no faster than the
  /// given rates.
  static double _slew(
    double current,
    double target,
    double dt, {
    required double tau,
    double maxUpPerSecond = 9000,
    double maxDownPerSecond = 6000,
  }) {
    final change = (target - current) * math.min(1.0, dt / tau);
    return current + change.clamp(-maxDownPerSecond * dt, maxUpPerSecond * dt);
  }

  ({bool fuelCut, double demand, EngineOutput output, double hold}) _runEngine({
    required double rpm,
    required double pedal,
    required double speed,
    required double clutchDragNm,
  }) {
    final moving = speed > 0.5;
    var fuelCut = pedal < 0.02 && moving && rpm > (_fuelCut ? 1400 : 1500);
    if (rpm >= profile.redlineRpm) fuelCut = true;
    // Below 1,450 rpm the idle governor keeps the engine turning.
    final idleWindow = rpm < 1450 && !fuelCut;
    final hold = idleWindow ? _idleLoadNm + clutchDragNm : 0.0;
    final pedalDemand = _engine.demandForPedal(pedal);
    final demand = idleWindow
        ? math.max(pedalDemand, _governorDemand)
        : pedalDemand;
    final output = _engine.run(
      rpm: rpm,
      demand: demand,
      intakeAirC: _intakeAirC,
      fuelCut: fuelCut,
      frictionScale: _frictionScale(),
    );
    return (fuelCut: fuelCut, demand: demand, output: output, hold: hold);
  }

  _Drive _driveCvt(CvtTransmission tx, double pedal, double speed, double dt) {
    final idle = _idleTargetRpm;
    final kmh = speed * 3.6;

    // Gentle cruising: revs follow road speed a little, up to a ceiling.
    final cruiseAtTen = tx.cruiseRpmBase + tx.cruiseRpmPerKmh * 10;
    final cruise = kmh < 10
        ? idle + (cruiseAtTen - idle) * (kmh / 10)
        : math.min(
            tx.cruiseRpmBase + tx.cruiseRpmPerKmh * kmh,
            tx.cruiseRpmMax,
          );
    // The pedal pulls the revs up. From a standstill the torque converter lets
    // them run ahead of the wheels, but not all the way.
    final pullMax =
        tx.launchRpmMax +
        (tx.pullRpmMax - tx.launchRpmMax) * math.min(1.0, kmh / 40);
    final pull = pedal <= 0.15
        ? 0.0
        : math.pow((pedal - 0.15) / 0.85, 1.4).toDouble();
    final target = math.min(
      math.max(idle, cruise + (pullMax - cruise) * pull),
      profile.redlineRpm,
    );
    final rpm = _slew(_rpm, target, dt, tau: 0.2);

    final drag = tx.standstillDragNm * math.max(0.0, 1 - speed / 2.0);
    final run = _runEngine(
      rpm: rpm,
      pedal: pedal,
      speed: speed,
      clutchDragNm: drag,
    );

    final torque = run.output.torqueNm - run.hold;
    final omega = rpm * 2 * math.pi / 60;
    var force = tx.efficiency * torque * omega / math.max(speed, 1.5);
    final limit = profile.tractionLimitG * profile.massKg * _gravity;
    force = force.clamp(-limit, limit);

    // An automatic in drive creeps when the pedals are up.
    if (pedal < 0.02 && _brake < 0.1 && speed < 2.0) {
      force += tx.creepForceN * (1 - speed / 2.0);
    }

    return _Drive(
      rpm: rpm,
      gear: 0,
      shiftRemaining: 0,
      sinceShift: 0,
      fuelCut: run.fuelCut,
      demand: run.demand,
      output: run.output,
      driveForceN: force,
    );
  }

  double _wheelRpm(ManualTransmission tx, int gear, double speed) =>
      speed /
      (2 * math.pi * tx.wheelRadiusM) *
      60 *
      tx.gearRatios[gear - 1] *
      tx.finalDrive;

  _Drive _driveManual(
    ManualTransmission tx,
    double pedal,
    double speed,
    double dt,
    bool allowShift,
  ) {
    final idle = _idleTargetRpm;
    final gears = tx.gearRatios.length;

    // The virtual driver's gear choice.
    var gear = _gear < 1 ? 1 : _gear;
    var shiftRemaining = _shiftRemaining;
    var sinceShift = _sinceShift + dt;
    if (shiftRemaining > 0) {
      shiftRemaining = math.max(0.0, shiftRemaining - dt);
    } else if (!allowShift) {
      // Keep the gear.
    } else if (speed < 0.3 && pedal < 0.05) {
      gear = 1;
    } else if (sinceShift > 1.0) {
      final upRpm =
          tx.upshiftRpmAtLightPedal +
          (tx.upshiftRpmAtFullPedal - tx.upshiftRpmAtLightPedal) *
              ((pedal - 0.2) / 0.8).clamp(0.0, 1.0);
      final here = _wheelRpm(tx, gear, speed);
      // Hysteresis: never change up if the next gear would want a change down,
      // and never change down if the lower gear would want a change up. That
      // is what stops a gearbox hunting.
      if (gear < gears &&
          here >= upRpm &&
          _wheelRpm(tx, gear + 1, speed) > tx.downshiftRpm + 150) {
        gear += 1;
        shiftRemaining = tx.shiftSeconds;
        sinceShift = 0;
      } else if (gear > 1 && speed > 1.0) {
        final lower = _wheelRpm(tx, gear - 1, speed);
        final kickdown =
            pedal > 0.9 &&
            lower < profile.redlineRpm - 700 &&
            here < profile.redlineRpm * 0.55;
        if ((here < tx.downshiftRpm && lower < upRpm - 150) || kickdown) {
          gear -= 1;
          shiftRemaining = tx.shiftSeconds;
          sinceShift = 0;
        }
      }
    }

    final shifting = shiftRemaining > 0;
    final effectivePedal = shifting ? 0.0 : pedal;
    final wheel = _wheelRpm(tx, gear, speed);
    final launchTarget =
        idle + (tx.launchRpmMax - idle) * math.pow(effectivePedal, 0.8);
    final slipping =
        !shifting &&
        gear == 1 &&
        effectivePedal >= 0.05 &&
        wheel < launchTarget;
    final engaged = !shifting && (slipping || wheel >= idle);
    final locked = engaged && !slipping;

    final target = slipping ? launchTarget : math.max(wheel, idle);
    final limited = math.min(target, profile.redlineRpm + 50);
    final rpm = _slew(_rpm, limited, dt, tau: locked ? 0.05 : 0.18);

    final run = _runEngine(
      rpm: rpm,
      pedal: effectivePedal,
      speed: speed,
      clutchDragNm: 0,
    );

    var force = 0.0;
    if (engaged) {
      final torque = run.output.torqueNm - run.hold;
      final ratio = tx.gearRatios[gear - 1] * tx.finalDrive;
      force = tx.efficiency * torque * ratio / tx.wheelRadiusM;
      final limit = profile.tractionLimitG * profile.massKg * _gravity;
      force = force.clamp(-limit, limit);
    }

    return _Drive(
      rpm: rpm,
      gear: gear,
      shiftRemaining: shiftRemaining,
      sinceShift: sinceShift,
      fuelCut: run.fuelCut,
      demand: run.demand,
      output: run.output,
      driveForceN: force,
    );
  }

  /// The idle governor: the throttle that holds the idle revs against the load.
  /// It changes slowly, so it is refreshed once a step and reused, which keeps
  /// the driver's what-if questions cheap.
  void _refreshGovernor() {
    final drag = switch (profile.transmission) {
      final CvtTransmission cvt =>
        cvt.standstillDragNm * math.max(0.0, 1 - _speedMs / 2.0),
      ManualTransmission() => 0.0,
    };
    _governorDemand = _engine.demandForTorque(
      rpm: math.max(_rpm, profile.idleRpm * 0.8),
      torqueNm: _idleLoadNm + drag,
      intakeAirC: _intakeAirC,
      frictionScale: _frictionScale(),
    );
  }

  // ----------------------------------------------------------------- forces

  /// The net force on the car, N, with [driveForce] from the powertrain.
  double _netForce(double driveForce, double brake, double speed) {
    final rolling = profile.rollingResistance * profile.massKg * _gravity;
    final brakeForce = brake * profile.maxBrakeDecelMs2 * profile.massKg;
    if (speed <= 0) {
      // At rest the brakes and rolling resistance hold the car, and it cannot
      // roll backwards.
      return math.max(0.0, driveForce - rolling - brakeForce);
    }
    final drag = 0.5 * _airDensity * profile.dragAreaM2 * speed * speed;
    return driveForce - brakeForce - rolling - drag;
  }

  /// The acceleration the car would have next step with these pedals, m/s2.
  /// It changes nothing. The scripted driver uses it to find the pedal for an
  /// acceleration it wants.
  double accelerationFor({required double pedal, double brake = 0}) {
    final running = _state == EngineState.running;
    final drive = running
        ? _drive(
            pedal: pedal.clamp(0.0, 1.0),
            speed: _speedMs,
            dt: stepSeconds,
            allowShift: false,
          )
        : null;
    final force = _netForce(
      drive?.driveForceN ?? 0,
      brake.clamp(0.0, 1.0),
      _speedMs,
    );
    return force / profile.massKg;
  }

  /// The accelerator position, 0 to [maxPedal], that gives [acceleration] next
  /// step, or the nearest the car can do.
  double pedalForAcceleration(double acceleration, {double maxPedal = 1}) {
    if (accelerationFor(pedal: 0) >= acceleration) return 0;
    if (accelerationFor(pedal: maxPedal) <= acceleration) return maxPedal;
    var low = 0.0;
    var high = maxPedal;
    for (var i = 0; i < 22; i++) {
      final mid = (low + high) / 2;
      if (accelerationFor(pedal: mid) < acceleration) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return (low + high) / 2;
  }

  /// The brake, 0 to 1, that gives a deceleration of [deceleration] (a positive
  /// number) with the accelerator up, or the most the brakes can do.
  double brakeForDeceleration(double deceleration) {
    final coasting = accelerationFor(pedal: 0);
    final needed = coasting + deceleration;
    if (needed <= 0) return 0;
    return (needed / profile.maxBrakeDecelMs2).clamp(0.0, 1.0);
  }

  // ---------------------------------------------------- fuel, heat and truth

  void _updateFuelAndTruth(
    bool running,
    double speedBefore,
    double speedAfter,
    double dt,
  ) {
    if (!running) return;
    final fuelLitres =
        _output.fuelGramsPerSecond * dt / profile.fuel.densityGramsPerLitre;
    _fuelUsedLitres += fuelLitres;
    _truthFuelLitres += fuelLitres;
    _engineOnSeconds += dt;
    // Idling is the engine running below 2 km/h (CLAUDE.md 8.7).
    if ((speedBefore + speedAfter) / 2 * 3.6 < 2.0) {
      _idleSeconds += dt;
      _idleFuelLitres += fuelLitres;
    }
  }

  void _updateThermalAndElectrical(bool running, double dt) {
    final fuelPower = running
        ? _output.fuelGramsPerSecond *
              profile.fuel.lowerHeatingValueJoulesPerGram
        : 0.0;
    final heatIn = _heatToCoolant * fuelPower;
    var heatOut =
        (_ambientLossWattsPerKelvin +
            _airflowLossWattsPerKelvinPerMs * _speedMs) *
        (_coolantC - ambientC);
    if (_coolantC > _thermostatC) {
      heatOut += _radiatorLossWattsPerKelvin * (_coolantC - _thermostatC);
    }
    _coolantC += (heatIn - heatOut) * dt / _heatCapacityJoulesPerKelvin;

    _intakeAirC =
        ambientC +
        0.10 *
            (_coolantC - ambientC) *
            (1 - 0.5 * math.min(1.0, _speedMs / 10));

    _voltage = switch (_state) {
      EngineState.running =>
        14.0 +
            0.2 * math.min(1.0, _rpm / 3000) +
            0.05 * math.sin(2 * math.pi * 0.13 * _timeSeconds + _ripplePhase),
      EngineState.cranking => 10.6,
      EngineState.keyOn || EngineState.off => 12.4,
    };
  }

  /// Events span exactly the steps they cover: they start at the beginning of
  /// the first hard step and end at the end of the last one.
  void _trackEvents(DriverIntent intent, double speedBefore, double dt) {
    final wanted = switch (intent) {
      DriverIntent.hardAcceleration => TruthEventType.hardAcceleration,
      DriverIntent.hardBraking => TruthEventType.hardBraking,
      DriverIntent.normal => null,
    };
    final open = _openEvent;
    if (open != null && open.type != wanted) {
      _closedEvents.add(
        TruthEvent(
          type: open.type,
          startSeconds: open.startSeconds,
          startSpeedKmh: open.startSpeedKmh,
          endSeconds: _timeSeconds - dt,
          endSpeedKmh: speedBefore * 3.6,
          peakAccelerationMs2: open.peak,
        ),
      );
      _openEvent = null;
    }
    if (wanted != null && _openEvent == null) {
      _openEvent = _OpenEvent(wanted, _timeSeconds - dt, speedBefore * 3.6);
    }
    final current = _openEvent;
    if (current != null) {
      current.peak = math.max(current.peak, _accelerationMs2.abs());
    }
  }
}
