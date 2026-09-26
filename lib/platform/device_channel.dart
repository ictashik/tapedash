import 'package:flutter/services.dart';

import 'device_features.dart';

/// [DeviceFeatures] on the platform channels implemented by `DeviceChannel.kt`.
///
/// Unverified on hardware until the handoff (CLAUDE.md 11). The tests here run
/// against mocked channels.
class DeviceChannel implements DeviceFeatures {
  DeviceChannel({
    MethodChannel? methods,
    EventChannel? lightEvents,
    EventChannel? accelerationEvents,
  }) : _methods = methods ?? const MethodChannel('tapedash/device'),
       _lightEvents =
           lightEvents ?? const EventChannel('tapedash/device/light'),
       _accelerationEvents =
           accelerationEvents ??
           const EventChannel('tapedash/device/acceleration') {
    // Each stream is made once and shared. An EventChannel has one native
    // handler, so a second receiveBroadcastStream() would take the sensor away
    // from the first listener.
    ambientLux = _lightEvents.receiveBroadcastStream().map(_toLux);
    acceleration = _accelerationEvents.receiveBroadcastStream().map(
      _toAcceleration,
    );
  }

  final MethodChannel _methods;
  final EventChannel _lightEvents;
  final EventChannel _accelerationEvents;

  @override
  late final Stream<double> ambientLux;

  @override
  late final Stream<Acceleration> acceleration;

  @override
  Future<void> setKeepScreenOn(bool enabled) =>
      _methods.invokeMethod<void>('setKeepScreenOn', {'enabled': enabled});

  @override
  Future<void> setImmersive(bool enabled) =>
      _methods.invokeMethod<void>('setImmersive', {'enabled': enabled});

  @override
  Future<void> setBrightness(double? level) {
    if (level != null && level.isNaN) {
      throw ArgumentError.value(level, 'level', 'must be a number');
    }
    return _methods.invokeMethod<void>('setBrightness', {
      'level': level?.clamp(0.0, 1.0).toDouble(),
    });
  }

  @override
  Future<double?> batteryTemperatureCelsius() async {
    final celsius = await _methods.invokeMethod<num>('batteryTemperature');
    return celsius?.toDouble();
  }

  @override
  Future<SensorSupport> sensorSupport() async {
    final support = await _methods.invokeMapMethod<String, Object?>(
      'sensorSupport',
    );
    return SensorSupport(
      ambientLight: support?['ambientLight'] == true,
      accelerometer: support?['accelerometer'] == true,
    );
  }

  static double _toLux(Object? event) => (event! as num).toDouble();

  static Acceleration _toAcceleration(Object? event) {
    final values = event! as List<Object?>;
    if (values.length != 3) {
      throw FormatException('Expected x, y and z, got ${values.length}', event);
    }
    return Acceleration(
      (values[0]! as num).toDouble(),
      (values[1]! as num).toDouble(),
      (values[2]! as num).toDouble(),
    );
  }
}
