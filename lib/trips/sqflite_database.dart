import 'package:sqflite/sqflite.dart';

/// The app's database (CLAUDE.md 5): trips, their samples and the fill-up log,
/// in one SQLite file on the phone. It is never synced or uploaded.
abstract final class TapeDatabase {
  static const int version = 1;

  /// The file name in the app's databases directory.
  static const String fileName = 'tapedash.db';

  /// Opens the database at [path], creating it if it is new.
  static Future<Database> open(String path, {DatabaseFactory? factory}) {
    final options = OpenDatabaseOptions(
      version: version,
      onCreate: (db, v) => _create(db),
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
    return (factory ?? databaseFactory).openDatabase(path, options: options);
  }

  static Future<void> _create(Database db) async {
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
    await db.execute('''
      CREATE TABLE trip_samples (
        trip_id INTEGER NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
        seconds REAL NOT NULL,
        speed_kmh REAL NOT NULL,
        rpm REAL NOT NULL,
        throttle REAL NOT NULL,
        litres_per_hour REAL NOT NULL,
        latitude REAL,
        longitude REAL
      )
    ''');
    await db.execute(
      'CREATE INDEX trip_samples_by_trip ON trip_samples (trip_id, seconds)',
    );
    await db.execute('''
      CREATE TABLE fill_ups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        at INTEGER NOT NULL,
        litres REAL NOT NULL,
        amount REAL NOT NULL,
        full_tank INTEGER NOT NULL,
        factor REAL
      )
    ''');
  }
}
