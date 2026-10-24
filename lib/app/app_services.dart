import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:sqflite/sqflite.dart';

import '../core/clock.dart';
import '../core/fuel_blend.dart';
import '../core/key_value_store.dart';
import '../core/observable.dart';
import '../fuel/fuel_constants.dart';
import '../insights/rest_voltage_log.dart';
import '../money/fill_up.dart';
import '../money/fuel_ledger.dart';
import '../money/money_settings.dart';
import '../obd/adapter_config.dart';
import '../obd/link_diary.dart';
import '../platform/shared_prefs_store.dart';
import '../trips/sqflite_database.dart';
import '../trips/sqflite_fill_up_repository.dart';
import '../trips/sqflite_trip_repository.dart';
import '../trips/trip.dart';
import 'app_settings.dart';

/// What lives as long as the app: the settings, the trip log, the fill-up log and
/// the calibration (CLAUDE.md 6), all on the phone and nowhere else.
///
/// It is separate from a drive's own services, so the same money settings and
/// trip log serve whichever drive is on.
class AppServices {
  AppServices({
    required this.store,
    required this.trips,
    required this.fills,
    required this.money,
    required this.ledger,
    VehicleSetup setup = const VehicleSetup(),
    this.recordByDefault = false,
    this.clock = const SystemClock(),
  }) : _setup = ObservableValue(setup);

  /// The time of the readings the app keeps; the real clock outside a test.
  final Clock clock;

  /// Whether adapter sessions are recorded until Garage says otherwise (see
  /// `AdapterStore.recordByDefault`).
  final bool recordByDefault;

  static const _fuelTypeKey = 'vehicle_fuel_type';
  static const _displacementKey = 'vehicle_displacement_l';
  static const _tankKey = 'vehicle_tank_l';
  static const _blendKey = 'vehicle_petrol_blend';
  static const _installKey = 'install_id';

  /// A short random id for this install (docs/EXCHANGE.md 1), made the first time
  /// and kept, so that two files from one device say so. It identifies nothing
  /// else and leaves the device only inside a file the person exports.
  String installId = 'local';

  final KeyValueStore store;
  final TripRepository trips;
  final FillUpRepository fills;
  final MoneySettings money;
  final FuelLedger ledger;

  final ObservableValue<VehicleSetup> _setup;

  /// The look, the HUD, the coach and the engine sound: what the user sets in Garage
  /// (`AppSettings`), saved to [store] as it changes.
  late final AppSettings settings = AppSettings(store);

  /// The battery's resting voltage, a reading a day at most (Insights, Current).
  late final RestVoltageLog restVoltage = RestVoltageLog(
    store: store,
    clock: clock,
  );

  /// What the app has done to reach the adapter, for Garage's connection log.
  late final LinkDiary linkDiary = LinkDiary(clock: clock);

  /// The adapter the user chose, and how it is used (`AdapterStore`).
  late final AdapterStore adapters = AdapterStore(
    store,
    recordByDefault: recordByDefault,
  );

  /// The car's fuel type, displacement and tank (CLAUDE.md 8.4).
  Observable<VehicleSetup> get setup => _setup;

  Future<void> setVehicleSetup(VehicleSetup setup) async {
    _setup.value = setup;
    await store.setString(_fuelTypeKey, setup.fuelType.name);
    await store.setDouble(_displacementKey, setup.displacementLitres);
    await store.setDouble(_tankKey, setup.tankLitres);
    await store.setString(_blendKey, setup.blend.name);
  }

  /// Logs a fill-up, works out a calibration factor from it if it can, and makes
  /// its price per litre the current price (CLAUDE.md 8.5).
  Future<FillUp> saveFillUp({
    required DateTime at,
    required double litres,
    required double amount,
    required bool fullTank,
  }) async {
    final fill = await ledger.recordFillUp(
      at: at,
      litres: litres,
      amount: amount,
      fullTank: fullTank,
    );
    await money.setPrice(amount / litres);
    return fill;
  }

  /// Deletes what the app has recorded (Garage → Data): every trip, the simulated ones
  /// that older builds left behind included, every fill-up and the calibration, and the fuel price. The car's
  /// setup and the settings stay.
  Future<void> deleteAllData() async {
    for (final t in await trips.all(includeDemo: true)) {
      await trips.delete(t.id!);
    }
    await ledger.clear();
    await restVoltage.clear();
    await money.setPrice(null);
  }

  Future<void> load() async {
    var id = await store.getString(_installKey);
    if (id == null || id.isEmpty) {
      final random = math.Random.secure();
      id = [
        for (var i = 0; i < 4; i++)
          random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ].join();
      await store.setString(_installKey, id);
    }
    installId = id;
    await settings.load();
    await adapters.load();
    await money.load();
    await ledger.load();
    await restVoltage.load();
    final type = await store.getString(_fuelTypeKey);
    final blend = await store.getString(_blendKey);
    _setup.value = VehicleSetup(
      fuelType: FuelType.values.firstWhere(
        (t) => t.name == type,
        orElse: () => FuelType.petrol,
      ),
      displacementLitres: await store.getDouble(_displacementKey) ?? 1.5,
      tankLitres: await store.getDouble(_tankKey) ?? 40,
      // No blend saved (a new install, or one from before the setting): E20,
      // which is what the pumps sell.
      blend: PetrolBlend.values.firstWhere(
        (b) => b.name == blend,
        orElse: () => VehicleSetup.indiaDefault.blend,
      ),
    );
  }

  /// The real services: SQLite and `shared_preferences` on the phone.
  static Future<AppServices> open() async {
    final path = '${await getDatabasesPath()}/${TapeDatabase.fileName}';
    final db = await TapeDatabase.open(path);
    final store = SharedPrefsStore.instance();
    final fills = SqfliteFillUpRepository(db);
    final services = AppServices(
      store: store,
      trips: SqfliteTripRepository(db),
      fills: fills,
      money: MoneySettings(store),
      ledger: FuelLedger(fills: fills, store: store),
      // A debug or profile build is for finding things out: record the drives.
      recordByDefault: !kReleaseMode,
    );
    await services.load();
    return services;
  }

  /// In-memory services, for tests: everything empty, and usable at once.
  factory AppServices.inMemory({double? price, TripRepository? trips}) {
    final store = MemoryKeyValueStore();
    final fills = MemoryFillUpRepository();
    final services = AppServices(
      store: store,
      trips: trips ?? MemoryTripRepository(),
      fills: fills,
      money: MoneySettings(store),
      ledger: FuelLedger(fills: fills, store: store),
    );
    // Setting a price on an empty store completes before its first await.
    if (price != null) services.money.setPrice(price);
    return services;
  }

  /// [AppServices.inMemory], loaded.
  static Future<AppServices> memory({double? price}) async {
    final services = AppServices.inMemory(price: price);
    await services.load();
    return services;
  }
}
