import 'dart:async';
import 'dart:math' as math;

import '../core/clock.dart';
import '../core/scheduler.dart';
import '../sim/sim_random.dart';
import '../sim/simulated_car.dart';
import 'location_source.dart';

/// A [LocationSource] that follows a [SimulatedCar] along its route
/// (CLAUDE.md 7.5).
///
/// The position is where the car has got to along the scenario's road, with
/// the errors of a phone's GPS: a wander of a few metres that drifts from one
/// fix to the next rather than jumping about, a little noise on the speed, and
/// now and then a spell in a street of tall buildings, where the fixes are far
/// worse and the receiver says so.
///
/// The reported accuracy is honest: it is the radius that the error stays within
/// about two times in three, which is how a real receiver reports it, so code
/// that weighs fixes by their accuracy can be tested against this.
class SimLocationSource implements LocationSource {
  SimLocationSource({
    required this.car,
    required this.scheduler,
    required this.clock,
    int seed = 1,
    this.period = const Duration(seconds: 1),
    this.altitudeM = 920,
  }) : _random = SimRandom(seed).fork(5) {
    // Start with an error typical of the open sky.
    _east = _openSigma * _random.nextGaussian();
    _north = _openSigma * _random.nextGaussian();
    _up = _verticalSigma * _random.nextGaussian();
  }

  final SimulatedCar car;
  final Scheduler scheduler;
  final Clock clock;

  /// How often there is a fix.
  final Duration period;

  /// About how high the road is, metres above sea level.
  final double altitudeM;

  final SimRandom _random;

  final StreamController<LocationFix> _fixes =
      StreamController<LocationFix>.broadcast(sync: true);
  ScheduledTask? _task;

  // How much of each fix's error is left in the next one: a receiver's error
  // wanders, and has not changed much a second later.
  static const double _memory = 0.85;

  // Standard deviation of the error on each axis, in metres, in the open and
  // in a street of tall buildings.
  static const double _openSigma = 2.5;
  static const double _canyonSigma = 18;
  static const double _verticalSigma = 2;
  static const double _metresPerDegree = 111320;

  // The chance in any one second of driving into a bad spell, and how long
  // it lasts, in fixes.
  static const double _canyonChance = 0.008;
  static const int _canyonShortest = 3;
  static const int _canyonLongest = 9;

  // The circle that holds a 2D error with probability 0.68 has a radius of
  // about 1.5 sigma.
  static const double _accuracyPerSigma = 1.5;

  late double _east;
  late double _north;
  late double _up;

  // The variance the error has now. It follows the conditions: it grows over a
  // few fixes on the way into a canyon and dies away on the way out, and the
  // accuracy the receiver reports has to follow it.
  double _variance = _openSigma * _openSigma;
  int _canyonFixesLeft = 0;

  @override
  Stream<LocationFix> get fixes => _fixes.stream;

  @override
  bool get isRunning => _task != null;

  @override
  Future<void> start() {
    _task ??= scheduler.runEvery(period, _fix);
    return Future<void>.value();
  }

  @override
  Future<void> stop() {
    _task?.cancel();
    _task = null;
    return Future<void>.value();
  }

  /// Stops, and closes the stream.
  Future<void> dispose() async {
    await stop();
    await _fixes.close();
  }

  void _fix() {
    final state = car.state;
    final onRoute = car.scenario.route.pointAt(state.distanceM);

    if (_canyonFixesLeft > 0) {
      _canyonFixesLeft--;
    } else if (_random.chance(_canyonChance)) {
      _canyonFixesLeft =
          _canyonShortest +
          _random.nextInt(_canyonLongest - _canyonShortest + 1);
    }
    final target = _canyonFixesLeft > 0 ? _canyonSigma : _openSigma;

    // An error that mostly carries over from the last fix. Its variance moves
    // towards the level of the conditions, and it is that variance that the
    // fix's accuracy reports.
    const carried = _memory * _memory;
    _variance = carried * _variance + target * target * (1 - carried);
    final sigma = math.sqrt(_variance);
    final fresh = math.sqrt(1 - carried);
    _east = _memory * _east + target * fresh * _random.nextGaussian();
    _north = _memory * _north + target * fresh * _random.nextGaussian();
    _up = _memory * _up + _verticalSigma * fresh * _random.nextGaussian();

    final latitude = onRoute.latitude + _north / _metresPerDegree;
    final longitude =
        onRoute.longitude +
        _east / (_metresPerDegree * math.cos(onRoute.latitude * math.pi / 180));

    // A receiver's speed is good to a few centimetres per second, and it reads
    // a hair above zero when standing still.
    final moving = state.speedMs > 1;
    final speed = state.speedMs < 0.1
        ? 0.04 * _random.nextGaussian().abs()
        : math.max(0.0, state.speedMs + 0.12 * _random.nextGaussian());
    // Standing still, a receiver has no direction to report.
    final heading = moving
        ? (onRoute.headingDegrees + 1.5 * _random.nextGaussian()) % 360
        : null;

    final accuracy = math.max(
      2.0,
      _accuracyPerSigma * sigma * (1 + 0.15 * _random.nextGaussian()),
    );

    if (_fixes.isClosed) return;
    _fixes.add(
      LocationFix(
        latitude: latitude,
        longitude: longitude,
        speedMs: speed,
        headingDegrees: heading,
        altitudeM: altitudeM + _up,
        accuracyM: accuracy,
        time: clock.now(),
      ),
    );
  }
}
