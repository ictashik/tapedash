import '../core/observable.dart';
import '../vehicle/sensor.dart';
import '../vehicle/vehicle_state.dart';
import 'coach_thresholds.dart';

enum HardEventType { hardAcceleration, hardBraking }

/// Where a hard-acceleration event is: not started, its condition just met but
/// not yet held long enough (so it may still turn out to be nothing), or
/// confirmed and going on.
enum HardPhase { none, candidate, active }

/// A hard acceleration or hard braking that was found.
class HardEvent {
  const HardEvent({
    required this.type,
    required this.start,
    required this.end,
    required this.peakMs2,
    required this.startSpeedKmh,
  });

  final HardEventType type;

  /// When the condition first held, on the monotonic clock. It is before the
  /// moment the event was confirmed: a hard acceleration is only known to be one
  /// after a second of it.
  final Duration start;
  final Duration end;

  /// The largest acceleration or deceleration, as a positive number.
  final double peakMs2;
  final double startSpeedKmh;

  Duration get duration => end - start;
}

/// Finds hard accelerations and hard brakings (CLAUDE.md 8.8) from the smoothed
/// acceleration in [VehicleState.motion] and the throttle.
///
/// A hard acceleration is smoothed acceleration above the threshold for a
/// second, or the throttle above 70% for two seconds while going faster than
/// 10 km/h. Hard braking is deceleration beyond the threshold for half a second.
/// An event ends when its condition has been false for a short grace time, so
/// acceleration jittering about the threshold is one event and not several.
///
/// [accelerationPhase] tells the money attribution when fuel is being burnt in
/// a hard acceleration, including the time before it was confirmed.
class HardEventDetector {
  HardEventDetector({
    required this.vehicle,
    this.thresholds = CoachThresholds.normal,
  }) {
    vehicle.motion.addListener(_onMotion);
  }

  final VehicleState vehicle;
  CoachThresholds thresholds;

  final ObservableValue<HardPhase> _phase = ObservableValue(HardPhase.none);
  final ObservableValue<bool> _braking = ObservableValue(false);
  final List<HardEvent> _events = [];
  final List<void Function(HardEvent)> _listeners = [];

  Duration? _accelSince;
  Duration? _throttleSince;
  Duration? _accelFalseSince;
  Duration? _eventStart;
  double _eventStartSpeed = 0;
  double _peak = 0;
  Duration? _lastTrueAt;

  Duration? _brakeSince;
  Duration? _brakeFalseSince;
  Duration? _brakeEventStart;
  double _brakeStartSpeed = 0;
  double _brakePeak = 0;
  Duration? _brakeLastTrueAt;
  bool _brakeConfirmed = false;

  /// Where a hard acceleration is.
  Observable<HardPhase> get accelerationPhase => _phase;

  /// Whether a hard braking is going on.
  Observable<bool> get braking => _braking;

  /// The events found so far, in order (only those that have ended).
  List<HardEvent> get events => List.unmodifiable(_events);

  /// Calls [listener] with each event as it ends.
  void onEvent(void Function(HardEvent) listener) => _listeners.add(listener);

  void _onMotion() {
    final m = vehicle.motion.value;
    if (m == null) return;
    final at = m.at;
    final t = thresholds;
    final speedKmh = m.speedKmh;
    final throttle = vehicle.isStale(Sensor.throttle)
        ? null
        : vehicle.throttle.value?.value;

    // Hard acceleration.
    final accelHigh = m.accelerationMs2 > t.hardAccelerationMs2;
    final throttleHigh =
        throttle != null &&
        throttle > t.hardAccelerationThrottlePercent &&
        speedKmh > t.hardAccelerationMinSpeedKmh;
    _accelSince = accelHigh ? (_accelSince ?? at) : null;
    _throttleSince = throttleHigh ? (_throttleSince ?? at) : null;
    final anyHigh = accelHigh || throttleHigh;
    final confirmedNow =
        (_accelSince != null &&
            _secs(at - _accelSince!) >= t.hardAccelerationSeconds) ||
        (_throttleSince != null &&
            _secs(at - _throttleSince!) >= t.hardAccelerationThrottleSeconds);

    if (anyHigh) {
      _accelFalseSince = null;
      _lastTrueAt = at;
      if (_eventStart == null) {
        _eventStart = _accelSince != null && _throttleSince != null
            ? (_accelSince! < _throttleSince! ? _accelSince : _throttleSince)
            : (_accelSince ?? _throttleSince);
        _eventStartSpeed = speedKmh;
        _peak = 0;
      }
      if (m.accelerationMs2 > _peak) _peak = m.accelerationMs2;
      if (_phase.value != HardPhase.active) {
        _phase.value = confirmedNow ? HardPhase.active : HardPhase.candidate;
      }
    } else if (_eventStart != null) {
      _accelFalseSince ??= at;
      final held = _secs(at - _accelFalseSince!) >= t.releaseGraceSeconds;
      if (held || _phase.value == HardPhase.candidate) {
        // A candidate that never confirmed drops at once; a confirmed event
        // waits out the grace.
        if (_phase.value == HardPhase.active) {
          _emit(
            HardEvent(
              type: HardEventType.hardAcceleration,
              start: _eventStart!,
              end: _lastTrueAt!,
              peakMs2: _peak,
              startSpeedKmh: _eventStartSpeed,
            ),
          );
        }
        _eventStart = null;
        _accelFalseSince = null;
        _phase.value = HardPhase.none;
      }
    }

    // Hard braking.
    final brakeHigh = m.accelerationMs2 < -t.hardBrakingMs2;
    _brakeSince = brakeHigh ? (_brakeSince ?? at) : null;
    if (brakeHigh) {
      _brakeFalseSince = null;
      _brakeLastTrueAt = at;
      if (_brakeEventStart == null) {
        _brakeEventStart = _brakeSince;
        _brakeStartSpeed = speedKmh;
        _brakePeak = 0;
      }
      if (-m.accelerationMs2 > _brakePeak) _brakePeak = -m.accelerationMs2;
      if (!_brakeConfirmed &&
          _secs(at - _brakeSince!) >= t.hardBrakingSeconds) {
        _brakeConfirmed = true;
        _braking.value = true;
      }
    } else if (_brakeEventStart != null) {
      _brakeFalseSince ??= at;
      if (_secs(at - _brakeFalseSince!) >= t.releaseGraceSeconds / 2 ||
          !_brakeConfirmed) {
        if (_brakeConfirmed) {
          _emit(
            HardEvent(
              type: HardEventType.hardBraking,
              start: _brakeEventStart!,
              end: _brakeLastTrueAt!,
              peakMs2: _brakePeak,
              startSpeedKmh: _brakeStartSpeed,
            ),
          );
        }
        _brakeEventStart = null;
        _brakeFalseSince = null;
        _brakeConfirmed = false;
        _braking.value = false;
      }
    }
  }

  void _emit(HardEvent e) {
    _events.add(e);
    for (final l in List.of(_listeners)) {
      l(e);
    }
  }

  static double _secs(Duration d) => d.inMicroseconds / 1e6;

  void dispose() => vehicle.motion.removeListener(_onMotion);
}
