/// What a scripted driver means to be doing, over and above the pedals.
///
/// The ground truth logs a hard-acceleration or hard-braking event for each
/// stretch where the driver is being hard, so the tests can check that the app
/// detects the events that were scripted (CLAUDE.md 7.1, 7.3).
enum DriverIntent { normal, hardAcceleration, hardBraking }

/// The driver's inputs to the car for one step (CLAUDE.md 7.1).
class DriverInputs {
  const DriverInputs({
    this.throttle = 0,
    this.brake = 0,
    this.ignitionOn = true,
    this.intent = DriverIntent.normal,
  });

  /// Accelerator pedal, 0 to 1.
  final double throttle;

  /// Brake pedal, 0 to 1.
  final double brake;

  final bool ignitionOn;
  final DriverIntent intent;

  /// Ignition on, both pedals up.
  static const DriverInputs idle = DriverInputs();

  /// Ignition off.
  static const DriverInputs off = DriverInputs(ignitionOn: false);

  DriverInputs copyWith({
    double? throttle,
    double? brake,
    bool? ignitionOn,
    DriverIntent? intent,
  }) => DriverInputs(
    throttle: throttle ?? this.throttle,
    brake: brake ?? this.brake,
    ignitionOn: ignitionOn ?? this.ignitionOn,
    intent: intent ?? this.intent,
  );

  @override
  String toString() =>
      'DriverInputs(throttle: $throttle, brake: $brake, '
      'ignition: ${ignitionOn ? 'on' : 'off'}, $intent)';
}
