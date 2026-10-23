import 'dart:async';

import '../core/clock.dart';
import '../core/observable.dart';
import '../core/scheduler.dart';
import '../vehicle/sensor.dart';
import '../vehicle/vehicle_state.dart';
import 'location_source.dart';
import 'location_status.dart';

/// Where the GPS-only drive has got to, for the screen to say in words.
enum GpsPhase {
  /// Asking the phone for its location.
  starting,

  /// The person has not allowed the app to use the location (or refused it).
  needsPermission,

  /// The phone would not start a GPS receiver at all.
  unavailable,

  /// The receiver is on and has no usable fix yet, or has lost it.
  searching,

  /// A fix in the last few seconds: the speed is the road's.
  tracking,
}

/// What a GPS-only drive adds up to: the distance, the time spent moving and the
/// fastest the phone saw. Whole-trip figures, until [GpsDrive.resetTrip].
class GpsFigures {
  const GpsFigures({
    this.distanceKm = 0,
    this.movingTime = Duration.zero,
    this.maxKmh = 0,
  });

  final double distanceKm;

  /// Time with the car moving (not standing at a light).
  final Duration movingTime;
  final double maxKmh;

  /// The average speed while moving, or null before there is enough of it to mean
  /// anything: ten seconds of movement.
  double? get averageKmh {
    final hours = movingTime.inMicroseconds / Duration.microsecondsPerHour;
    return movingTime < const Duration(seconds: 10) ? null : distanceKm / hours;
  }

  @override
  bool operator ==(Object other) =>
      other is GpsFigures &&
      other.distanceKm == distanceKm &&
      other.movingTime == movingTime &&
      other.maxKmh == maxKmh;

  @override
  int get hashCode => Object.hash(distanceKm, movingTime, maxKmh);
}

/// A drive on the phone's GPS alone (CLAUDE.md 6): the speed the receiver reads
/// from the Doppler shift of the satellites' signals, a distance and a time
/// worked out from it, and nothing from the car.
///
/// It fills a [VehicleState] with the speed, so that the same smoothing, the same
/// Motion and Parked rules and the same HUD that serve a drive from an adapter
/// serve this one. No other reading is ever invented: the tach, the money and the
/// coach have nothing to read, and the screen for this drive does not show them.
///
/// The speed is the receiver's, not a sum of its positions: positions wander by
/// metres while the car stands still, and a distance built from them would grow
/// at a red light. Below a walking pace the speed is taken as zero for the same
/// reason. **Fuel and money figures cannot come from GPS and are not offered.**
class GpsDrive {
  GpsDrive({
    required this.location,
    required this.clock,
    required this.scheduler,
    this.stillBelowKmh = 1.5,
    this.usableAccuracyM = 100,
    this.maxGap = const Duration(seconds: 5),
  }) : vehicle = VehicleState(
         clock: clock,
         scheduler: scheduler,
         // A fix a second: one or two missing before the number is old.
         config: const VehicleStateConfig(
           staleAfter: Duration(milliseconds: 2500),
         ),
       ) {
    status = LocationStatus(source: location, scheduler: scheduler);
    _fixes = location.fixes.listen(_onFix);
    status.hasFix.addListener(_refreshPhase);
  }

  final LocationSource location;
  final Clock clock;
  final Scheduler scheduler;

  /// Below this the car is taken to be standing: a receiver at rest still
  /// reports a metre a second or so of drift.
  final double stillBelowKmh;

  /// A fix less accurate than this (metres) is not used at all.
  final double usableAccuracyM;

  /// A gap between fixes longer than this is not driven over: the distance of a
  /// tunnel is not counted from two speeds that far apart.
  final Duration maxGap;

  /// The speed, and the mode (Motion or Parked) that follows it.
  final VehicleState vehicle;

  /// Whether the receiver has a fix, and the latest fix.
  late final LocationStatus status;

  late final StreamSubscription<LocationFix> _fixes;
  final ObservableValue<GpsPhase> _phase = ObservableValue(GpsPhase.starting);
  final ObservableValue<GpsFigures> _figures = ObservableValue(
    const GpsFigures(),
  );
  final ObservableValue<double?> _heading = ObservableValue(null);
  bool _running = false;
  bool _starting = false;
  DateTime? _lastFixAt;
  double _lastMs = 0;

  Observable<GpsPhase> get phase => _phase;

  Observable<GpsFigures> get figures => _figures;

  /// The direction of travel in degrees from north, or null when the car is
  /// standing or the receiver does not know it.
  Observable<double?> get heading => _heading;

  /// Starts the receiver, asking for the location permission if it is needed.
  /// Safe to call again, and it is what to call after the person has changed the
  /// permission.
  Future<void> start() async {
    if (_starting) return;
    _starting = true;
    _phase.value = GpsPhase.starting;
    try {
      await location.start();
      _running = true;
      _refreshPhase();
    } on LocationPermissionException {
      _running = false;
      _phase.value = GpsPhase.needsPermission;
    } on Object {
      _running = false;
      _phase.value = GpsPhase.unavailable;
    } finally {
      _starting = false;
    }
  }

  void _refreshPhase() {
    if (!_running) return;
    _phase.value = status.hasFix.value ? GpsPhase.tracking : GpsPhase.searching;
  }

  void _onFix(LocationFix fix) {
    if (fix.accuracyM > usableAccuracyM) return;
    final now = clock.monotonic();
    var kmh = fix.speedMs * 3.6;
    if (kmh < stillBelowKmh) kmh = 0;
    vehicle.ingest(Sensor.speed, kmh, at: now, receivedAt: now);
    // What the vehicle accepted, which is not this fix if it was an outlier.
    final shown = vehicle.speed.value?.value ?? 0;
    final ms = shown / 3.6;

    final previous = _lastFixAt;
    _lastFixAt = fix.time;
    var figures = _figures.value;
    if (previous != null) {
      final gap = fix.time.difference(previous);
      if (gap > Duration.zero && gap <= maxGap) {
        final seconds = gap.inMicroseconds / Duration.microsecondsPerSecond;
        figures = GpsFigures(
          distanceKm: figures.distanceKm + (ms + _lastMs) / 2 * seconds / 1000,
          movingTime: shown > 0 ? figures.movingTime + gap : figures.movingTime,
          maxKmh: figures.maxKmh,
        );
      }
    }
    // The fastest only counts from a fix that knows where it is.
    if (fix.accuracyM <= 30 && shown > figures.maxKmh) {
      figures = GpsFigures(
        distanceKm: figures.distanceKm,
        movingTime: figures.movingTime,
        maxKmh: shown,
      );
    }
    _lastMs = ms;
    _figures.value = figures;
    _heading.value = shown > 0 ? fix.headingDegrees : null;
  }

  /// Starts the trip's figures again from nothing.
  void resetTrip() {
    _figures.value = const GpsFigures();
    _lastFixAt = null;
  }

  /// Stops the receiver and lets go of everything.
  Future<void> dispose() async {
    status.hasFix.removeListener(_refreshPhase);
    await _fixes.cancel();
    await status.dispose();
    try {
      await location.stop();
    } on Object {
      // Nothing left to stop.
    }
    vehicle.dispose();
  }
}
