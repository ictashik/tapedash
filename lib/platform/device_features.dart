/// What the phone offers that Flutter does not: the screen's power and
/// brightness, the battery, and two sensors (CLAUDE.md 5, "Device features").
///
/// Code that needs any of this takes a [DeviceFeatures], so it can be tested
/// with [FakeDeviceFeatures] and never depends on the Android side.
abstract interface class DeviceFeatures {
  /// Keeps the screen on while the app is in front. A dashboard that goes dark
  /// is no use.
  Future<void> setKeepScreenOn(bool enabled);

  /// Hides the status and navigation bars. Swiping in from the edge shows them
  /// briefly.
  Future<void> setImmersive(bool enabled);

  /// Sets this window's brightness from 0 to 1, or goes back to the phone's own
  /// setting when [level] is null.
  ///
  /// A value outside 0 to 1 is clamped, and NaN is an [ArgumentError]. The
  /// screen is never turned fully off: some phones treat 0 as backlight off, so
  /// the Android side keeps a small floor.
  Future<void> setBrightness(double? level);

  /// The battery temperature in degrees Celsius, or null if the phone does not
  /// report one. It is the best stand-in for how hot the phone is (CLAUDE.md 9).
  Future<double?> batteryTemperatureCelsius();

  /// The folder the app may write files to that its user can reach over USB
  /// (`Android/data/<package>/files`), or null if the phone has none. Session
  /// recordings go here (CLAUDE.md 11).
  Future<String?> externalFilesDirectory();

  /// Which of the sensors below this phone has. Without an ambient light sensor
  /// the app falls back to sunrise and sunset (DESIGN.md 4.4).
  Future<SensorSupport> sensorSupport();

  /// Ambient light in lux, a few times a second. It drives the Daylight and
  /// Night modes (DESIGN.md 4.4).
  ///
  /// A broadcast stream. The sensor is only on while something listens. On a
  /// phone without the sensor it emits an error and ends.
  Stream<double> get ambientLux;

  /// Acceleration about 25 times a second. It drives the road view's body roll
  /// (DESIGN.md 6.11).
  ///
  /// A broadcast stream. The sensor is only on while something listens. On a
  /// phone without the sensor it emits an error and ends.
  Stream<Acceleration> get acceleration;
}

/// Which sensors a phone has.
class SensorSupport {
  const SensorSupport({
    required this.ambientLight,
    required this.accelerometer,
  });

  final bool ambientLight;
  final bool accelerometer;

  @override
  bool operator ==(Object other) =>
      other is SensorSupport &&
      other.ambientLight == ambientLight &&
      other.accelerometer == accelerometer;

  @override
  int get hashCode => Object.hash(ambientLight, accelerometer);

  @override
  String toString() =>
      'SensorSupport(ambientLight: $ambientLight, accelerometer: $accelerometer)';
}

/// One accelerometer reading, in m/s2, including gravity.
///
/// The axes follow the screen as it is drawn, whichever landscape direction the
/// phone is in: [x] to the right, [y] up the screen, [z] out of the screen. A
/// phone standing still and upright reads about 9.8 on [y].
class Acceleration {
  const Acceleration(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  @override
  bool operator ==(Object other) =>
      other is Acceleration && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'Acceleration($x, $y, $z)';
}
