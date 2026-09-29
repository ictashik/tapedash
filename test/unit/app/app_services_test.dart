import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/fuel/fuel_constants.dart';
import 'package:tapedash/money/calibration.dart';

void main() {
  test('a fill-up sets the price to the amount over the litres', () async {
    final app = await AppServices.memory();
    expect(app.money.price.value, isNull);
    await app.saveFillUp(
      at: DateTime(2026, 3, 1),
      litres: 20,
      amount: 2050,
      fullTank: true,
    );
    expect(app.money.price.value, closeTo(102.5, 1e-9));
    expect((await app.fills.all()).single.litres, 20);
  });

  test('two full tanks make a calibration', () async {
    final app = await AppServices.memory();
    await app.saveFillUp(
      at: DateTime(2026, 3, 1),
      litres: 30,
      amount: 3000,
      fullTank: true,
    );
    app.ledger.addEstimate(25);
    await app.saveFillUp(
      at: DateTime(2026, 3, 5),
      litres: 30,
      amount: 3090,
      fullTank: true,
    );
    expect(app.ledger.confidence.value, CalibrationConfidence.calibrating);
    expect(app.ledger.calibration.factor, closeTo(1.2, 1e-9));
    expect(app.money.price.value, closeTo(103, 1e-9));
  });

  test('the vehicle setup is kept and read back', () async {
    final app = await AppServices.memory();
    expect(app.setup.value.displacementLitres, 1.5);
    await app.setVehicleSetup(
      const VehicleSetup(
        fuelType: FuelType.diesel,
        displacementLitres: 2.2,
        tankLitres: 55,
      ),
    );
    await app.load();
    expect(app.setup.value.fuelType, FuelType.diesel);
    expect(app.setup.value.displacementLitres, 2.2);
    expect(app.setup.value.tankLitres, 55);
  });

  test(
    'a demo has its own price and calibration, and shares only the trips',
    () async {
      final real = await AppServices.memory(price: 100);
      final demo = AppServices.demo(real.trips);
      expect(demo.money.price.value, AppServices.demoPricePerLitre);
      expect(demo.trips, same(real.trips));
      await demo.saveFillUp(
        at: DateTime(2026, 3, 1),
        litres: 10,
        amount: 1000,
        fullTank: true,
      );
      expect(real.money.price.value, 100);
      expect(await real.fills.all(), isEmpty);
    },
  );
}
