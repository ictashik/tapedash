/// One measurement of a sensor.
class Reading {
  const Reading({
    required this.value,
    required this.at,
    required this.receivedAt,
  });

  /// The value, in the sensor's unit.
  final double value;

  /// When it was measured, on the monotonic clock. For a value read over the
  /// OBD port this is the middle of the request's round trip, since the ECU read
  /// it while the request was on its way (DESIGN.md 5.2).
  final Duration at;

  /// When it arrived, on the monotonic clock. Staleness is counted from this.
  final Duration receivedAt;

  /// How long ago it arrived.
  Duration age(Duration now) => now - receivedAt;

  @override
  bool operator ==(Object other) =>
      other is Reading &&
      other.value == value &&
      other.at == at &&
      other.receivedAt == receivedAt;

  @override
  int get hashCode => Object.hash(value, at, receivedAt);

  @override
  String toString() => 'Reading($value at ${at.inMilliseconds} ms)';
}
