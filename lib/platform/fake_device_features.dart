import 'dart:async';

import 'device_features.dart';

/// A [DeviceFeatures] that does nothing on a phone, for tests and for anything
/// that has to run without one. It remembers what it was told, and its sensors
/// emit whatever the caller pushes into them.
class FakeDeviceFeatures implements DeviceFeatures {
  bool keepScreenOn = false;
  bool immersive = false;

  /// The last brightness set, or null for the phone's own setting.
  double? brightness;

  /// What [batteryTemperatureCelsius] returns. Null means the phone does not
  /// report one.
  double? batteryTemperature = 30;

  SensorSupport support = const SensorSupport(
    ambientLight: true,
    accelerometer: true,
  );

  final StreamController<double> _lux = StreamController<double>.broadcast();
  final StreamController<Acceleration> _acceleration =
      StreamController<Acceleration>.broadcast();

  void emitLux(double lux) => _lux.add(lux);

  void emitAcceleration(Acceleration acceleration) =>
      _acceleration.add(acceleration);

  /// Closes the sensor streams.
  Future<void> dispose() => Future.wait([_lux.close(), _acceleration.close()]);

  @override
  Stream<double> get ambientLux => _lux.stream;

  @override
  Stream<Acceleration> get acceleration => _acceleration.stream;

  @override
  Future<void> setKeepScreenOn(bool enabled) async => keepScreenOn = enabled;

  @override
  Future<void> setImmersive(bool enabled) async => immersive = enabled;

  @override
  Future<void> setBrightness(double? level) async {
    if (level != null && level.isNaN) {
      throw ArgumentError.value(level, 'level', 'must be a number');
    }
    brightness = level?.clamp(0.0, 1.0).toDouble();
  }

  @override
  Future<double?> batteryTemperatureCelsius() async => batteryTemperature;

  @override
  Future<SensorSupport> sensorSupport() async => support;
}
