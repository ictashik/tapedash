import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/key_value_store.dart';
import 'package:tapedash/money/fill_up.dart';
import 'package:tapedash/money/fuel_ledger.dart';

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
}
