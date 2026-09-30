// Picking the fuel source and the estimate each gives (CLAUDE.md 8.4).
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/fuel_blend.dart';
import 'package:tapedash/fuel/fuel_constants.dart';
import 'package:tapedash/fuel/fuel_estimator.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

void main() {
  late FakeClock clock;
  late VehicleState vehicle;

  setUp(() {
    clock = FakeClock()..advance(const Duration(seconds: 100));
    vehicle = VehicleState(clock: clock, scheduler: clock);
  });

  tearDown(() => vehicle.dispose());

  void feed(Sensor sensor, double value) {
    // A reading is a new one only if it is a new time.
    clock.advance(const Duration(milliseconds: 1));
    final now = clock.monotonic();
    vehicle.ingest(sensor, value, at: now, receivedAt: now);
  }

  FuelEstimator make({VehicleSetup setup = const VehicleSetup()}) {
    final e = FuelEstimator(vehicle: vehicle, setup: setup);
    addTearDown(e.dispose);
    return e;
  }

  test('with no fuel sensor there is no source and no estimate', () {
    final e = make();
    feed(Sensor.rpm, 2000);
    feed(Sensor.speed, 50);
    expect(e.source.value, FuelSource.none);
    expect(e.flow.value, isNull);
  });

  test('PID 5E is used as it is, and wins over MAF', () {
    final e = make();
    feed(Sensor.airFlow, 10);
    feed(Sensor.fuelRate, 3.4);
    expect(e.source.value, FuelSource.fuelRate);
    expect(e.flow.value!.litresPerHour, 3.4);
    expect(e.flow.value!.lowConfidence, isFalse);
  });

  test('MAF: 10 g/s is 3.309 L/h of petrol', () {
    final e = make();
    feed(Sensor.airFlow, 10);
    expect(e.source.value, FuelSource.airFlow);
    // 10 * 3600 / (14.7 * 740) = 3.3094
    expect(e.flow.value!.litresPerHour, closeTo(3.3094, 1e-3));
  });

  test('MAF on E20: 3 g/s is 1.067 L/h, 7.5% more than the same air on E0', () {
    // 3 * 3600 / (13.50 * 749.8) = 10800 / 10122 = 1.0670; on E0 it is 0.9928.
    final e20 = make(setup: const VehicleSetup(blend: PetrolBlend.e20));
    feed(Sensor.airFlow, 3);
    expect(e20.flow.value!.litresPerHour, closeTo(1.0670, 2e-3));

    final e0 = make();
    feed(Sensor.airFlow, 3);
    expect(e0.flow.value!.litresPerHour, closeTo(0.9928, 1e-3));
    expect(
      e20.flow.value!.litresPerHour / e0.flow.value!.litresPerHour,
      closeTo(1.075, 3e-3),
    );
  });

  test('PID 5E is the ECU\'s own figure: the blend does not touch it', () {
    final e = make(setup: const VehicleSetup(blend: PetrolBlend.e20));
    feed(Sensor.fuelRate, 3.4);
    expect(e.flow.value!.litresPerHour, 3.4);
  });

  test('speed-density needs the manifold, the intake air and the revs', () {
    final e = make();
    feed(Sensor.manifoldPressure, 60);
    expect(e.source.value, FuelSource.none);
    feed(Sensor.intakeAir, 30);
    feed(Sensor.rpm, 2000);
    feed(Sensor.manifoldPressure, 60);
    expect(e.source.value, FuelSource.speedDensity);
    // 1.5 L, 2000 rpm, 60 kPa, 30 C, VE 0.85: 14.652 g/s, 4.849 L/h.
    expect(e.flow.value!.litresPerHour, closeTo(4.849, 0.01));
  });

  test('a stale better source hands over to the next', () {
    final e = make();
    feed(Sensor.fuelRate, 3);
    feed(Sensor.airFlow, 10);
    expect(e.source.value, FuelSource.fuelRate);
    // 5E goes quiet for longer than its stale time; MAF keeps coming.
    for (var i = 0; i < 8; i++) {
      clock.advance(const Duration(seconds: 1));
      feed(Sensor.airFlow, 10);
    }
    expect(e.source.value, FuelSource.airFlow);
  });

  group('fuel cut-off', () {
    test('a coasting petrol car burns nothing, by an air-based source', () {
      final e = make();
      feed(Sensor.rpm, 2500);
      feed(Sensor.speed, 60);
      feed(Sensor.throttle, 0);
      feed(Sensor.airFlow, 4);
      expect(e.flow.value!.litresPerHour, 0);
      expect(e.flow.value!.cutOff, isTrue);
    });

    test(
      'but not below 10 km/h, nor under 1500 rpm, nor with the throttle open',
      () {
        final e = make();
        feed(Sensor.rpm, 2500);
        feed(Sensor.speed, 8);
        feed(Sensor.throttle, 0);
        feed(Sensor.airFlow, 4);
        expect(e.flow.value!.litresPerHour, greaterThan(0));

        feed(Sensor.speed, 60);
        feed(Sensor.rpm, 1200);
        feed(Sensor.airFlow, 4);
        expect(e.flow.value!.cutOff, isFalse);

        feed(Sensor.rpm, 2500);
        feed(Sensor.throttle, 20);
        feed(Sensor.airFlow, 4);
        expect(e.flow.value!.cutOff, isFalse);
      },
    );

    test(
      'a closed throttle reads where this car reads it at idle (PID 11)',
      () {
        final e = make();
        // PID 11 is the absolute position: 12% with the throttle shut.
        feed(Sensor.speed, 0);
        feed(Sensor.rpm, 800);
        feed(Sensor.throttle, 12);
        expect(e.closedThrottle, 12);
        // (Time passes, or the outlier check holds the jump back.)
        clock.advance(const Duration(seconds: 10));
        feed(Sensor.speed, 60);
        feed(Sensor.rpm, 2500);
        feed(Sensor.throttle, 12.5);
        feed(Sensor.airFlow, 4);
        expect(e.flow.value!.cutOff, isTrue);
        feed(Sensor.throttle, 20);
        feed(Sensor.airFlow, 4);
        expect(e.flow.value!.cutOff, isFalse);
      },
    );

    test('5E is never overridden: the ECU knows', () {
      final e = make();
      feed(Sensor.rpm, 2500);
      feed(Sensor.speed, 60);
      feed(Sensor.throttle, 0);
      feed(Sensor.fuelRate, 0.4);
      expect(e.flow.value!.litresPerHour, 0.4);
      expect(e.flow.value!.cutOff, isFalse);
    });

    test('a car whose throttle is not read is never judged to be cutting', () {
      final e = make();
      feed(Sensor.rpm, 2500);
      feed(Sensor.speed, 60);
      feed(Sensor.airFlow, 4);
      expect(e.flow.value!.cutOff, isFalse);
      expect(e.flow.value!.litresPerHour, greaterThan(0));
    });
  });

  group('diesel', () {
    const diesel = VehicleSetup(fuelType: FuelType.diesel);

    test('air flow is used, and marked low confidence', () {
      final e = make(setup: diesel);
      feed(Sensor.airFlow, 10);
      expect(e.source.value, FuelSource.airFlow);
      expect(e.flow.value!.lowConfidence, isTrue);
      // 10 * 3600 / (24 * 832) = 1.8029
      expect(e.flow.value!.litresPerHour, closeTo(1.8029, 1e-3));
    });

    test('speed-density is not valid for a diesel', () {
      final e = make(setup: diesel);
      feed(Sensor.intakeAir, 30);
      feed(Sensor.rpm, 2000);
      feed(Sensor.manifoldPressure, 150);
      expect(e.source.value, FuelSource.none);
      expect(e.flow.value, isNull);
    });

    test('5E is used without a warning', () {
      final e = make(setup: diesel);
      feed(Sensor.fuelRate, 2);
      expect(e.flow.value!.lowConfidence, isFalse);
    });
  });

  test('the constants are per vehicle', () {
    final e = make(
      setup: const VehicleSetup(
        constants: FuelConstants(airFuelRatio: 10, densityGramsPerLitre: 800),
      ),
    );
    feed(Sensor.airFlow, 10);
    expect(e.flow.value!.litresPerHour, closeTo(10 * 3600 / (10 * 800), 1e-9));
  });

  test('a changed setup is used at once (displacement from the Garage)', () {
    final e = make();
    feed(Sensor.intakeAir, 30);
    feed(Sensor.rpm, 2000);
    feed(Sensor.manifoldPressure, 60);
    final before = e.flow.value!.litresPerHour;
    e.setup = const VehicleSetup(displacementLitres: 3);
    feed(Sensor.manifoldPressure, 60);
    expect(e.flow.value!.litresPerHour, closeTo(2 * before, 1e-6));
  });
}
