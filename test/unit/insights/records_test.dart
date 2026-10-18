import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/key_value_store.dart';
import 'package:tapedash/insights/cold_start.dart';
import 'package:tapedash/insights/ghost_commute.dart';
import 'package:tapedash/insights/rest_voltage_log.dart';
import 'package:tapedash/insights/toll_map.dart';
import 'package:tapedash/insights/voltage_trace.dart';
import 'package:tapedash/insights/year_on_tape.dart';
import 'package:tapedash/money/spend_bucket.dart';
import 'package:tapedash/trips/trip.dart';

import '../../support/insight_drive.dart';

void main() {
  group('VoltageTrace', () {
    test('finds the dips and how deep, and the share of time charging', () {
      final samples = madeDrive(
        120,
        kmh: (_) => 40,
        volts: (t) {
          if (t >= 30 && t < 38) return 12.6; // a load, 8 s
          if (t >= 80 && t < 84) return 13.1; // a smaller one, 4 s
          return 14.0;
        },
      );
      final v = VoltageTrace.from(samples);
      expect(v.dips.length, 2);
      expect(v.dips[0].startSeconds, closeTo(30, 1));
      expect(v.dips[0].seconds, closeTo(8, 1.5));
      expect(v.dips[0].depth, closeTo(1.4, 0.05));
      expect(v.dips[1].depth, closeTo(0.9, 0.05));
      expect(v.chargingShare, closeTo(1 - 12 / 121, 0.03));
      expect(v.median, 14.0);
    });

    test('a reading that jitters by a tenth is not a dip', () {
      final v = VoltageTrace.from(
        madeDrive(
          100,
          kmh: (_) => 40,
          volts: (t) => 14.0 + (t.isEven ? 0.1 : -0.1),
        ),
      );
      expect(v.dips, isEmpty);
    });

    test('a sag that never ends is the voltage settling, not a load', () {
      final v = VoltageTrace.from(
        madeDrive(300, kmh: (_) => 40, volts: (t) => t < 100 ? 14.0 : 13.2),
      );
      expect(v.dips, isEmpty);
    });

    test('with the engine off, or no voltage, there is nothing', () {
      expect(VoltageTrace.from(madeDrive(60, kmh: (_) => 40)).isEmpty, isTrue);
    });
  });

  group('RestVoltageLog', () {
    test(
      'keeps one reading in six hours, and reads back what it kept',
      () async {
        final clock = FakeClock();
        final store = MemoryKeyValueStore();
        final log = RestVoltageLog(store: store, clock: clock);
        expect(await log.note(12.5), isTrue);
        clock.advance(const Duration(hours: 1));
        expect(await log.note(12.4), isFalse);
        clock.advance(const Duration(hours: 6));
        expect(await log.note(12.4), isTrue);

        final again = RestVoltageLog(store: store, clock: clock);
        await again.load();
        expect([for (final r in again.readings) r.volts], [12.5, 12.4]);
      },
    );

    test('a charger or the alternator is not the battery at rest', () async {
      final log = RestVoltageLog(
        store: MemoryKeyValueStore(),
        clock: FakeClock(),
      );
      expect(await log.note(14.1), isFalse);
      expect(await log.note(9.0), isFalse);
      expect(log.readings, isEmpty);
    });

    test('it keeps the last 120', () async {
      final clock = FakeClock();
      final log = RestVoltageLog(store: MemoryKeyValueStore(), clock: clock);
      for (var i = 0; i < 130; i++) {
        clock.advance(const Duration(hours: 7));
        await log.note(12.5);
      }
      expect(log.readings.length, RestVoltageLog.keep);
    });
  });

  group('TollMap', () {
    // 10 minutes along a road with a stand of 120 s at 2 km, and another of 60 s
    // near the same place later on, and a short one that is only a bump.
    List<TripSample> day(double lat, double lon) => madeDrive(
      700,
      kmh: (t) {
        if (t >= 200 && t < 320) return 0;
        if (t >= 500 && t < 560) return 0;
        if (t >= 400 && t < 408) return 0;
        return 36;
      },
      lph: (t, v) => v < 1 ? 0.9 : 3,
      position: (t, km) => eastward(lat, lon, km),
    );

    test(
      'puts the money at the places the car stood, and joins the near ones',
      () {
        final a = day(12.9, 77.6);
        final trip = Trip(startedAt: DateTime(2026, 10, 1), pricePerLitre: 100);
        final map = TollMap.from([(trip, a), (trip, day(12.9, 77.6))]);
        expect(map.spots, isNotEmpty);
        final top = map.spots.first;
        // The 120 s stands are at the same place on both days: four stops would be
        // the two long ones twice over, and the bump is under 15 s.
        expect(top.stops, greaterThanOrEqualTo(2));
        expect(top.litres, closeTo(2 * 0.9 * 120 / 3600, 0.01));
        expect(top.rupees, closeTo(top.litres * 100, 1e-6));
        expect(map.roads.length, 2);
      },
    );

    test(
      'the dearest place comes first and nothing is drawn without cause',
      () {
        final trip = Trip(startedAt: DateTime(2026, 10, 1), pricePerLitre: 100);
        final map = TollMap.from([(trip, day(12.9, 77.6))]);
        for (var i = 1; i < map.spots.length; i++) {
          expect(
            map.spots[i].rupees!,
            lessThanOrEqualTo(map.spots[i - 1].rupees!),
          );
        }
        final none = TollMap.from([
          (
            trip,
            madeDrive(
              120,
              kmh: (_) => 40,
              position: (t, km) => eastward(12.9, 77.6, km),
            ),
          ),
        ]);
        expect(none.isEmpty, isTrue);
      },
    );

    test('with no price, litres are what there is', () {
      final trip = Trip(startedAt: DateTime(2026, 10, 1));
      final map = TollMap.from([(trip, day(12.9, 77.6))]);
      expect(map.spots.first.rupees, isNull);
      expect(map.spots.first.litres, greaterThan(0));
      final priced = TollMap.from([
        (trip, day(12.9, 77.6)),
      ], fallbackPrice: 115);
      expect(priced.spots.first.rupees, isNotNull);
    });

    test('the map fits its points into the panel with a margin', () {
      final trip = Trip(startedAt: DateTime(2026, 10, 1), pricePerLitre: 100);
      final fit = TollMap.from([(trip, day(12.9, 77.6))]).fit();
      expect(fit.widthM, greaterThan(5000));
      final scale = fit.scale(600, 300, 20);
      expect(scale * fit.widthM, lessThanOrEqualTo(560 + 1e-6));
    });
  });

  group('ColdStart', () {
    // 18 minutes: the coolant climbs from 35 to 90 in 8, and the cold running
    // costs more a kilometre than the warm.
    List<TripSample> cold({double startC = 35}) => madeDrive(
      1080,
      kmh: (t) => 40,
      lph: (t, v) => t < 480 ? 5.5 - t / 480 * 1.5 : 4.0,
      coolant: (t) => t < 480 ? startC + (90 - startC) * t / 480 : 90,
    );

    test('puts a bill on the cold running, over the warm cost', () {
      final trip = Trip(
        startedAt: DateTime(2026, 10, 1),
        pricePerLitre: 100,
        litres: 1,
      );
      final c = ColdStart.of(trip, cold())!;
      // Warm: 4 L/h at 40 km/h is 0.1 L/km, so Rs 10 a km.
      expect(c.warmPerKm, closeTo(10, 0.3));
      expect(c.warmAtMinutes, closeTo(7, 1.5));
      expect(c.extraRupees, greaterThan(5));
      expect(c.coldKm, greaterThan(3));
      expect(c.windows.first.perKm, greaterThan(c.warmPerKm));
    });

    test('a trip that began warm has no cold start', () {
      final trip = Trip(startedAt: DateTime(2026, 10, 1), pricePerLitre: 100);
      expect(ColdStart.of(trip, cold(startC: 85)), isNull);
    });

    test('no price, or no warm driving after, says nothing', () {
      final unpriced = Trip(startedAt: DateTime(2026, 10, 1));
      expect(ColdStart.of(unpriced, cold()), isNull);
      final priced = Trip(startedAt: DateTime(2026, 10, 1), pricePerLitre: 100);
      expect(ColdStart.of(priced, cold().take(300).toList()), isNull);
    });
  });

  group('GhostMatch', () {
    List<TripSample> route(double lat, double lon, {double km = 8}) =>
        madeDrive(
          (km / 40 * 3600).round(),
          kmh: (_) => 40,
          position: (t, d) => eastward(lat, lon + 0.0, d),
        );
    Trip trip(int id, int day, {double? cost, bool demo = false}) => Trip(
      id: id,
      startedAt: DateTime(2026, 10, day, 8),
      cost: cost,
      isDemo: demo,
      idleSeconds: cost == null ? 0 : cost * 2,
    );

    test('finds the latest earlier drive of the same route', () {
      final now = trip(3, 16, cost: 90);
      final tue = trip(2, 14, cost: 104);
      final mon = trip(1, 13, cost: 110);
      final other = trip(4, 15, cost: 50);
      final m = GhostMatch.find(now, route(12.9, 77.6), [
        (mon, route(12.9, 77.6)),
        (tue, route(12.9, 77.6)),
        (other, route(13.2, 77.9)),
      ])!;
      expect(m.before.id, 2);
      expect(m.rupeesSaved, 14);
      expect(m.nowRoute.length, GhostMatch.points);
    });

    test(
      'another place, another length, a demo or a later trip is no match',
      () {
        final now = trip(3, 16, cost: 90);
        expect(
          GhostMatch.find(now, route(12.9, 77.6), [
            (trip(1, 13), route(13.2, 77.9)),
            (trip(2, 14), route(12.9, 77.6, km: 20)),
            (trip(5, 15, demo: true), route(12.9, 77.6)),
            (trip(6, 20), route(12.9, 77.6)),
          ]),
          isNull,
        );
      },
    );

    test('an unpriced trip compares nothing in rupees', () {
      final m = GhostMatch.find(trip(3, 16), route(12.9, 77.6), [
        (trip(2, 14, cost: 100), route(12.9, 77.6)),
      ])!;
      expect(m.rupeesSaved, isNull);
    });
  });

  group('YearOnTape', () {
    Trip t(DateTime at, double cost, {bool demo = false, double idle = 0.2}) =>
        Trip(
          startedAt: at,
          isDemo: demo,
          litres: cost / 100,
          cost: cost,
          distanceKm: cost / 8,
          bucketLitres: {
            SpendBucket.normal: (1 - idle) * cost / 100,
            SpendBucket.idling: idle * cost / 100,
          },
        );

    test('a bar a trip, oldest first, shares adding to one, demo left out', () {
      final y = YearOnTape.from([
        t(DateTime(2026, 3, 5), 120),
        t(DateTime(2026, 1, 9), 80),
        t(DateTime(2026, 2, 1), 999, demo: true),
        t(DateTime(2025, 12, 31), 70),
      ], 2026);
      expect(y.trips, 2);
      expect(y.bars.first.at.month, 1);
      expect(y.spent, 200);
      expect(y.km, closeTo(25, 1e-9));
      expect(y.idleSpent, closeTo(40, 1e-6));
      expect(y.idleShare, closeTo(0.2, 1e-9));
      for (final b in y.bars) {
        expect(b.shares.fold<double>(0, (a, s) => a + s), closeTo(1, 1e-9));
      }
      expect(y.priced, isTrue);
    });

    test('without a price the year is in litres', () {
      final y = YearOnTape.from([
        Trip(startedAt: DateTime(2026, 5, 1), litres: 2, distanceKm: 20),
      ], 2026);
      expect(y.priced, isFalse);
      expect(y.spent, 2);
    });

    test('the year shown is this one, else the latest with trips', () {
      final trips = [t(DateTime(2025, 4, 1), 50), t(DateTime(2024, 4, 1), 50)];
      expect(YearOnTape.defaultYear(trips, DateTime(2026, 1, 1)), 2025);
      expect(YearOnTape.defaultYear(const [], DateTime(2026, 1, 1)), 2026);
      expect(
        YearOnTape.defaultYear([
          t(DateTime(2026, 2, 1), 50),
        ], DateTime(2026, 6, 1)),
        2026,
      );
    });
  });
}
