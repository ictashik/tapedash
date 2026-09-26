/// A stretch of scripted hard driving.
enum TruthEventType { hardAcceleration, hardBraking }

/// One scripted hard-acceleration or hard-braking event, as it really
/// happened in the simulation.
class TruthEvent {
  const TruthEvent({
    required this.type,
    required this.startSeconds,
    required this.startSpeedKmh,
    this.endSeconds,
    this.endSpeedKmh,
    this.peakAccelerationMs2 = 0,
  });

  final TruthEventType type;
  final double startSeconds;
  final double startSpeedKmh;

  /// Null while the event is still going on.
  final double? endSeconds;
  final double? endSpeedKmh;

  /// The largest acceleration or deceleration during the event, as a positive
  /// number.
  final double peakAccelerationMs2;

  double? get durationSeconds =>
      endSeconds == null ? null : endSeconds! - startSeconds;

  @override
  String toString() =>
      'TruthEvent($type, ${startSeconds.toStringAsFixed(1)}s '
      'to ${endSeconds?.toStringAsFixed(1)}s)';
}

/// What the simulation knows for certain, so tests can compare the app's
/// estimates with the truth (CLAUDE.md 7.1).
class GroundTruth {
  const GroundTruth({
    required this.fuelLitres,
    required this.distanceKm,
    required this.engineOnSeconds,
    required this.idleSeconds,
    required this.idleFuelLitres,
    required this.events,
  });

  /// Fuel burnt since the start, in litres.
  final double fuelLitres;

  final double distanceKm;

  /// Seconds with the engine running.
  final double engineOnSeconds;

  /// Seconds with the engine running and the car below 2 km/h, which is how
  /// CLAUDE.md 8.7 defines idling.
  final double idleSeconds;

  /// Fuel burnt while idling, in litres.
  final double idleFuelLitres;

  /// Every scripted hard-acceleration and hard-braking event, in order. The
  /// last may still be open.
  final List<TruthEvent> events;

  int get hardAccelerationCount =>
      events.where((e) => e.type == TruthEventType.hardAcceleration).length;

  int get hardBrakingCount =>
      events.where((e) => e.type == TruthEventType.hardBraking).length;
}
