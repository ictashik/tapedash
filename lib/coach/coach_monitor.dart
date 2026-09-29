import '../core/observable.dart';
import '../vehicle/vehicle_state.dart';
import 'coach_thresholds.dart';

/// What the coach counted in one trip (CLAUDE.md 8.8), beyond the hard events
/// the [HardEventDetector] finds.
class CoachStats {
  const CoachStats({
    this.longIdles = 0,
    this.longestIdleSeconds = 0,
    this.highRpmSeconds = 0,
    this.highRpmEvents = 0,
    this.speedingSeconds = 0,
    this.speedingEvents = 0,
  });

  /// Stops of more than the long-idle threshold with the engine running.
  final int longIdles;
  final double longestIdleSeconds;

  /// Seconds above the high-rpm threshold, in stretches longer than its minimum.
  final double highRpmSeconds;
  final int highRpmEvents;

  /// Seconds above the speed threshold, in stretches longer than its minimum.
  final double speedingSeconds;
  final int speedingEvents;
}

/// A stretch that a threshold is held above (or below) for a minimum time: the
/// shape of the long-idle, high-rpm and speeding rules.
class _Stretch {
  Duration? _since;
  bool _confirmed = false;
  double confirmedSeconds = 0;
  int events = 0;
  double longestSeconds = 0;

  /// Feeds whether the condition holds at [at]; [minimum] is how long it must
  /// hold before it counts.
  void update(bool holds, Duration at, double minimum) {
    if (holds) {
      _since ??= at;
      final held = (at - _since!).inMicroseconds / 1e6;
      if (!_confirmed && held >= minimum) {
        _confirmed = true;
        events++;
      }
      if (_confirmed && held > longestSeconds) longestSeconds = held;
      return;
    }
    _end(at);
  }

  void _end(Duration at) {
    if (_since != null && _confirmed) {
      confirmedSeconds += (at - _since!).inMicroseconds / 1e6;
    }
    _since = null;
    _confirmed = false;
  }

  /// Counts the stretch still going, at the end of a trip.
  double totalSeconds(Duration now) {
    if (_since != null && _confirmed) {
      return confirmedSeconds + (now - _since!).inMicroseconds / 1e6;
    }
    return confirmedSeconds;
  }

  void reset() {
    _since = null;
    _confirmed = false;
    confirmedSeconds = 0;
    events = 0;
    longestSeconds = 0;
  }
}

/// Watches a trip for the coach's three duration rules (CLAUDE.md 8.8): long
/// idling (more than 60 s stopped with the engine running), high revs (above
/// 3500 rpm for more than 3 s) and speeding (above the user's threshold for more
/// than 10 s). It counts; it never speaks. What is said, and when, is the tip
/// engine's and the screens' (tips are for a stopped car or a finished trip).
class CoachMonitor {
  CoachMonitor({required this.vehicle, CoachThresholds? thresholds})
    : thresholds = thresholds ?? CoachThresholds.normal {
    vehicle.speed.addListener(_update);
    vehicle.rpm.addListener(_update);
  }

  final VehicleState vehicle;
  CoachThresholds thresholds;

  final _Stretch _idle = _Stretch();
  final _Stretch _highRpm = _Stretch();
  final _Stretch _speeding = _Stretch();
  Duration _last = Duration.zero;
  final ObservableValue<CoachStats> _stats = ObservableValue(
    const CoachStats(),
  );

  /// What has been counted this trip, updated as it changes.
  Observable<CoachStats> get stats => _stats;

  void _update() {
    final speed = vehicle.speed.value;
    final rpm = vehicle.rpm.value;
    if (speed == null || rpm == null) return;
    final at = speed.at > rpm.at ? speed.at : rpm.at;
    if (at <= _last && _last != Duration.zero) return;
    _last = at;
    final t = thresholds;
    final idling = vehicle.engineRunning.value && speed.value < 2;
    _idle.update(idling, at, t.longIdleSeconds);
    _highRpm.update(rpm.value > t.highRpm, at, t.highRpmSeconds);
    _speeding.update(speed.value > t.speedLimitKmh, at, t.speedingSeconds);
    _publish(at);
  }

  void _publish(Duration now) {
    _stats.value = CoachStats(
      longIdles: _idle.events,
      longestIdleSeconds: _idle.longestSeconds,
      highRpmSeconds: _highRpm.totalSeconds(now),
      highRpmEvents: _highRpm.events,
      speedingSeconds: _speeding.totalSeconds(now),
      speedingEvents: _speeding.events,
    );
  }

  /// Starts counting from nothing: a new trip.
  void reset() {
    _idle.reset();
    _highRpm.reset();
    _speeding.reset();
    _last = Duration.zero;
    _stats.value = const CoachStats();
  }

  void dispose() {
    vehicle.speed.removeListener(_update);
    vehicle.rpm.removeListener(_update);
  }
}
