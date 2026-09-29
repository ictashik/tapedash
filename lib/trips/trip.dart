import '../fuel/fuel_estimator.dart';
import '../money/spend_bucket.dart';

/// One drive, from the engine starting to the engine being switched off
/// (CLAUDE.md 8.6).
class Trip {
  const Trip({
    this.id,
    required this.startedAt,
    this.endedAt,
    this.isDemo = false,
    this.distanceKm = 0,
    this.litres = 0,
    this.uncalibratedLitres = 0,
    this.cost,
    this.pricePerLitre,
    this.idleSeconds = 0,
    this.engineSeconds = 0,
    this.bucketLitres = const {},
    this.blockBuckets = const [],
    this.fuelSource = FuelSource.none,
    this.lowConfidence = false,
    this.calibrationFactor = 1,
    this.hardAccelerations = 0,
    this.hardBrakings = 0,
    this.longIdles = 0,
    this.longestIdleSeconds = 0,
    this.highRpmSeconds = 0,
    this.speedingSeconds = 0,
  });

  final int? id;
  final DateTime startedAt;

  /// Null while the trip is going on, or within the five minutes it can still
  /// be resumed.
  final DateTime? endedAt;

  /// Driven in Demo Mode: stored, but never counted in real statistics
  /// (CLAUDE.md 7.6).
  final bool isDemo;

  final double distanceKm;

  /// Fuel used, calibrated, and the raw estimate it was worked out from.
  final double litres;
  final double uncalibratedLitres;

  /// Null when no price was set.
  final double? cost;
  final double? pricePerLitre;

  final double idleSeconds;

  /// Seconds with the engine running.
  final double engineSeconds;

  final Map<SpendBucket, double> bucketLitres;

  /// Which bucket each rupee block fell in, in order (the Money Tape).
  final List<SpendBucket> blockBuckets;

  final FuelSource fuelSource;
  final bool lowConfidence;
  final double calibrationFactor;
  final int hardAccelerations;
  final int hardBrakings;

  /// The coach's duration rules (CLAUDE.md 8.8): stops of more than a minute with
  /// the engine on, the longest of them, seconds above the high-rpm threshold, and
  /// seconds above the speed threshold.
  final int longIdles;
  final double longestIdleSeconds;
  final double highRpmSeconds;
  final double speedingSeconds;

  bool get isOpen => endedAt == null;

  double? get kmPerLitre =>
      distanceKm < 0.1 || litres <= 0 ? null : distanceKm / litres;

  double? get costPerKm =>
      cost == null || distanceKm < 0.1 ? null : cost! / distanceKm;

  Trip copyWith({
    int? id,
    Object? endedAt = _keep,
    double? distanceKm,
    double? litres,
    double? uncalibratedLitres,
    Object? cost = _keep,
    Object? pricePerLitre = _keep,
    double? idleSeconds,
    double? engineSeconds,
    Map<SpendBucket, double>? bucketLitres,
    List<SpendBucket>? blockBuckets,
    FuelSource? fuelSource,
    bool? lowConfidence,
    double? calibrationFactor,
    int? hardAccelerations,
    int? hardBrakings,
    int? longIdles,
    double? longestIdleSeconds,
    double? highRpmSeconds,
    double? speedingSeconds,
  }) => Trip(
    id: id ?? this.id,
    startedAt: startedAt,
    endedAt: identical(endedAt, _keep) ? this.endedAt : endedAt as DateTime?,
    isDemo: isDemo,
    distanceKm: distanceKm ?? this.distanceKm,
    litres: litres ?? this.litres,
    uncalibratedLitres: uncalibratedLitres ?? this.uncalibratedLitres,
    cost: identical(cost, _keep) ? this.cost : cost as double?,
    pricePerLitre: identical(pricePerLitre, _keep)
        ? this.pricePerLitre
        : pricePerLitre as double?,
    idleSeconds: idleSeconds ?? this.idleSeconds,
    engineSeconds: engineSeconds ?? this.engineSeconds,
    bucketLitres: bucketLitres ?? this.bucketLitres,
    blockBuckets: blockBuckets ?? this.blockBuckets,
    fuelSource: fuelSource ?? this.fuelSource,
    lowConfidence: lowConfidence ?? this.lowConfidence,
    calibrationFactor: calibrationFactor ?? this.calibrationFactor,
    hardAccelerations: hardAccelerations ?? this.hardAccelerations,
    hardBrakings: hardBrakings ?? this.hardBrakings,
    longIdles: longIdles ?? this.longIdles,
    longestIdleSeconds: longestIdleSeconds ?? this.longestIdleSeconds,
    highRpmSeconds: highRpmSeconds ?? this.highRpmSeconds,
    speedingSeconds: speedingSeconds ?? this.speedingSeconds,
  );

  static const Object _keep = Object();
}

/// One second of a trip, for the route, the telemetry scrubber and the
/// sweet-spot statistics.
class TripSample {
  const TripSample({
    required this.seconds,
    required this.speedKmh,
    required this.rpm,
    required this.throttle,
    required this.litresPerHour,
    this.latitude,
    this.longitude,
  });

  /// Seconds since the trip started.
  final double seconds;
  final double speedKmh;
  final double rpm;
  final double throttle;

  /// Fuel flow, calibrated.
  final double litresPerHour;
  final double? latitude;
  final double? longitude;
}

/// The trip log. It has an in-memory implementation for tests and a sqflite one
/// for the app (CLAUDE.md 6).
abstract interface class TripRepository {
  /// Saves a new trip and returns it with its id.
  Future<Trip> create(Trip trip);

  Future<void> update(Trip trip);

  /// Adds samples to a trip, in order.
  Future<void> addSamples(int tripId, List<TripSample> samples);

  /// Trips, newest first. Demo trips are left out unless [includeDemo].
  Future<List<Trip>> all({bool includeDemo = false});

  Future<Trip?> get(int id);

  Future<List<TripSample>> samples(int tripId);

  Future<void> delete(int id);
}

class MemoryTripRepository implements TripRepository {
  final Map<int, Trip> _trips = {};
  final Map<int, List<TripSample>> _samples = {};
  int _next = 1;

  @override
  Future<Trip> create(Trip trip) async {
    final saved = trip.copyWith(id: _next++);
    _trips[saved.id!] = saved;
    _samples[saved.id!] = [];
    return saved;
  }

  @override
  Future<void> update(Trip trip) async => _trips[trip.id!] = trip;

  @override
  Future<void> addSamples(int tripId, List<TripSample> samples) async =>
      _samples[tripId]!.addAll(samples);

  @override
  Future<List<Trip>> all({bool includeDemo = false}) async {
    final rows = _trips.values.where((t) => includeDemo || !t.isDemo).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return rows;
  }

  @override
  Future<Trip?> get(int id) async => _trips[id];

  @override
  Future<List<TripSample>> samples(int tripId) async =>
      List.of(_samples[tripId] ?? const []);

  @override
  Future<void> delete(int id) async {
    _trips.remove(id);
    _samples.remove(id);
  }
}
