/// What the car measures, whatever reads it: the OBD port, a recording or a
/// simulation. The vehicle model is built on these and knows nothing of PIDs.
enum Sensor {
  /// Engine speed.
  rpm('rpm', maxChangePerSecond: 10000),

  /// Road speed from the car's own sensor, which is whole km/h.
  speed('km/h', maxChangePerSecond: 150),

  /// Throttle position, 0 to 100.
  throttle('%'),

  /// Calculated engine load, 0 to 100.
  load('%'),

  /// Coolant temperature.
  coolant('°C'),

  /// Intake air temperature.
  intakeAir('°C'),

  /// Intake manifold absolute pressure.
  manifoldPressure('kPa'),

  /// Mass air flow.
  airFlow('g/s'),

  /// Fuel tank level, 0 to 100.
  fuelLevel('%'),

  /// The car's module voltage: the battery, or the alternator when running.
  voltage('V'),

  /// Engine fuel rate, as the ECU reports it.
  fuelRate('L/h');

  const Sensor(this.unit, {this.maxChangePerSecond});

  /// The unit of a reading, for diagnostics; the UI has its own formatting.
  final String unit;

  /// The fastest this can really change, per second, or null if it is not
  /// checked. A reading that implies more is an outlier (DESIGN.md 5.2):
  /// 10,000 rpm/s for the engine, and 15 km/h in 100 ms for road speed.
  final double? maxChangePerSecond;
}
