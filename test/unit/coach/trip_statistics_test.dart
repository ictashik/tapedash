import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/coach/trip_statistics.dart';
import 'package:tapedash/trips/trip.dart';

Trip t(
  DateTime at, {
  double km = 10,
  double cost = 100,
  bool demo = false,
  double? c,
}) => Trip(
  startedAt: at,
  distanceKm: km,
  litres: cost / 100,
  cost: c ?? cost,
  isDemo: demo,
);

void main() {
  // 2026-03-04 is a Wednesday.
  final now = DateTime(2026, 3, 4, 12);

  test('a week starts on Monday at midnight', () {
    expect(TripStatistics.weekStart(now), DateTime(2026, 3, 2));
    expect(
      TripStatistics.weekStart(DateTime(2026, 3, 2, 0, 5)),
      DateTime(2026, 3, 2),
    );
    expect(
      TripStatistics.weekStart(DateTime(2026, 3, 8, 23, 59)),
      DateTime(2026, 3, 2),
    );
    expect(
      TripStatistics.weekStart(DateTime(2026, 3, 9)),
      DateTime(2026, 3, 9),
    );
  });

  test('the weeks are oldest first and end with this one', () {
    final w = TripStatistics.weekly(const [], now, weeks: 3);
    expect(
      [for (final x in w) x.start],
      [DateTime(2026, 2, 16), DateTime(2026, 2, 23), DateTime(2026, 3, 2)],
    );
  });

  test('trips land in their own week, and add up', () {
    final trips = [
      t(DateTime(2026, 3, 3), km: 10, cost: 100),
      t(DateTime(2026, 3, 4), km: 20, cost: 150),
      t(DateTime(2026, 2, 25), km: 5, cost: 40),
    ];
    final w = TripStatistics.weekly(trips, now, weeks: 2);
    expect(w[1].km, 30);
    expect(w[1].cost, 250);
    expect(w[1].trips, 2);
    expect(w[0].km, 5);
    expect(w[1].costPerKm, closeTo(250 / 30, 1e-9));
  });

  test('a trip at midnight on Monday is in the new week', () {
    final w = TripStatistics.weekly(
      [t(DateTime(2026, 3, 2), km: 3)],
      now,
      weeks: 2,
    );
    expect(w[1].trips, 1);
    expect(w[0].trips, 0);
  });

  test('demo trips are left out', () {
    final w = TripStatistics.weekly(
      [t(DateTime(2026, 3, 3), demo: true)],
      now,
      weeks: 1,
    );
    expect(w.single.trips, 0);
  });

  test('trips with no price add distance and fuel and no money', () {
    final w = TripStatistics.weekly(
      [Trip(startedAt: DateTime(2026, 3, 3), distanceKm: 10, litres: 1)],
      now,
      weeks: 1,
    );
    expect(w.single.km, 10);
    expect(w.single.cost, 0);
    expect(w.single.costPerKm, isNull);
  });

  test('the month is the calendar month', () {
    final m = TripStatistics.month([
      t(DateTime(2026, 3, 1), km: 10),
      t(DateTime(2026, 3, 31, 23), km: 10),
      t(DateTime(2026, 2, 28), km: 10),
      t(DateTime(2026, 4, 1), km: 10),
    ], now);
    expect(m.km, 20);
    expect(m.trips, 2);
  });
}
