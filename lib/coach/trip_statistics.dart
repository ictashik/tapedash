import '../trips/trip.dart';

/// One week of driving, from a Monday (the Coach page's THIS WEEK and LAST WEEK,
/// DESIGN.md 7.6).
class WeekTotal {
  const WeekTotal({
    required this.start,
    required this.km,
    required this.cost,
    required this.litres,
    required this.trips,
  });

  final DateTime start;
  final double km;

  /// Money spent, counting only trips that had a price.
  final double cost;
  final double litres;
  final int trips;

  /// Rupees a kilometre, or null with no distance or no priced trip.
  double? get costPerKm => km >= 0.5 && cost > 0 ? cost / km : null;
}

/// Sums of trips over time. Demo trips never reach here: the repository leaves
/// them out, and these functions leave out any that come anyway (CLAUDE.md 7.6).
abstract final class TripStatistics {
  /// The Monday at or before [d], at midnight.
  static DateTime weekStart(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  /// The [weeks] weeks up to and including the one [now] is in, oldest first.
  static List<WeekTotal> weekly(
    Iterable<Trip> trips,
    DateTime now, {
    int weeks = 8,
  }) {
    final thisWeek = weekStart(now);
    final out = <WeekTotal>[];
    for (var w = weeks - 1; w >= 0; w--) {
      final start = thisWeek.subtract(Duration(days: 7 * w));
      final end = start.add(const Duration(days: 7));
      var km = 0.0, cost = 0.0, litres = 0.0, count = 0;
      for (final t in trips) {
        if (t.isDemo) continue;
        if (t.startedAt.isBefore(start) || !t.startedAt.isBefore(end)) continue;
        km += t.distanceKm;
        litres += t.litres;
        cost += t.cost ?? 0;
        count++;
      }
      out.add(
        WeekTotal(
          start: start,
          km: km,
          cost: cost,
          litres: litres,
          trips: count,
        ),
      );
    }
    return out;
  }

  /// The total over the month [now] is in (the History header, DESIGN.md 7.7).
  static WeekTotal month(Iterable<Trip> trips, DateTime now) {
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    var km = 0.0, cost = 0.0, litres = 0.0, count = 0;
    for (final t in trips) {
      if (t.isDemo) continue;
      if (t.startedAt.isBefore(start) || !t.startedAt.isBefore(end)) continue;
      km += t.distanceKm;
      litres += t.litres;
      cost += t.cost ?? 0;
      count++;
    }
    return WeekTotal(
      start: start,
      km: km,
      cost: cost,
      litres: litres,
      trips: count,
    );
  }
}
