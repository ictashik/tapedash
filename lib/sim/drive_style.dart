/// How a scripted driver drives: how hard it accelerates and brakes, and how
/// quickly it moves its feet.
///
/// The same route driven [gentle] and [hard] is what shows that driving style
/// changes what a trip costs, which is the premise of the coach (CLAUDE.md 7.3).
class DriveStyle {
  const DriveStyle({
    required this.accelerationMs2,
    required this.brakeDecelerationMs2,
    required this.pedalRatePerSecond,
    required this.brakeRatePerSecond,
    this.hard = false,
    this.coastEarly = false,
  });

  /// The acceleration the driver asks for when pulling away, m/s2.
  final double accelerationMs2;

  /// The deceleration the driver plans to stop with, m/s2.
  final double brakeDecelerationMs2;

  /// How fast the accelerator and the brake pedals are pressed, in pedal
  /// travel per second. Releasing is always quick.
  final double pedalRatePerSecond;
  final double brakeRatePerSecond;

  /// Whether the ground truth should log this driver's hard accelerations and
  /// hard braking as events.
  final bool hard;

  /// Lifts off early and coasts towards a stop, instead of driving up to it
  /// and braking.
  final bool coastEarly;

  /// Smooth and early: coasts to stops, accelerates gently.
  static const DriveStyle gentle = DriveStyle(
    accelerationMs2: 0.9,
    brakeDecelerationMs2: 1.1,
    pedalRatePerSecond: 0.6,
    brakeRatePerSecond: 1.2,
    coastEarly: true,
  );

  /// An ordinary driver.
  static const DriveStyle normal = DriveStyle(
    accelerationMs2: 1.6,
    brakeDecelerationMs2: 2.2,
    pedalRatePerSecond: 1.6,
    brakeRatePerSecond: 3,
  );

  /// Hard on the throttle and hard on the brakes: well above the coach's
  /// thresholds of 2.5 m/s2 and 3.5 m/s2 (CLAUDE.md 8.8). It has to be, because
  /// the app smooths speed over about a second before it looks at acceleration,
  /// and that lag hides an acceleration that is only just over the threshold or
  /// does not last. The car cannot do much more than 3.5 m/s2 from a standstill,
  /// so this asks for all of it.
  static const DriveStyle hardDriving = DriveStyle(
    accelerationMs2: 3.6,
    brakeDecelerationMs2: 5.0,
    pedalRatePerSecond: 8,
    brakeRatePerSecond: 12,
    hard: true,
  );
}
