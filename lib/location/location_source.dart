/// One position fix from a GPS receiver.
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.speedMs,
    required this.headingDegrees,
    required this.altitudeM,
    required this.accuracyM,
    required this.time,
  });

  final double latitude;
  final double longitude;

  /// Ground speed in metres per second.
  final double speedMs;

  /// The direction of travel, 0 to 360 degrees clockwise from north. Null when
  /// it is not known, as it is when the receiver is standing still.
  final double? headingDegrees;

  /// Height above sea level in metres.
  final double altitudeM;

  /// The horizontal accuracy in metres: the radius of the circle the true
  /// position is in, with about 68% confidence (the same as Android's
  /// `Location.getAccuracy`). It grows in a street of tall buildings.
  final double accuracyM;

  /// When the fix was taken.
  final DateTime time;

  @override
  String toString() =>
      'LocationFix($latitude, $longitude, ${speedMs.toStringAsFixed(1)} m/s, '
      '±${accuracyM.toStringAsFixed(1)} m)';
}

/// The phone's location permission is not granted, or was refused.
class LocationPermissionException implements Exception {
  const LocationPermissionException();

  @override
  String toString() => 'Location permission is not granted';
}

/// Where the phone is (CLAUDE.md 6): the phone's own GPS, or the simulator's.
abstract interface class LocationSource {
  /// Fixes, about once a second, while the source is running. It is a
  /// broadcast stream.
  Stream<LocationFix> get fixes;

  /// Whether fixes are being produced.
  bool get isRunning;

  /// Starts producing fixes. Safe to call when already started.
  Future<void> start();

  /// Stops. Safe to call when already stopped.
  Future<void> stop();
}
