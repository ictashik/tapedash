import '../core/scheduler.dart';
import 'drive_scenario.dart';
import 'driver.dart';
import 'driver_inputs.dart';
import 'ground_truth.dart';
import 'scenario_events.dart';
import 'vehicle_model.dart';
import 'vehicle_profile.dart';

/// A [VehicleModel] being driven through a [DriveScenario].
///
/// Each tick asks the scenario's driver for inputs and steps the model, and the
/// scenario's fault codes appear in the car's memory at their times. Give it a
/// [Scheduler] and [start] it to run in step with a clock, or call [tick]
/// yourself to run as fast as you like.
class SimulatedCar {
  SimulatedCar({
    required this.scenario,
    VehicleProfile? profile,
    this.seed = 1,
    this.scheduler,
    this.stopWhenFinished = false,
  }) : profile = profile ?? scenario.profile {
    _reset();
  }

  final DriveScenario scenario;
  final VehicleProfile profile;
  final int seed;
  final Scheduler? scheduler;

  /// Brakes to a stop once the scenario's time is up, rather than carrying on
  /// with the plan: a scenario that is cut off mid-drive then ends parked, as a
  /// looping demo needs (its trip can end, and Review opens). Off by default, so
  /// the ground truth of a test drive is the plan's, however it ends.
  final bool stopWhenFinished;

  late VehicleModel model;
  late Driver _driver;
  ScheduledTask? _task;

  final List<String> _stored = [];
  final List<String> _pending = [];
  int _nextInjection = 0;

  void _reset() {
    model = VehicleModel(
      profile: profile,
      seed: seed,
      route: scenario.route,
      ambientC: scenario.ambientC,
      coolantC: scenario.startCoolantC,
      fuelLevelFraction: scenario.fuelLevelFraction,
      engineRunning: scenario.engineRunningAtStart,
    );
    _driver = scenario.newDriver();
    _stored.clear();
    _pending.clear();
    _nextInjection = 0;
  }

  /// Starts again from the beginning, with a fresh car and driver, as a
  /// looping demo does.
  void restart() => _reset();

  VehicleSnapshot get state => model.state;
  GroundTruth get truth => model.truth;

  /// Seconds since the drive began.
  double get elapsedSeconds => model.state.timeSeconds;

  /// True once the scenario is over: its time is up, or its driver has
  /// finished. The car carries on idling.
  bool get isFinished {
    final duration = scenario.duration;
    if (duration != null) {
      return elapsedSeconds >= duration.inMicroseconds / 1e6;
    }
    return _driver.isFinished;
  }

  /// Fault codes stored in the ECU (Mode 03) and pending ones (Mode 07).
  List<String> get storedDtcs => List.unmodifiable(_stored);
  List<String> get pendingDtcs => List.unmodifiable(_pending);

  /// Whether the check-engine light is on: a stored code sets it.
  bool get milOn => _stored.isNotEmpty;

  /// Erases the stored and pending codes, as Mode 04 does.
  void clearDtcs() {
    _stored.clear();
    _pending.clear();
  }

  /// Advances the car by one step.
  void tick() {
    final inputs = stopWhenFinished && isFinished && model.state.speedMs > 0.05
        ? const DriverInputs(brake: 0.3)
        : _driver.decide(model);
    model.step(inputs);
    _applyDtcInjections();
  }

  void _applyDtcInjections() {
    final injections = scenario.dtcs;
    while (_nextInjection < injections.length) {
      final injection = injections[_nextInjection];
      if (elapsedSeconds < injection.at.inMicroseconds / 1e6) break;
      _nextInjection++;
      switch (injection.kind) {
        case DtcKind.stored:
          _pending.remove(injection.code);
          if (!_stored.contains(injection.code)) _stored.add(injection.code);
        case DtcKind.pending:
          if (!_stored.contains(injection.code) &&
              !_pending.contains(injection.code)) {
            _pending.add(injection.code);
          }
      }
    }
  }

  /// Runs the car on the scheduler, one step every [VehicleModel.stepSeconds].
  void start() {
    final scheduler = this.scheduler;
    if (scheduler == null) {
      throw StateError('Give the car a Scheduler to start it, or call tick()');
    }
    _task ??= scheduler.runEvery(
      Duration(microseconds: (VehicleModel.stepSeconds * 1e6).round()),
      tick,
    );
  }

  void stop() {
    _task?.cancel();
    _task = null;
  }

  bool get isRunning => _task?.isActive ?? false;

  /// Runs to the end of the scenario as fast as possible, or for [limit] of
  /// simulated time if the scenario would not end. Returns the seconds run.
  double runToEnd({Duration limit = const Duration(hours: 2)}) {
    final limitSeconds = limit.inMicroseconds / 1e6;
    while (!isFinished && elapsedSeconds < limitSeconds) {
      tick();
    }
    return elapsedSeconds;
  }
}
