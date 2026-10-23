import 'dart:async';

import 'package:flutter/services.dart';

import '../location/location_source.dart';

export '../location/location_source.dart' show LocationPermissionException;

/// [LocationSource] on the platform channels implemented by `GpsChannel.kt`
/// (CLAUDE.md 5): the phone's own GNSS receiver, through `LocationManager`, with
/// no fused provider and no Play Services.
///
/// Unverified on hardware until the handoff (CLAUDE.md 11). The tests run against
/// mocked channels.
class NativeLocationSource implements LocationSource {
  NativeLocationSource({MethodChannel? methods, EventChannel? events})
    : _methods = methods ?? const MethodChannel('tapedash/gps'),
      _events = events ?? const EventChannel('tapedash/gps/fixes');

  final MethodChannel _methods;
  final EventChannel _events;

  final StreamController<LocationFix> _fixes = StreamController.broadcast();
  StreamSubscription<Object?>? _subscription;
  bool _running = false;

  @override
  Stream<LocationFix> get fixes => _fixes.stream;

  @override
  bool get isRunning => _running;

  /// Whether the location permission is granted.
  Future<bool> hasPermission() async =>
      await _methods.invokeMethod<bool>('hasPermission') ?? false;

  /// Asks for the permission if it is not granted, and says whether it is now.
  Future<bool> requestPermission() async =>
      await _methods.invokeMethod<bool>('requestPermission') ?? false;

  /// Whether the GPS is switched on in the phone's settings.
  Future<bool> isEnabled() async =>
      await _methods.invokeMethod<bool>('isEnabled') ?? false;

  /// Starts producing fixes, asking for the permission first. Throws
  /// [LocationPermissionException] if it is refused.
  @override
  Future<void> start() async {
    if (_running) return;
    if (!await requestPermission()) throw const LocationPermissionException();
    _subscription = _events.receiveBroadcastStream().listen(
      (event) {
        final fix = fixFrom(event);
        if (fix != null) _fixes.add(fix);
      },
      // A stream error is a receiver that has gone: the fixes stop and the
      // source says so.
      onError: (Object _) => _running = false,
    );
    try {
      await _methods.invokeMethod<void>('start');
    } on PlatformException catch (e) {
      await _subscription?.cancel();
      _subscription = null;
      if (e.code == 'permission_denied') {
        throw const LocationPermissionException();
      }
      rethrow;
    }
    _running = true;
  }

  @override
  Future<void> stop() async {
    if (!_running && _subscription == null) return;
    _running = false;
    await _subscription?.cancel();
    _subscription = null;
    await _methods.invokeMethod<void>('stop');
  }

  /// A fix from what the Android side sends: a map of latitude, longitude, speed
  /// (m/s, -1 when the receiver has none), bearing (null when not known),
  /// altitude, accuracy (m, -1 when not known) and the time in milliseconds. Null
  /// for anything malformed, so one bad message does not end the stream.
  static LocationFix? fixFrom(Object? event) {
    if (event is! Map) return null;
    final latitude = event['latitude'];
    final longitude = event['longitude'];
    final time = event['timeMillis'];
    if (latitude is! num || longitude is! num || time is! num) return null;
    final speed = (event['speed'] as num?)?.toDouble() ?? -1;
    final accuracy = (event['accuracy'] as num?)?.toDouble() ?? -1;
    return LocationFix(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      // A receiver with no speed gives -1; the honest value is 0 m/s, with the
      // accuracy saying how much to trust it.
      speedMs: speed < 0 ? 0 : speed,
      headingDegrees: (event['bearing'] as num?)?.toDouble(),
      altitudeM: (event['altitude'] as num?)?.toDouble() ?? 0,
      // No accuracy is treated as a bad one, not a perfect one.
      accuracyM: accuracy < 0 ? 999 : accuracy,
      time: DateTime.fromMillisecondsSinceEpoch(time.toInt(), isUtc: true),
    );
  }
}
