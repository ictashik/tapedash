/// Every threshold the coach judges driving by (CLAUDE.md 8.8), in one place so
/// that each is configurable and tested. The Garage's Gentle, Normal and Sporty
/// presets choose between them.
class CoachThresholds {
  const CoachThresholds({
    this.hardAccelerationMs2 = 2.5,
    this.hardAccelerationSeconds = 1.0,
    this.hardAccelerationThrottlePercent = 70,
    this.hardAccelerationThrottleSeconds = 2.0,
    this.hardAccelerationMinSpeedKmh = 10,
    this.hardBrakingMs2 = 3.5,
    this.hardBrakingSeconds = 0.5,
    this.longIdleSeconds = 60,
    this.highRpm = 3500,
    this.highRpmSeconds = 3,
    this.speedLimitKmh = 100,
    this.speedingSeconds = 10,
    this.releaseGraceSeconds = 0.7,
  });

  /// Smoothed acceleration above this, for [hardAccelerationSeconds]; or
  /// throttle above [hardAccelerationThrottlePercent] for
  /// [hardAccelerationThrottleSeconds] while going faster than
  /// [hardAccelerationMinSpeedKmh].
  final double hardAccelerationMs2;
  final double hardAccelerationSeconds;
  final double hardAccelerationThrottlePercent;
  final double hardAccelerationThrottleSeconds;
  final double hardAccelerationMinSpeedKmh;

  /// Smoothed deceleration beyond this, for [hardBrakingSeconds].
  final double hardBrakingMs2;
  final double hardBrakingSeconds;

  /// Idling for more than this many seconds without a break.
  final double longIdleSeconds;

  /// Above this many rpm for more than [highRpmSeconds].
  final double highRpm;
  final double highRpmSeconds;

  /// Above this speed for more than [speedingSeconds]; also where the money
  /// attribution's "high speed" bucket begins.
  final double speedLimitKmh;
  final double speedingSeconds;

  /// A hard event does not end until its condition has been false this long,
  /// so that acceleration jittering about a threshold stays one event.
  final double releaseGraceSeconds;

  static const CoachThresholds normal = CoachThresholds();

  static const CoachThresholds gentle = CoachThresholds(
    hardAccelerationMs2: 2.0,
    hardAccelerationThrottlePercent: 60,
    hardBrakingMs2: 3.0,
    highRpm: 3000,
  );

  static const CoachThresholds sporty = CoachThresholds(
    hardAccelerationMs2: 3.5,
    hardAccelerationThrottlePercent: 85,
    hardBrakingMs2: 4.5,
    highRpm: 4500,
  );

  CoachThresholds copyWith({double? speedLimitKmh}) => CoachThresholds(
    hardAccelerationMs2: hardAccelerationMs2,
    hardAccelerationSeconds: hardAccelerationSeconds,
    hardAccelerationThrottlePercent: hardAccelerationThrottlePercent,
    hardAccelerationThrottleSeconds: hardAccelerationThrottleSeconds,
    hardAccelerationMinSpeedKmh: hardAccelerationMinSpeedKmh,
    hardBrakingMs2: hardBrakingMs2,
    hardBrakingSeconds: hardBrakingSeconds,
    longIdleSeconds: longIdleSeconds,
    highRpm: highRpm,
    highRpmSeconds: highRpmSeconds,
    speedLimitKmh: speedLimitKmh ?? this.speedLimitKmh,
    speedingSeconds: speedingSeconds,
    releaseGraceSeconds: releaseGraceSeconds,
  );
}
