import 'package:sqflite/sqflite.dart';

import '../core/key_value_store.dart';
import '../core/observable.dart';
import '../fuel/fuel_constants.dart';
import '../money/fill_up.dart';
import '../money/fuel_ledger.dart';
import '../money/money_settings.dart';
import '../platform/shared_prefs_store.dart';
import '../trips/sqflite_database.dart';
import '../trips/sqflite_fill_up_repository.dart';
import '../trips/sqflite_trip_repository.dart';
import '../trips/trip.dart';

/// What lives as long as the app: the settings, the trip log, the fill-up log and
/// the calibration (CLAUDE.md 6), all on the phone and nowhere else.
///
/// It is separate from a drive's own services, so the same money settings and
/// trip log serve a demo drive and, later, a real one.
class AppServices {
  AppServices({
    required this.store,
    required this.trips,
    required this.fills,
    required this.money,
    required this.ledger,
    VehicleSetup setup = const VehicleSetup(),
  }) : _setup = ObservableValue(setup);

  static const _fuelTypeKey = 'vehicle_fuel_type';
  static const _displacementKey = 'vehicle_displacement_l';
  static const _tankKey = 'vehicle_tank_l';

  final KeyValueStore store;
  final TripRepository trips;
  final FillUpRepository fills;
  final MoneySettings money;
  final FuelLedger ledger;

  final ObservableValue<VehicleSetup> _setup;

  /// The car's fuel type, displacement and tank (CLAUDE.md 8.4).
  Observable<VehicleSetup> get setup => _setup;

  Future<void> setVehicleSetup(VehicleSetup setup) async {
    _setup.value = setup;
    await store.setString(_fuelTypeKey, setup.fuelType.name);
    await store.setDouble(_displacementKey, setup.displacementLitres);
    await store.setDouble(_tankKey, setup.tankLitres);
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

  Future<void> load() async {
    await money.load();
    await ledger.load();
    final type = await store.getString(_fuelTypeKey);
    _setup.value = VehicleSetup(
      fuelType: FuelType.values.firstWhere(
        (t) => t.name == type,
        orElse: () => FuelType.petrol,
      ),
      displacementLitres: await store.getDouble(_displacementKey) ?? 1.5,
      tankLitres: await store.getDouble(_tankKey) ?? 40,
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

  /// The services for Demo Mode (CLAUDE.md 7.6): the trip log is shared (demo
  /// trips are stored, flagged), but the price, the fill-ups and the calibration
  /// are the demo's own, in memory, so nothing a demo does touches the real
  /// numbers. The demo has an example price so the money screens have something
  /// to show; the DEMO badge is always on.
  factory AppServices.demo(TripRepository trips) =>
      AppServices.inMemory(price: demoPricePerLitre, trips: trips);

  /// The example price a demo drive uses, in rupees a litre.
  static const double demoPricePerLitre = 102.5;
}
