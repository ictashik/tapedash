// The trip and fill-up repositories: the in-memory ones and the SQLite ones
// (on the FFI SQLite, headless) meet the same contract.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tapedash/fuel/fuel_estimator.dart';
import 'package:tapedash/money/fill_up.dart';
import 'package:tapedash/money/spend_bucket.dart';
import 'package:tapedash/trips/sqflite_database.dart';
import 'package:tapedash/trips/sqflite_fill_up_repository.dart';
import 'package:tapedash/trips/sqflite_trip_repository.dart';
import 'package:tapedash/trips/trip.dart';

Trip sample({DateTime? at, bool demo = false}) => Trip(
  startedAt: at ?? DateTime(2026, 3, 1, 8),
  isDemo: demo,
  distanceKm: 12.5,
  litres: 1.02,
  uncalibratedLitres: 0.95,
  cost: 104.5,
  pricePerLitre: 102.5,
  idleSeconds: 90,
  engineSeconds: 1500,
  bucketLitres: {
    SpendBucket.normal: 0.6,
    SpendBucket.idling: 0.2,
    SpendBucket.hardAcceleration: 0.15,
    SpendBucket.highSpeed: 0.07,
  },
  blockBuckets: [
    SpendBucket.normal,
    SpendBucket.idling,
    SpendBucket.hardAcceleration,
  ],
  fuelSource: FuelSource.airFlow,
  lowConfidence: true,
  calibrationFactor: 1.07,
  hardAccelerations: 2,
  hardBrakings: 1,
  longIdles: 2,
  longestIdleSeconds: 140,
  highRpmSeconds: 33.5,
  speedingSeconds: 21,
);

void tripContract(String name, Future<TripRepository> Function() make) {
  group('$name trips', () {
    late TripRepository repo;
    setUp(() async => repo = await make());

    test('createWithSamples saves a trip and its samples together', () async {
      final saved = await repo.createWithSamples(
        sample().copyWith(endedAt: DateTime(2026, 3, 1, 9)),
        const [
          TripSample(
            seconds: 0,
            speedKmh: 0,
            rpm: 800,
            throttle: 0,
            litresPerHour: 0.7,
          ),
          TripSample(
            seconds: 1,
            speedKmh: 4,
            rpm: 1100,
            throttle: 12,
            litresPerHour: 1.4,
            latitude: 12.97,
            longitude: 77.59,
            load: 30,
            coolantC: 48,
            voltage: 14.1,
          ),
        ],
      );
      expect(saved.id, isNotNull);
      expect((await repo.get(saved.id!))!.endedAt, DateTime(2026, 3, 1, 9));
      final samples = await repo.samples(saved.id!);
      expect(samples.map((s) => s.rpm), [800, 1100]);
      expect(samples.last.voltage, 14.1);
      expect(samples.first.latitude, isNull);
    });

    test('create gives an id, and get returns what was saved', () async {
      final saved = await repo.create(sample());
      expect(saved.id, isNotNull);
      final read = (await repo.get(saved.id!))!;
      expect(read.distanceKm, 12.5);
      expect(read.litres, 1.02);
      expect(read.uncalibratedLitres, 0.95);
      expect(read.cost, 104.5);
      expect(read.pricePerLitre, 102.5);
      expect(read.idleSeconds, 90);
      expect(read.engineSeconds, 1500);
      expect(read.bucketLitres[SpendBucket.idling], closeTo(0.2, 1e-12));
      expect(read.blockBuckets, [
        SpendBucket.normal,
        SpendBucket.idling,
        SpendBucket.hardAcceleration,
      ]);
      expect(read.fuelSource, FuelSource.airFlow);
      expect(read.lowConfidence, isTrue);
      expect(read.calibrationFactor, 1.07);
      expect(read.hardAccelerations, 2);
      expect(read.hardBrakings, 1);
      expect(read.longIdles, 2);
      expect(read.longestIdleSeconds, 140);
      expect(read.highRpmSeconds, 33.5);
      expect(read.speedingSeconds, 21);
      expect(read.isOpen, isTrue);
      expect(read.startedAt, DateTime(2026, 3, 1, 8));
    });

    test('a trip with no price and no blocks round-trips', () async {
      final saved = await repo.create(Trip(startedAt: DateTime(2026, 3, 1)));
      final read = (await repo.get(saved.id!))!;
      expect(read.cost, isNull);
      expect(read.pricePerLitre, isNull);
      expect(read.blockBuckets, isEmpty);
      expect(read.endedAt, isNull);
    });

    test('update changes it, and closing it sets the end', () async {
      final saved = await repo.create(sample());
      await repo.update(
        saved.copyWith(distanceKm: 20, endedAt: DateTime(2026, 3, 1, 9)),
      );
      final read = (await repo.get(saved.id!))!;
      expect(read.distanceKm, 20);
      expect(read.endedAt, DateTime(2026, 3, 1, 9));
      expect(read.isOpen, isFalse);
      // And it can be reopened (a trip resumed).
      await repo.update(read.copyWith(endedAt: null));
      expect((await repo.get(saved.id!))!.isOpen, isTrue);
    });

    test(
      'all is newest first, and leaves demo trips out unless asked',
      () async {
        await repo.create(sample(at: DateTime(2026, 3, 1)));
        await repo.create(sample(at: DateTime(2026, 3, 3)));
        await repo.create(sample(at: DateTime(2026, 3, 2), demo: true));
        final real = await repo.all();
        expect([for (final t in real) t.startedAt.day], [3, 1]);
        final everything = await repo.all(includeDemo: true);
        expect([for (final t in everything) t.startedAt.day], [3, 2, 1]);
        expect(
          everything.firstWhere((t) => t.startedAt.day == 2).isDemo,
          isTrue,
        );
      },
    );

    test('samples are kept in order, with and without a position', () async {
      final saved = await repo.create(sample());
      await repo.addSamples(saved.id!, [
        const TripSample(
          seconds: 0,
          speedKmh: 0,
          rpm: 800,
          throttle: 10,
          litresPerHour: 0.8,
        ),
        const TripSample(
          seconds: 1,
          speedKmh: 12,
          rpm: 1500,
          throttle: 25,
          litresPerHour: 2.5,
          latitude: 12.97,
          longitude: 77.59,
        ),
      ]);
      await repo.addSamples(saved.id!, [
        const TripSample(
          seconds: 2,
          speedKmh: 20,
          rpm: 2000,
          throttle: 30,
          litresPerHour: 3,
        ),
      ]);
      final samples = await repo.samples(saved.id!);
      expect(samples.length, 3);
      expect([for (final s in samples) s.seconds], [0, 1, 2]);
      expect(samples[0].latitude, isNull);
      expect(samples[1].latitude, 12.97);
      expect(samples[1].longitude, 77.59);
      expect(samples[2].speedKmh, 20);
    });

    test(
      'samples keep the load, the coolant and the voltage when there are some',
      () async {
        final saved = await repo.create(sample());
        await repo.addSamples(saved.id!, [
          const TripSample(
            seconds: 0,
            speedKmh: 30,
            rpm: 1800,
            throttle: 20,
            litresPerHour: 1.5,
            load: 42.5,
            coolantC: 88,
            voltage: 14.1,
          ),
          const TripSample(
            seconds: 1,
            speedKmh: 31,
            rpm: 1850,
            throttle: 21,
            litresPerHour: 1.6,
          ),
        ]);

        final samples = await repo.samples(saved.id!);

        expect(samples[0].load, 42.5);
        expect(samples[0].coolantC, 88);
        expect(samples[0].voltage, 14.1);
        expect(samples[1].load, isNull, reason: 'a car that does not say');
        expect(samples[1].coolantC, isNull);
        expect(samples[1].voltage, isNull);
      },
    );

    test('delete removes the trip and its samples', () async {
      final saved = await repo.create(sample());
      await repo.addSamples(saved.id!, [
        const TripSample(
          seconds: 0,
          speedKmh: 0,
          rpm: 800,
          throttle: 10,
          litresPerHour: 0.8,
        ),
      ]);
      await repo.delete(saved.id!);
      expect(await repo.get(saved.id!), isNull);
      expect(await repo.samples(saved.id!), isEmpty);
    });
  });
}

void fillUpContract(String name, Future<FillUpRepository> Function() make) {
  group('$name fill-ups', () {
    late FillUpRepository repo;
    setUp(() async => repo = await make());

    test('are kept oldest first, with their factor', () async {
      await repo.add(
        FillUp(
          at: DateTime(2026, 3, 5),
          litres: 20,
          amount: 2050,
          fullTank: true,
          factor: 1.08,
        ),
      );
      await repo.add(
        FillUp(
          at: DateTime(2026, 3, 1),
          litres: 30,
          amount: 3000,
          fullTank: false,
        ),
      );
      final all = await repo.all();
      expect([for (final f in all) f.at.day], [1, 5]);
      expect(all[0].fullTank, isFalse);
      expect(all[0].factor, isNull);
      expect(all[1].fullTank, isTrue);
      expect(all[1].factor, 1.08);
      expect(all[1].pricePerLitre, closeTo(102.5, 1e-9));
      expect(all[0].id, isNotNull);
    });

    test('delete removes one', () async {
      final a = await repo.add(
        FillUp(
          at: DateTime(2026, 3, 1),
          litres: 30,
          amount: 3000,
          fullTank: true,
        ),
      );
      await repo.add(
        FillUp(
          at: DateTime(2026, 3, 2),
          litres: 30,
          amount: 3000,
          fullTank: true,
        ),
      );
      await repo.delete(a.id!);
      expect((await repo.all()).length, 1);
    });
  });
}

void main() {
  sqfliteFfiInit();

  tripContract('memory', () async => MemoryTripRepository());
  fillUpContract('memory', () async => MemoryFillUpRepository());

  tripContract('sqflite', () async {
    final db = await TapeDatabase.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);
    return SqfliteTripRepository(db);
  });
  fillUpContract('sqflite', () async {
    final db = await TapeDatabase.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);
    return SqfliteFillUpRepository(db);
  });

  test('the sqflite database survives being reopened', () async {
    final dir = Directory.systemTemp.createTempSync('tapedash_db_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/t.db';
    var db = await TapeDatabase.open(path, factory: databaseFactoryFfi);
    final saved = await SqfliteTripRepository(db).create(sample());
    await db.close();
    db = await TapeDatabase.open(path, factory: databaseFactoryFfi);
    addTearDown(db.close);
    expect((await SqfliteTripRepository(db).get(saved.id!))!.distanceKm, 12.5);
  });

  test('a version 1 database is upgraded, keeping its trips', () async {
    final dir = Directory.systemTemp.createTempSync('tapedash_db_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/old.db';
    // The schema as it was in version 1 (before the coach's counts).
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, v) async {
          await db.execute('''
            CREATE TABLE trips (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              started_at INTEGER NOT NULL,
              ended_at INTEGER,
              is_demo INTEGER NOT NULL DEFAULT 0,
              distance_km REAL NOT NULL DEFAULT 0,
              litres REAL NOT NULL DEFAULT 0,
              uncalibrated_litres REAL NOT NULL DEFAULT 0,
              cost REAL,
              price_per_litre REAL,
              idle_seconds REAL NOT NULL DEFAULT 0,
              engine_seconds REAL NOT NULL DEFAULT 0,
              bucket_litres TEXT NOT NULL DEFAULT '',
              block_buckets TEXT NOT NULL DEFAULT '',
              fuel_source INTEGER NOT NULL DEFAULT 3,
              low_confidence INTEGER NOT NULL DEFAULT 0,
              calibration_factor REAL NOT NULL DEFAULT 1,
              hard_accelerations INTEGER NOT NULL DEFAULT 0,
              hard_brakings INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute(
            'CREATE TABLE trip_samples (trip_id INTEGER NOT NULL, seconds REAL NOT NULL, speed_kmh REAL NOT NULL, rpm REAL NOT NULL, throttle REAL NOT NULL, litres_per_hour REAL NOT NULL, latitude REAL, longitude REAL)',
          );
          await db.execute(
            'CREATE TABLE fill_ups (id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER NOT NULL, litres REAL NOT NULL, amount REAL NOT NULL, full_tank INTEGER NOT NULL, factor REAL)',
          );
        },
      ),
    );
    await old.insert('trips', {
      'started_at': DateTime(2026, 3, 1).millisecondsSinceEpoch,
      'distance_km': 42.0,
      'hard_accelerations': 3,
    });
    await old.insert('trip_samples', {
      'trip_id': 1,
      'seconds': 0.0,
      'speed_kmh': 20.0,
      'rpm': 1500.0,
      'throttle': 12.0,
      'litres_per_hour': 1.1,
    });
    await old.close();

    final db = await TapeDatabase.open(path, factory: databaseFactoryFfi);
    addTearDown(db.close);
    final trips = await SqfliteTripRepository(db).all();
    expect(trips.single.distanceKm, 42);
    expect(trips.single.hardAccelerations, 3);
    expect(trips.single.longIdles, 0);
    expect(trips.single.highRpmSeconds, 0);
    // And it takes the new columns.
    await SqfliteTripRepository(db).update(trips.single.copyWith(longIdles: 4));
    expect((await SqfliteTripRepository(db).all()).single.longIdles, 4);

    // The sample from before the channels: still there, with none of them, and
    // new samples take them.
    final repo = SqfliteTripRepository(db);
    final before = await repo.samples(1);
    expect(before.single.speedKmh, 20);
    expect(before.single.load, isNull);
    await repo.addSamples(1, [
      const TripSample(
        seconds: 1,
        speedKmh: 22,
        rpm: 1600,
        throttle: 14,
        litresPerHour: 1.2,
        load: 33,
        coolantC: 70,
        voltage: 13.9,
      ),
    ]);
    final after = await repo.samples(1);
    expect(after.last.coolantC, 70);
  });
}
