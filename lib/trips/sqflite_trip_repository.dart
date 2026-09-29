import 'package:sqflite/sqflite.dart';

import '../fuel/fuel_estimator.dart';
import '../money/spend_bucket.dart';
import 'trip.dart';

/// The trip log in SQLite (CLAUDE.md 6). The behaviour is that of
/// [MemoryTripRepository], which the tests share.
class SqfliteTripRepository implements TripRepository {
  SqfliteTripRepository(this._db);

  final Database _db;

  @override
  Future<Trip> create(Trip trip) async {
    final id = await _db.insert('trips', _toRow(trip));
    return trip.copyWith(id: id);
  }

  @override
  Future<void> update(Trip trip) async {
    await _db.update(
      'trips',
      _toRow(trip),
      where: 'id = ?',
      whereArgs: [trip.id],
    );
  }

  @override
  Future<void> addSamples(int tripId, List<TripSample> samples) async {
    final batch = _db.batch();
    for (final s in samples) {
      batch.insert('trip_samples', {
        'trip_id': tripId,
        'seconds': s.seconds,
        'speed_kmh': s.speedKmh,
        'rpm': s.rpm,
        'throttle': s.throttle,
        'litres_per_hour': s.litresPerHour,
        'latitude': s.latitude,
        'longitude': s.longitude,
      });
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<List<Trip>> all({bool includeDemo = false}) async {
    final rows = await _db.query(
      'trips',
      where: includeDemo ? null : 'is_demo = 0',
      orderBy: 'started_at DESC',
    );
    return [for (final r in rows) _fromRow(r)];
  }

  @override
  Future<Trip?> get(int id) async {
    final rows = await _db.query('trips', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<List<TripSample>> samples(int tripId) async {
    final rows = await _db.query(
      'trip_samples',
      where: 'trip_id = ?',
      whereArgs: [tripId],
      orderBy: 'seconds ASC',
    );
    return [
      for (final r in rows)
        TripSample(
          seconds: (r['seconds']! as num).toDouble(),
          speedKmh: (r['speed_kmh']! as num).toDouble(),
          rpm: (r['rpm']! as num).toDouble(),
          throttle: (r['throttle']! as num).toDouble(),
          litresPerHour: (r['litres_per_hour']! as num).toDouble(),
          latitude: (r['latitude'] as num?)?.toDouble(),
          longitude: (r['longitude'] as num?)?.toDouble(),
        ),
    ];
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete('trip_samples', where: 'trip_id = ?', whereArgs: [id]);
    await _db.delete('trips', where: 'id = ?', whereArgs: [id]);
  }

  static Map<String, Object?> _toRow(Trip t) => {
    'started_at': t.startedAt.millisecondsSinceEpoch,
    'ended_at': t.endedAt?.millisecondsSinceEpoch,
    'is_demo': t.isDemo ? 1 : 0,
    'distance_km': t.distanceKm,
    'litres': t.litres,
    'uncalibrated_litres': t.uncalibratedLitres,
    'cost': t.cost,
    'price_per_litre': t.pricePerLitre,
    'idle_seconds': t.idleSeconds,
    'engine_seconds': t.engineSeconds,
    'bucket_litres': [
      for (final b in SpendBucket.values) t.bucketLitres[b] ?? 0,
    ].join(','),
    'block_buckets': [for (final b in t.blockBuckets) b.index].join(','),
    'fuel_source': t.fuelSource.index,
    'low_confidence': t.lowConfidence ? 1 : 0,
    'calibration_factor': t.calibrationFactor,
    'hard_accelerations': t.hardAccelerations,
    'hard_brakings': t.hardBrakings,
    'long_idles': t.longIdles,
    'longest_idle_seconds': t.longestIdleSeconds,
    'high_rpm_seconds': t.highRpmSeconds,
    'speeding_seconds': t.speedingSeconds,
  };

  static Trip _fromRow(Map<String, Object?> r) {
    final buckets = (r['bucket_litres']! as String).split(',');
    final blocks = (r['block_buckets']! as String);
    return Trip(
      id: r['id']! as int,
      startedAt: DateTime.fromMillisecondsSinceEpoch(r['started_at']! as int),
      endedAt: r['ended_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(r['ended_at']! as int),
      isDemo: r['is_demo'] == 1,
      distanceKm: (r['distance_km']! as num).toDouble(),
      litres: (r['litres']! as num).toDouble(),
      uncalibratedLitres: (r['uncalibrated_litres']! as num).toDouble(),
      cost: (r['cost'] as num?)?.toDouble(),
      pricePerLitre: (r['price_per_litre'] as num?)?.toDouble(),
      idleSeconds: (r['idle_seconds']! as num).toDouble(),
      engineSeconds: (r['engine_seconds']! as num).toDouble(),
      bucketLitres: {
        for (var i = 0; i < SpendBucket.values.length; i++)
          SpendBucket.values[i]: i < buckets.length
              ? double.tryParse(buckets[i]) ?? 0
              : 0,
      },
      blockBuckets: blocks.isEmpty
          ? const []
          : [
              for (final s in blocks.split(','))
                SpendBucket.values[int.parse(s)],
            ],
      fuelSource: FuelSource.values[r['fuel_source']! as int],
      lowConfidence: r['low_confidence'] == 1,
      calibrationFactor: (r['calibration_factor']! as num).toDouble(),
      hardAccelerations: r['hard_accelerations']! as int,
      hardBrakings: r['hard_brakings']! as int,
      longIdles: r['long_idles']! as int,
      longestIdleSeconds: (r['longest_idle_seconds']! as num).toDouble(),
      highRpmSeconds: (r['high_rpm_seconds']! as num).toDouble(),
      speedingSeconds: (r['speeding_seconds']! as num).toDouble(),
    );
  }
}
