import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/key_value_store.dart';
import 'package:tapedash/insights/tank_reading.dart';
import 'package:tapedash/money/fill_up.dart';
import 'package:tapedash/money/fuel_ledger.dart';
import 'package:tapedash/trips/trip.dart';

void main() {
  FuelLedger ledger() =>
      FuelLedger(fills: MemoryFillUpRepository(), store: MemoryKeyValueStore());

  Future<void> fill(FuelLedger l, int day, double litres, {bool full = true}) =>
      l.recordFillUp(
        at: DateTime(2026, 10, day),
        litres: litres,
        amount: litres * 100,
        fullTank: full,
      );

  test('there is no count until a full tank has been logged', () async {
    final l = ledger();
    expect(l.litresLeft(40), isNull);
    await fill(l, 1, 10, full: false);
    expect(l.litresLeft(40), isNull);
  });

  test('a full tank is the whole tank, and driving takes from it', () async {
    final l = ledger();
    await fill(l, 1, 38);
    expect(l.litresLeft(40), 40);
    l.addEstimate(6);
    expect(l.litresLeft(40), 34);
    expect(l.usedSinceFull, 6);
  });

  test('the calibration scales what has been used', () async {
    final l = ledger();
    await fill(l, 1, 30);
    l.addEstimate(20);
    await fill(l, 5, 22); // 22 put in for 20 estimated: a factor of 1.1
    expect(l.calibration.factor, closeTo(1.1, 1e-9));
    l.addEstimate(10);
    expect(l.litresLeft(40), closeTo(40 - 11, 1e-9));
  });

  test('a part-fill adds its litres, and a full tank starts again', () async {
    final l = ledger();
    await fill(l, 1, 30);
    l.addEstimate(25);
    await fill(l, 2, 10, full: false);
    expect(l.litresLeft(40), closeTo(40 - 25 + 10, 1e-9));
    await fill(l, 3, 20);
    expect(l.litresLeft(40), 40);
  });

  test('it never counts below empty or above full', () async {
    final l = ledger();
    await fill(l, 1, 30);
    l.addEstimate(60);
    expect(l.litresLeft(40), 0);
    await fill(l, 2, 70, full: false);
    expect(l.litresLeft(40), 40);
  });

  test('it counts again after a restart', () async {
    final fills = MemoryFillUpRepository();
    final store = MemoryKeyValueStore();
    final a = FuelLedger(fills: fills, store: store);
    await a.recordFillUp(
      at: DateTime(2026, 10, 1),
      litres: 30,
      amount: 3000,
      fullTank: true,
    );
    await a.recordFillUp(
      at: DateTime(2026, 10, 2),
      litres: 4,
      amount: 400,
      fullTank: false,
    );
    a.addEstimate(12);
    await a.flush();
    final b = FuelLedger(fills: fills, store: store);
    await b.load();
    expect(b.litresLeft(40), closeTo(40 - 12 + 4, 1e-9));
  });

  test('clearing forgets the count', () async {
    final l = ledger();
    await fill(l, 1, 30);
    await l.clear();
    expect(l.litresLeft(40), isNull);
  });

  group('TankReading', () {
    Trip trip(int day, double km, double litres, {bool demo = false}) => Trip(
      startedAt: DateTime(2026, 10, day, 12),
      distanceKm: km,
      litres: litres,
      isDemo: demo,
    );

    test('litres, range at the economy since the last full tank', () async {
      final l = ledger();
      await fill(l, 2, 30);
      l.addEstimate(24);
      final r = TankReading.of(
        ledger: l,
        tankLitres: 40,
        trips: [trip(3, 150, 10), trip(4, 130, 14), trip(1, 400, 20)],
      )!;
      expect(r.litres, 16);
      expect(r.usedLitres, 24);
      expect(r.kmSinceFull, 280);
      // 280 km on 24 L, from the trips since the fill-up, not the older 20 km/L.
      expect(r.rangeKm, closeTo(16 * 280 / 24, 1e-9));
      expect(r.level, closeTo(0.4, 1e-9));
      expect(r.inReserve, isFalse);
    });

    test(
      'with little driving since, the car\'s whole record gives the economy',
      () async {
        final l = ledger();
        await fill(l, 5, 30);
        final r = TankReading.of(
          ledger: l,
          tankLitres: 40,
          trips: [trip(2, 300, 20), trip(6, 5, 1)],
        )!;
        expect(r.rangeKm, closeTo(40 * 305 / 21, 1e-9));
      },
    );

    test(
      'no driving at all gives no range, and demo trips do not count',
      () async {
        final l = ledger();
        await fill(l, 1, 30);
        final r = TankReading.of(
          ledger: l,
          tankLitres: 40,
          trips: [trip(2, 300, 20, demo: true)],
        )!;
        expect(r.rangeKm, isNull);
      },
    );

    test('no full tank, no reading', () {
      expect(
        TankReading.of(ledger: ledger(), tankLitres: 40, trips: const []),
        isNull,
      );
    });

    test('an almost empty tank is in its reserve', () async {
      final l = ledger();
      await fill(l, 1, 30);
      l.addEstimate(36);
      expect(
        TankReading.of(ledger: l, tankLitres: 40, trips: const [])!.inReserve,
        isTrue,
      );
    });
  });
}
