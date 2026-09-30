// Calibration maths and the fill-up ledger (CLAUDE.md 8.5).
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/key_value_store.dart';
import 'package:tapedash/money/calibration.dart';
import 'package:tapedash/money/fill_up.dart';
import 'package:tapedash/money/fuel_ledger.dart';

void main() {
  group('Calibration', () {
    test('with nothing to go on the factor is 1 and it is uncalibrated', () {
      final c = Calibration();
      expect(c.factor, 1);
      expect(c.confidence, CalibrationConfidence.uncalibrated);
    });

    test('one factor is calibrating, two or more is calibrated', () {
      final c = Calibration()..add(1.1);
      expect(c.confidence, CalibrationConfidence.calibrating);
      c.add(1.2);
      expect(c.confidence, CalibrationConfidence.calibrated);
      c.add(1.0);
      expect(c.confidence, CalibrationConfidence.calibrated);
    });

    test('the factor is the mean of the last three', () {
      final c = Calibration([1.0, 1.1, 1.2, 1.3]);
      expect(c.factors, [1.1, 1.2, 1.3]);
      expect(c.factor, closeTo(1.2, 1e-12));
    });

    test('it is clamped to 0.7-1.3', () {
      expect(Calibration([2.0]).factor, 1.3);
      expect(Calibration([0.2]).factor, 0.7);
      expect(Calibration([1.3]).factor, 1.3);
      expect(Calibration([0.7]).factor, 0.7);
    });

    test('clear forgets every factor', () {
      final c = Calibration([0.9, 1.1]);
      c.clear();
      expect(c.factors, isEmpty);
      expect(c.factor, 1);
      expect(c.confidence, CalibrationConfidence.uncalibrated);
    });

    test('nonsense factors are ignored', () {
      final c = Calibration([double.nan, -1, 0, double.infinity]);
      expect(c.factors, isEmpty);
    });
  });

  group('FuelLedger', () {
    late MemoryFillUpRepository fills;
    late MemoryKeyValueStore store;
    late FuelLedger ledger;
    var t = DateTime(2026, 1, 1);

    DateTime next() => t = t.add(const Duration(days: 3));

    setUp(() {
      fills = MemoryFillUpRepository();
      store = MemoryKeyValueStore();
      ledger = FuelLedger(fills: fills, store: store);
      t = DateTime(2026, 1, 1);
    });

    test(
      'the first full tank only starts the count, and makes no factor',
      () async {
        ledger.addEstimate(5);
        final f = await ledger.recordFillUp(
          at: next(),
          litres: 30,
          amount: 3000,
          fullTank: true,
        );
        expect(f.factor, isNull);
        expect(ledger.estimatedSinceFull, 0);
        expect(
          ledger.calibration.confidence,
          CalibrationConfidence.uncalibrated,
        );
      },
    );

    test(
      'the second full tank works out litres filled over litres estimated',
      () async {
        await ledger.recordFillUp(
          at: next(),
          litres: 30,
          amount: 3000,
          fullTank: true,
        );
        ledger.addEstimate(24);
        final f = await ledger.recordFillUp(
          at: next(),
          litres: 30,
          amount: 3100,
          fullTank: true,
        );
        expect(f.factor, closeTo(30 / 24, 1e-12));
        expect(ledger.calibration.factor, closeTo(1.25, 1e-12));
        expect(
          ledger.calibration.confidence,
          CalibrationConfidence.calibrating,
        );
        expect(ledger.estimatedSinceFull, 0);
      },
    );

    test('a part-fill between counts as fuel used', () async {
      await ledger.recordFillUp(
        at: next(),
        litres: 30,
        amount: 3000,
        fullTank: true,
      );
      ledger.addEstimate(10);
      await ledger.recordFillUp(
        at: next(),
        litres: 5,
        amount: 500,
        fullTank: false,
      );
      ledger.addEstimate(10);
      final f = await ledger.recordFillUp(
        at: next(),
        litres: 20,
        amount: 2000,
        fullTank: true,
      );
      // 5 + 20 litres put in over 20 litres estimated.
      expect(f.factor, closeTo(25 / 20, 1e-12));
    });

    test('a part-fill alone does not reset the count', () async {
      ledger.addEstimate(7);
      await ledger.recordFillUp(
        at: next(),
        litres: 5,
        amount: 500,
        fullTank: false,
      );
      expect(ledger.estimatedSinceFull, 7);
    });

    test('too little data or an absurd ratio makes no factor', () async {
      await ledger.recordFillUp(
        at: next(),
        litres: 30,
        amount: 3000,
        fullTank: true,
      );
      ledger.addEstimate(0.5);
      var f = await ledger.recordFillUp(
        at: next(),
        litres: 30,
        amount: 3000,
        fullTank: true,
      );
      expect(f.factor, isNull);
      ledger.addEstimate(3);
      f = await ledger.recordFillUp(
        at: next(),
        litres: 30,
        amount: 3000,
        fullTank: true,
      );
      expect(f.factor, isNull, reason: '10x is the app having missed trips');
      expect(ledger.calibration.factors, isEmpty);
    });

    test('the count and the factors survive a restart', () async {
      await ledger.recordFillUp(
        at: next(),
        litres: 30,
        amount: 3000,
        fullTank: true,
      );
      ledger.addEstimate(24);
      await ledger.recordFillUp(
        at: next(),
        litres: 30,
        amount: 3000,
        fullTank: true,
      );
      ledger.addEstimate(3);
      await ledger.flush();

      final again = FuelLedger(fills: fills, store: store);
      await again.load();
      expect(again.estimatedSinceFull, 3);
      expect(again.calibration.factor, closeTo(1.25, 1e-12));
      expect(again.calibration.confidence, CalibrationConfidence.calibrating);
    });

    test('the price per litre is the amount over the litres', () {
      final f = FillUp(
        at: DateTime(2026),
        litres: 20,
        amount: 2050,
        fullTank: true,
      );
      expect(f.pricePerLitre, closeTo(102.5, 1e-12));
    });
  });
}
