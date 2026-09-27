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
  load('%', staleFactor: 2),

  /// Coolant temperature.
  coolant('°C', staleFactor: 8),

  /// Intake air temperature.
  intakeAir('°C', staleFactor: 8),

  /// Intake manifold absolute pressure.
  manifoldPressure('kPa', staleFactor: 2),

  /// Mass air flow.
  airFlow('g/s', staleFactor: 2),

  /// Fuel tank level, 0 to 100.
  fuelLevel('%', staleFactor: 8),

  /// The car's module voltage: the battery, or the alternator when running.
  voltage('V', staleFactor: 8),

  /// Engine fuel rate, as the ECU reports it.
  fuelRate('L/h', staleFactor: 2);

  const Sensor(this.unit, {this.maxChangePerSecond, this.staleFactor = 1});

  /// The unit of a reading, for diagnostics; the UI has its own formatting.
  final String unit;

  /// The fastest this can really change, per second, or null if it is not
  /// checked. A reading that implies more is an outlier (DESIGN.md 5.2):
  /// 10,000 rpm/s for the engine, and 15 km/h in 100 ms for road speed.
  final double? maxChangePerSecond;

  /// How many times the ordinary 1.5 s a reading may go without a successor
  /// before it is stale. The fast tier (RPM, speed and throttle) is read every
  /// cycle and is stale at 1.5 s (DESIGN.md 5.2). The medium tier is read
  /// about once a second and the slow tier every four, so at 1.5 s they would
  /// be stale most of the time: theirs are 3 s and 12 s.
  final int staleFactor;
}
