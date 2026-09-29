// The live trip computer (CLAUDE.md 8.6, 8.7): distance, fuel, cost, idling and
// the buckets, on hand-made sensor streams so that every number can be worked
// out on paper.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/coach/hard_event_detector.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/fuel/fuel_constants.dart';
import 'package:tapedash/fuel/fuel_estimator.dart';
import 'package:tapedash/money/spend_bucket.dart';
import 'package:tapedash/money/trip_computer.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

class Rig {
  Rig({double? price = 100, this.factor = 1}) {
    clock = FakeClock()..advance(const Duration(seconds: 100));
    vehicle = VehicleState(clock: clock, scheduler: clock);
    estimator = FuelEstimator(vehicle: vehicle, setup: const VehicleSetup());
    hard = HardEventDetector(vehicle: vehicle);
    this.price = ObservableValue<double?>(price);
    trip = TripComputer(
      vehicle: vehicle,
      estimator: estimator,
      hardEvents: hard,
      calibrationFactor: () => factor,
      price: this.price,
    );
  }

  late final FakeClock clock;
  late final VehicleState vehicle;
  late final FuelEstimator estimator;
  late final HardEventDetector hard;
  late final ObservableValue<double?> price;
  late final TripComputer trip;
  double factor;

  void feed(Sensor s, double v) {
    final now = clock.monotonic();
    vehicle.ingest(s, v, at: now, receivedAt: now);
  }

  /// Drives [seconds] of sensor stream: speed every 200 ms, the rest every
  /// second, [speed], [maf] and [throttle] as functions of the time in the
  /// stretch.
  void drive(
    int seconds, {
    required double Function(double t) speed,
    double Function(double t)? maf,
    double Function(double t)? throttle,
    double rpm = 1800,
  }) {
    for (var i = 0; i < seconds * 5; i++) {
      final t = i * 0.2;
      clock.advance(const Duration(milliseconds: 200));
      feed(Sensor.speed, speed(t).roundToDouble());
      if (i % 5 == 0) {
        feed(Sensor.rpm, rpm);
        feed(Sensor.throttle, throttle?.call(t) ?? 20);
        feed(Sensor.airFlow, maf?.call(t) ?? 5);
      }
    }
  }

  void close() {
    trip.dispose();
    hard.dispose();
    estimator.dispose();
    vehicle.dispose();
  }
}

/// 5 g/s of air at 14.7:1 and 740 g/L: litres an hour.
const lphAt5 = 5 * 3600 / (14.7 * 740);

void main() {
  late Rig rig;

  Rig make({double? price = 100, double factor = 1}) {
    rig = Rig(price: price, factor: factor);
    addTearDown(rig.close);
    return rig;
  }

  group('distance', () {
    test('60 km/h for a minute is a kilometre', () {
      make().drive(60, speed: (_) => 60);
      expect(rig.trip.distanceKm.value, closeTo(1.0, 0.01));
    });

    test('speeding up from 0 to 60 over a minute is half a kilometre', () {
      make().drive(60, speed: (t) => t);
      expect(rig.trip.distanceKm.value, closeTo(0.5, 0.01));
    });

    test('a stretch with no speed readings is not counted', () {
      make().drive(10, speed: (_) => 60);
      final before = rig.trip.distanceKm.value;
      rig.clock.advance(const Duration(seconds: 60));
      rig.feed(Sensor.speed, 60);
      expect(rig.trip.distanceKm.value, before);
    });
  });

  group('fuel and cost', () {
    test('5 g/s for a minute burns 1.6547 L/h * 60 s', () {
      make().drive(60, speed: (_) => 60);
      // The first estimate opens the stretch: 59 seconds are counted.
      expect(rig.trip.litres.value, closeTo(lphAt5 * 59 / 3600, 0.0005));
    });

    test('cost is litres times the price; ₹/km and km/L follow', () {
      make(price: 100).drive(120, speed: (_) => 60);
      final litres = rig.trip.litres.value;
      expect(rig.trip.cost.value, closeTo(litres * 100, 1e-9));
      final km = rig.trip.distanceKm.value;
      expect(rig.trip.costPerKm.value, closeTo(litres * 100 / km, 1e-9));
      expect(rig.trip.kmPerLitre.value, closeTo(km / litres, 1e-9));
    });

    test('the calibration factor scales the fuel, and the cost with it', () {
      make(price: 100, factor: 1.2).drive(120, speed: (_) => 60);
      expect(
        rig.trip.litres.value,
        closeTo(rig.trip.uncalibratedLitres * 1.2, 1e-9),
      );
    });

    test('with no price there is fuel and no cost', () {
      make(price: null).drive(60, speed: (_) => 60);
      expect(rig.trip.litres.value, greaterThan(0));
      expect(rig.trip.cost.value, isNull);
      expect(rig.trip.costPerKm.value, isNull);
      expect(rig.trip.blocks, isEmpty);
    });

    test('a gap in the estimates longer than 30 s burns nothing, no spike', () {
      make().drive(20, speed: (_) => 60);
      final before = rig.trip.litres.value;
      rig.clock.advance(const Duration(seconds: 45));
      rig.drive(1, speed: (_) => 60, maf: (_) => 40);
      // Only the estimates after the gap add, and not the 45 s in it.
      expect(rig.trip.litres.value - before, lessThan(0.005));
    });

    test('a short gap is filled with the average of the two sides', () {
      make().drive(10, speed: (_) => 60, maf: (_) => 4);
      final before = rig.trip.litres.value;
      rig.clock.advance(const Duration(seconds: 9));
      rig.feed(Sensor.airFlow, 8);
      final added = rig.trip.litres.value - before;
      final lph4 = 4 * 3600 / (14.7 * 740);
      final lph8 = 8 * 3600 / (14.7 * 740);
      // 10 s stretch from the last estimate at 4 g/s to this one at 8.
      expect(added, closeTo((lph4 + lph8) / 2 * 10 / 3600, 0.001));
    });
  });

  group('idling', () {
    test(
      '30 s stopped with the engine on is 30 s idle, in the idle bucket',
      () {
        make().drive(
          30,
          speed: (_) => 0,
          maf: (_) => 2,
          rpm: 800,
          throttle: (_) => 10,
        );
        expect(rig.trip.idleSeconds.value, closeTo(30, 0.5));
        final idle = rig.trip.bucketLitres[SpendBucket.idling]!;
        expect(idle, closeTo(rig.trip.litres.value, 1e-9));
        expect(rig.trip.idleCost.value, closeTo(idle * 100, 1e-9));
      },
    );

    test('driving is not idling', () {
      make().drive(30, speed: (_) => 40);
      expect(rig.trip.idleSeconds.value, 0);
      expect(rig.trip.bucketLitres[SpendBucket.idling], 0);
    });

    test('below 2 km/h is idling; at 2 it is not', () {
      make().drive(10, speed: (_) => 1, rpm: 800, throttle: (_) => 10);
      final idling = rig.trip.bucketLitres[SpendBucket.idling]!;
      expect(idling, greaterThan(0));
      rig.drive(10, speed: (_) => 2);
      expect(rig.trip.bucketLitres[SpendBucket.normal]!, greaterThan(0));
    });
  });

  group('attribution: every sample in exactly one bucket', () {
    test('idle, cruising and high speed add up to the whole', () {
      make()
        ..drive(20, speed: (_) => 0, rpm: 800, throttle: (_) => 10)
        ..drive(30, speed: (_) => 60)
        ..drive(30, speed: (_) => 120, maf: (_) => 12);
      rig.trip.finish();
      final sum = rig.trip.bucketLitres.values.fold<double>(0, (a, b) => a + b);
      expect(
        sum + rig.trip.pendingLitres,
        closeTo(rig.trip.litres.value, 1e-9),
      );
      expect(rig.trip.bucketLitres[SpendBucket.idling]!, greaterThan(0));
      expect(rig.trip.bucketLitres[SpendBucket.normal]!, greaterThan(0));
      expect(rig.trip.bucketLitres[SpendBucket.highSpeed]!, greaterThan(0));
      // (The steps between the stretches are themselves violent accelerations, so
      // the hard bucket may hold some: what matters is that nothing is lost.)
    });

    test('the high-speed bucket starts above the threshold, not at it', () {
      make().drive(20, speed: (_) => 100);
      expect(rig.trip.bucketLitres[SpendBucket.highSpeed], 0);
      rig.drive(20, speed: (_) => 101);
      expect(rig.trip.bucketLitres[SpendBucket.highSpeed]!, greaterThan(0));
    });

    test('a hard acceleration takes its fuel, including its first seconds', () {
      make()
        ..drive(20, speed: (_) => 40)
        // 40 to 90 km/h in 5 s: 2.8 m/s2 for the whole stretch, throttle open.
        ..drive(
          5,
          speed: (t) => 40 + 10 * t,
          maf: (_) => 20,
          throttle: (_) => 90,
        )
        ..drive(20, speed: (_) => 90);
      rig.trip.finish();
      expect(
        rig.hard.events.where((e) => e.type == HardEventType.hardAcceleration),
        isNotEmpty,
      );
      final hardL = rig.trip.bucketLitres[SpendBucket.hardAcceleration]!;
      // About five seconds at 20 g/s of air, less the confirmation lag being in.
      final expected = 20 * 3600 / (14.7 * 740) * 5 / 3600;
      expect(hardL, closeTo(expected, expected * 0.35));
      final sum = rig.trip.bucketLitres.values.fold<double>(0, (a, b) => a + b);
      expect(sum, closeTo(rig.trip.litres.value, 1e-9));
    });

    test('a candidate that never confirms goes back to normal', () {
      make()
        ..drive(10, speed: (_) => 40)
        // Acceleration over the threshold for half a second only.
        ..drive(1, speed: (t) => t < 0.5 ? 40 + 12 * t : 46, maf: (_) => 12)
        ..drive(10, speed: (_) => 46);
      rig.trip.finish();
      expect(rig.trip.bucketLitres[SpendBucket.hardAcceleration], 0);
      expect(rig.trip.pendingLitres, 0);
    });
  });

  group('the rupee blocks', () {
    test(
      'there is one for each whole rupee, in order, adding up to the total',
      () {
        make(price: 300)
          ..drive(
            60,
            speed: (_) => 0,
            rpm: 800,
            maf: (_) => 2,
            throttle: (_) => 10,
          )
          ..drive(120, speed: (_) => 60, maf: (_) => 9)
          ..drive(40, speed: (_) => 110, maf: (_) => 16);
        rig.trip.finish();
        final cost = rig.trip.cost.value!;
        expect(rig.trip.blocks.length, cost.floor());
        expect(rig.trip.blocks.length, greaterThan(5));
        for (var i = 0; i < rig.trip.blocks.length; i++) {
          expect(rig.trip.blocks[i].index, i + 1);
        }
      },
    );

    test('each bucket has about the blocks its cost says', () {
      make(price: 300)
        ..drive(
          60,
          speed: (_) => 0,
          rpm: 800,
          maf: (_) => 2,
          throttle: (_) => 10,
        )
        ..drive(120, speed: (_) => 60, maf: (_) => 9)
        ..drive(40, speed: (_) => 110, maf: (_) => 16);
      rig.trip.finish();
      final costs = rig.trip.bucketCosts!;
      for (final b in SpendBucket.values) {
        final count = rig.trip.blocks.where((e) => e.bucket == b).length;
        expect((count - costs[b]!).abs(), lessThan(1.0), reason: '$b');
      }
    });

    test(
      'a price set after some driving works the blocks out from the start',
      () {
        make(price: null).drive(120, speed: (_) => 60, maf: (_) => 12);
        expect(rig.trip.blocks, isEmpty);
        var resets = 0;
        rig.trip.onBlocksReset(() => resets++);
        rig.price.value = 200;
        expect(resets, 1);
        expect(rig.trip.blocks.length, rig.trip.cost.value!.floor());
        expect(rig.trip.blocks.length, greaterThan(0));
      },
    );

    test('listeners hear each block as it prints', () {
      make(price: 300);
      final heard = <MoneyEvent>[];
      rig.trip.onBlock(heard.add);
      rig.drive(120, speed: (_) => 60, maf: (_) => 12);
      expect(heard.length, rig.trip.blocks.length);
      expect(heard, isNotEmpty);
    });
  });

  group('instant economy', () {
    test('is null below 5 km/h', () {
      make().drive(20, speed: (_) => 3);
      expect(rig.trip.instantKmPerLitre.value, isNull);
    });

    test('is speed over fuel rate once it settles', () {
      make().drive(60, speed: (_) => 60);
      expect(rig.trip.instantKmPerLitre.value, closeTo(60 / lphAt5, 0.2));
    });

    test('a coast with the fuel cut is capped, not endless', () {
      make().drive(30, speed: (_) => 60, throttle: (_) => 0, rpm: 2500);
      expect(
        rig.trip.instantKmPerLitre.value,
        TripComputer.maxInstantKmPerLitre,
      );
    });
  });

  group('fuel remaining', () {
    test('the level over the tank, and the range at this trip\'s economy', () {
      make().drive(120, speed: (_) => 60);
      rig.feed(Sensor.fuelLevel, 50);
      // The default tank is 40 L.
      expect(rig.trip.remainingLitres.value, closeTo(20, 1e-9));
      expect(
        rig.trip.remainingKm.value,
        closeTo(20 * rig.trip.kmPerLitre.value!, 1e-6),
      );
    });

    test('a car that does not report its level shows nothing', () {
      make().drive(20, speed: (_) => 60);
      expect(rig.trip.remainingLitres.value, isNull);
      expect(rig.trip.remainingKm.value, isNull);
    });
  });
}
