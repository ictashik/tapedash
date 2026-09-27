import 'dart:math' as math;

import '../core/clock.dart';
import '../core/observable.dart';
import '../core/scheduler.dart';
import 'reading.dart';
import 'sensor.dart';

/// Whether the car is being driven, for the rules that only allow some things
/// while it is not (CLAUDE.md 9, DESIGN.md 7.2).
enum DrivingMode {
  /// Speed 0 for 5 s, or the ignition off: tips, fill-ups, fault-code clearing
  /// and settings are reachable.
  parked,

  /// Speed above 3 km/h.
  motion,
}

/// What is known of the ignition. The connection layer sets it, from whether
/// the ECU answers.
enum IgnitionState { unknown, on, off }

/// Road speed smoothed, and the acceleration taken from it.
class MotionSample {
  const MotionSample({
    required this.speedMs,
    required this.accelerationMs2,
    required this.at,
    required this.receivedAt,
  });

  /// Speed in metres per second, smoothed with an exponential average of about
  /// a second (CLAUDE.md 8.8). The car reports whole km/h, and unsmoothed it
  /// would make the acceleration jump by 0.28 m/s2 with every step.
  final double speedMs;

  /// Acceleration in m/s2, positive when speeding up, from the change in the
  /// smoothed speed between two samples.
  final double accelerationMs2;

  /// When the speed sample it comes from was measured.
  final Duration at;

  /// When that sample arrived.
  final Duration receivedAt;

  double get speedKmh => speedMs * 3.6;
}

/// The numbers behind [VehicleState].
class VehicleStateConfig {
  const VehicleStateConfig({
    this.staleAfter = const Duration(milliseconds: 1500),
    this.speedTimeConstant = const Duration(seconds: 1),
    this.outlierWindow = const Duration(milliseconds: 100),
    this.movingAboveKmh = 3,
    this.parkedAfter = const Duration(seconds: 5),
    this.engineOnRpm = 400,
  });

  /// A value with no new sample for this long is stale (DESIGN.md 5.2).
  final Duration staleAfter;

  /// The time constant of the exponential average of speed.
  final Duration speedTimeConstant;

  /// The shortest time over which a change is judged. Two samples closer
  /// together than this are judged as if they were this far apart, since the
  /// timestamps of samples are estimates and a whole-km/h step between two
  /// samples 5 ms apart is not a change of 200 km/h per second.
  final Duration outlierWindow;

  /// Above this speed the car is in motion.
  final double movingAboveKmh;

  /// How long speed must be 0 for the car to count as parked.
  final Duration parkedAfter;

  /// Above this the engine is running (CLAUDE.md 8.6).
  final double engineOnRpm;
}

/// What is known of the car right now (CLAUDE.md 6): the latest reading of each
/// sensor, and the values derived from them.
///
/// Readings come in through [ingest]. Each is checked against the last: one
/// that implies a physically impossible change is held back, and is used only if
/// the next sample confirms it (DESIGN.md 5.2). Everything is an [Observable] and
/// changes synchronously, so a fake clock can drive a whole drive.
///
/// Values are never guessed: a sensor that has not been read is null, and a value
/// that has stopped arriving holds, and can be told apart by its age.
class VehicleState {
  VehicleState({
    required this.clock,
    required this.scheduler,
    this.config = const VehicleStateConfig(),
  }) {
    for (final sensor in Sensor.values) {
      _readings[sensor] = ObservableValue<Reading?>(null);
      _filters[sensor] = _Filter();
    }
  }

  final Clock clock;
  final Scheduler scheduler;
  final VehicleStateConfig config;

  final Map<Sensor, ObservableValue<Reading?>> _readings = {};
  final Map<Sensor, _Filter> _filters = {};
  final Map<Sensor, int> _rejected = {};

  final ObservableValue<MotionSample?> _motion = ObservableValue(null);
  final ObservableValue<bool> _engineRunning = ObservableValue(false);
  final ObservableValue<DrivingMode> _mode = ObservableValue(
    DrivingMode.parked,
  );
  final ObservableValue<IgnitionState> _ignition = ObservableValue(
    IgnitionState.unknown,
  );

  Duration? _lastSpeedAt;
  double? _smoothedMs;
  Duration? _zeroSince;
  ScheduledTask? _parkTask;

  /// The latest accepted reading of [sensor], or null if there is none.
  Observable<Reading?> reading(Sensor sensor) => _readings[sensor]!;

  Observable<Reading?> get rpm => reading(Sensor.rpm);
  Observable<Reading?> get speed => reading(Sensor.speed);
  Observable<Reading?> get throttle => reading(Sensor.throttle);
  Observable<Reading?> get load => reading(Sensor.load);
  Observable<Reading?> get coolant => reading(Sensor.coolant);
  Observable<Reading?> get intakeAir => reading(Sensor.intakeAir);
  Observable<Reading?> get manifoldPressure => reading(Sensor.manifoldPressure);
  Observable<Reading?> get airFlow => reading(Sensor.airFlow);
  Observable<Reading?> get fuelLevel => reading(Sensor.fuelLevel);
  Observable<Reading?> get voltage => reading(Sensor.voltage);
  Observable<Reading?> get fuelRate => reading(Sensor.fuelRate);

  /// Speed smoothed, and the acceleration from it. Null until there are two
  /// speed samples.
  Observable<MotionSample?> get motion => _motion;

  /// Whether the engine is running: the last RPM was above 400.
  Observable<bool> get engineRunning => _engineRunning;

  /// Motion or parked (DESIGN.md 7.2).
  Observable<DrivingMode> get mode => _mode;

  /// What is known of the ignition.
  Observable<IgnitionState> get ignition => _ignition;

  /// How many readings of [sensor] were thrown away as impossible.
  int rejectedReadings(Sensor sensor) => _rejected[sensor] ?? 0;

  /// How long [sensor] may go without a new reading before it is stale: 1.5 s
  /// for the values read every cycle, and longer for those read less often
  /// (see [Sensor.staleFactor]).
  Duration staleAfterFor(Sensor sensor) =>
      config.staleAfter * sensor.staleFactor;

  /// Whether [sensor] has never been read, or has had no new reading for longer
  /// than [staleAfterFor].
  bool isStale(Sensor sensor) {
    final reading = _readings[sensor]!.value;
    return reading == null ||
        reading.age(clock.monotonic()) > staleAfterFor(sensor);
  }

  /// Takes a measurement of [sensor]: [value] in its unit, read at [at] and
  /// received at [receivedAt], both on the monotonic clock.
  void ingest(
    Sensor sensor,
    double value, {
    required Duration at,
    required Duration receivedAt,
  }) {
    final reading = Reading(value: value, at: at, receivedAt: receivedAt);
    final limit = sensor.maxChangePerSecond;
    final filter = _filters[sensor]!;
    final accepted = filter.accepted;
    if (limit == null || accepted == null) {
      _accept(sensor, reading);
      return;
    }

    final pending = filter.pending;
    if (pending != null) {
      filter.pending = null;
      if (_plausible(limit, pending, reading)) {
        // The jump held for a second sample, so it was real.
        _accept(sensor, pending);
        _accept(sensor, reading);
      } else {
        // The first sample of the jump was a glitch.
        _reject(sensor);
        if (_plausible(limit, accepted, reading)) {
          _accept(sensor, reading);
        } else {
          filter.pending = reading;
        }
      }
      return;
    }
    if (_plausible(limit, accepted, reading)) {
      _accept(sensor, reading);
    } else {
      filter.pending = reading;
    }
  }

  /// Says what is known of the ignition. Off means the car is parked, and the
  /// engine is not running.
  void setIgnition(IgnitionState state) {
    _ignition.value = state;
    if (state == IgnitionState.off) {
      _parkTask?.cancel();
      _parkTask = null;
      _zeroSince = null;
      _engineRunning.value = false;
      _mode.value = DrivingMode.parked;
    }
  }

  bool _plausible(double limit, Reading from, Reading to) {
    var seconds = (to.at - from.at).inMicroseconds / 1e6;
    final window = config.outlierWindow.inMicroseconds / 1e6;
    seconds = math.max(seconds, window);
    return (to.value - from.value).abs() <= limit * seconds;
  }

  void _reject(Sensor sensor) =>
      _rejected[sensor] = rejectedReadings(sensor) + 1;

  void _accept(Sensor sensor, Reading reading) {
    _filters[sensor]!.accepted = reading;
    _readings[sensor]!.value = reading;
    switch (sensor) {
      case Sensor.speed:
        _onSpeed(reading);
      case Sensor.rpm:
        _engineRunning.value =
            _ignition.value != IgnitionState.off &&
            reading.value > config.engineOnRpm;
      default:
        break;
    }
  }

  void _onSpeed(Reading reading) {
    final metresPerSecond = reading.value / 3.6;
    final previousAt = _lastSpeedAt;
    final previous = _smoothedMs;
    if (previous == null || previousAt == null) {
      _smoothedMs = metresPerSecond;
      _lastSpeedAt = reading.at;
    } else {
      final seconds = (reading.at - previousAt).inMicroseconds / 1e6;
      if (seconds > 0) {
        final alpha =
            1 -
            math.exp(
              -seconds / (config.speedTimeConstant.inMicroseconds / 1e6),
            );
        final next = previous + alpha * (metresPerSecond - previous);
        _smoothedMs = next;
        _lastSpeedAt = reading.at;
        _motion.value = MotionSample(
          speedMs: next,
          accelerationMs2: (next - previous) / seconds,
          at: reading.at,
          receivedAt: reading.receivedAt,
        );
      }
    }
    _updateMode(reading);
  }

  void _updateMode(Reading reading) {
    if (_ignition.value == IgnitionState.off) return;
    final kmh = reading.value;
    if (kmh > config.movingAboveKmh) {
      _zeroSince = null;
      _parkTask?.cancel();
      _parkTask = null;
      _mode.value = DrivingMode.motion;
    } else if (kmh == 0) {
      _zeroSince ??= reading.receivedAt;
      if (_mode.value == DrivingMode.motion) _parkIfStill();
    } else {
      // Creeping: neither. It is not standing still, so the count starts again.
      _zeroSince = null;
      _parkTask?.cancel();
      _parkTask = null;
    }
  }

  /// Parks the car if speed has been 0 for long enough, and otherwise says
  /// when to look again.
  void _parkIfStill() {
    final since = _zeroSince;
    if (since == null) return;
    final still = clock.monotonic() - since;
    if (still >= config.parkedAfter) {
      _mode.value = DrivingMode.parked;
      _parkTask?.cancel();
      _parkTask = null;
    } else {
      _parkTask ??= scheduler.runAfter(config.parkedAfter - still, () {
        _parkTask = null;
        if (_zeroSince != null && _mode.value == DrivingMode.motion) {
          _parkIfStill();
        }
      });
    }
  }

  /// Stops the timer and drops every listener.
  void dispose() {
    _parkTask?.cancel();
    _parkTask = null;
    for (final value in _readings.values) {
      value.dispose();
    }
    _motion.dispose();
    _engineRunning.dispose();
    _mode.dispose();
    _ignition.dispose();
  }
}

/// What the outlier check remembers about one sensor.
class _Filter {
  Reading? accepted;
  Reading? pending;
}
