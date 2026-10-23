import 'dart:async';

import 'package:tapedash/location/location_source.dart';

/// A GPS receiver a test drives by hand: it says when it was started and stopped,
/// refuses as a phone without the permission does, and gives the fixes the test
/// emits, a second apart unless told otherwise. Like the simulated one, it
/// delivers synchronously.
class FakeLocation implements LocationSource {
  FakeLocation({this.permission = true, this.unavailable = false});

  /// Whether the location permission is granted. Starting without it fails.
  bool permission;

  /// Whether the phone has no GPS receiver at all: starting fails otherwise.
  bool unavailable;

  int started = 0;
  int stopped = 0;
  bool _running = false;
  DateTime _at = DateTime.utc(2026, 10, 23, 9);

  final StreamController<LocationFix> _fixes =
      StreamController<LocationFix>.broadcast(sync: true);

  @override
  Stream<LocationFix> get fixes => _fixes.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<void> start() async {
    started++;
    if (unavailable) throw StateError('This phone has no GPS');
    if (!permission) throw const LocationPermissionException();
    _running = true;
  }

  @override
  Future<void> stop() async {
    stopped++;
    _running = false;
  }

  /// A fix at [kmh], [after] the last one.
  void emit({
    required double kmh,
    double accuracyM = 5,
    double? heading,
    Duration after = const Duration(seconds: 1),
    double latitude = 12.97,
    double longitude = 77.59,
  }) {
    _at = _at.add(after);
    _fixes.add(
      LocationFix(
        latitude: latitude,
        longitude: longitude,
        speedMs: kmh / 3.6,
        headingDegrees: heading,
        altitudeM: 920,
        accuracyM: accuracyM,
        time: _at,
      ),
    );
  }

  Future<void> close() => _fixes.close();
}
