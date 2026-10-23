import 'package:flutter/foundation.dart';

import '../../../core/clock.dart';
import '../../../core/observable.dart';
import '../../../core/scheduler.dart';
import '../../../location/gps_drive.dart';
import '../../../obd/obd_session.dart' show ConnectionStatus;
import '../../design/motion/ignition_sequence.dart';
import '../../design/motion/motion_clock.dart';
import '../../design/motion/numeral_source.dart';
import '../../design/motion/observable_listenable.dart';
import 'drive_signals.dart';

/// One of a GPS drive's whole-trip figures as a number to roll: the distance, the
/// average or the fastest. The figures change once a second at most, so this is a
/// plain listener on them, with nothing to smooth.
class GpsFigureSource extends ChangeNotifier implements NumeralSource {
  GpsFigureSource(this._figures, this._pick) {
    _figures.addListener(notifyListeners);
  }

  final Observable<GpsFigures> _figures;
  final double? Function(GpsFigures) _pick;

  @override
  double get value => _pick(_figures.value) ?? 0;

  @override
  double get staleness => 0;

  @override
  bool get hasValue => _pick(_figures.value) != null;

  @override
  void dispose() {
    _figures.removeListener(notifyListeners);
    super.dispose();
  }
}

/// What the GPS screen reads, bound once to a [GpsDrive]: the same
/// [DriveSignals] a drive from an adapter has (the speed's spring, the Motion and
/// Parked share, the clock), the trip figures as numbers to roll, and the phase
/// as something to listen to.
class GpsSignals {
  GpsSignals({
    required this.gps,
    required MotionClock motion,
    required Clock clock,
    required Scheduler scheduler,
    ValueListenable<bool>? phoneHot,
    bool reduceMotion = false,
  }) : _phase = ObservableListenable(gps.phase),
       _figures = ObservableListenable(gps.figures),
       heading = ObservableListenable(gps.heading),
       distance = GpsFigureSource(gps.figures, (f) => f.distanceKm),
       average = GpsFigureSource(gps.figures, (f) => f.averageKmh),
       fastest = GpsFigureSource(gps.figures, (f) => f.maxKmh),
       _link = ObservableValue(ConnectionStatus.searching) {
    drive = DriveSignals(
      vehicle: gps.vehicle,
      motion: motion,
      clock: clock,
      scheduler: scheduler,
      connection: _link,
      // There is no engine to light: the cluster's ignition sequence is the
      // tach's, and the GPS screen has no tach.
      ignitionMode: IgnitionMode.off,
      reduceMotion: reduceMotion,
      gpsHasFix: ObservableListenable(gps.status.hasFix),
      phoneHot: phoneHot,
    );
    gps.phase.addListener(_onPhase);
    _onPhase();
    gps.vehicle.speed.addListener(_onSpeed);
    _onSpeed();
  }

  final GpsDrive gps;
  late final DriveSignals drive;

  final ObservableListenable<GpsPhase> _phase;
  final ObservableListenable<GpsFigures> _figures;

  /// The direction of travel in degrees, or null.
  final ObservableListenable<double?> heading;

  final GpsFigureSource distance;
  final GpsFigureSource average;
  final GpsFigureSource fastest;
  final ObservableValue<ConnectionStatus> _link;
  final ValueNotifier<bool> hasSpeed = ValueNotifier(false);

  ValueListenable<GpsPhase> get phase => _phase;

  /// The distance, the moving time and the fastest, for the readouts that are
  /// text and not rolling numbers.
  ValueListenable<GpsFigures> get figures => _figures;

  void _onPhase() {
    _link.value = gps.phase.value == GpsPhase.tracking
        ? ConnectionStatus.connected
        : ConnectionStatus.searching;
  }

  // The speed on screen is a number as soon as there has been one: a fix lost in
  // a tunnel dims it (it goes stale) but never swaps it for a message.
  void _onSpeed() =>
      hasSpeed.value = hasSpeed.value || gps.vehicle.speed.value != null;

  void dispose() {
    gps.phase.removeListener(_onPhase);
    gps.vehicle.speed.removeListener(_onSpeed);
    drive.dispose();
    _phase.dispose();
    _figures.dispose();
    heading.dispose();
    distance.dispose();
    average.dispose();
    fastest.dispose();
    hasSpeed.dispose();
    _link.dispose();
  }
}
