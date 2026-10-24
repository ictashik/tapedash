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
    EventChannel? rotaryEvents,
  }) : _methods = methods ?? const MethodChannel('tapedash/device'),
       _lightEvents =
           lightEvents ?? const EventChannel('tapedash/device/light'),
       _accelerationEvents =
           accelerationEvents ??
           const EventChannel('tapedash/device/acceleration'),
       _rotaryEvents =
           rotaryEvents ?? const EventChannel('tapedash/device/rotary') {
    // Each stream is made once and shared. An EventChannel has one native
    // handler, so a second receiveBroadcastStream() would take the sensor away
    // from the first listener.
    ambientLux = _lightEvents.receiveBroadcastStream().map(_toLux);
    acceleration = _accelerationEvents.receiveBroadcastStream().map(
      _toAcceleration,
    );
    rotary = _rotaryEvents.receiveBroadcastStream().map(_toDetent);
  }

  final MethodChannel _methods;
  final EventChannel _lightEvents;
  final EventChannel _accelerationEvents;
  final EventChannel _rotaryEvents;

  @override
  late final Stream<double> ambientLux;

  @override
  late final Stream<Acceleration> acceleration;

  @override
  late final Stream<int> rotary;

  @override
  Future<FormFactorInfo> formFactor() async {
    try {
      final info = await _methods.invokeMapMethod<String, Object?>(
        'formFactor',
      );
      return FormFactorInfo(
        isWatch: info?['watch'] == true,
        isRound: info?['round'] == true,
      );
    } on MissingPluginException {
      return FormFactorInfo.phone;
    }
  }

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
  Future<String?> externalFilesDirectory() =>
      _methods.invokeMethod<String>('externalFilesDirectory');

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

  // One detent is +1 or -1; a bezel that sends more than one at once (a fast
  // turn) is a bigger number, and the sign is the direction.
  static int _toDetent(Object? event) => (event! as num).toInt();

  // The Android side sends what the sensor gave it, [x, y, z] in the phone's
  // own axes, plus the display rotation in quarter turns (Surface.ROTATION_*).
  // The remapping to screen axes is here so it is unit-tested.
  static Acceleration _toAcceleration(Object? event) {
    final values = event! as List<Object?>;
    if (values.length != 4) {
      throw FormatException(
        'Expected x, y, z and the display rotation, got ${values.length} values',
        event,
      );
    }
    final x = (values[0]! as num).toDouble();
    final y = (values[1]! as num).toDouble();
    final z = (values[2]! as num).toDouble();
    final quarterTurns = (values[3]! as num).toInt();

    // The display is rotated by `quarterTurns` from the phone's natural
    // orientation, so a reading in the phone's axes is turned back to follow
    // the screen. Android's own sensor samples use the same mapping.
    return switch (quarterTurns) {
      0 => Acceleration(x, y, z),
      1 => Acceleration(-y, x, z),
      2 => Acceleration(-x, -y, z),
      3 => Acceleration(y, -x, z),
      _ => throw FormatException(
        'Unknown display rotation $quarterTurns',
        event,
      ),
    };
  }
}
