import '../money/spend_bucket.dart';
import '../trips/trip.dart';

/// One trip of the year, as a bar: how much it cost, and in what shares by where
/// the money went.
class YearBar {
  const YearBar({
    required this.at,
    required this.value,
    required this.shares,
    required this.km,
  });

  final DateTime at;

  /// Rupees, or litres when the year had no price.
  final double value;

  /// The share of each [SpendBucket], in the enum's order, adding up to 1.
  final List<double> shares;
  final double km;
}

/// A year of driving as a barcode (Year on Tape): a bar for each trip, stacked by
/// where its money went, and the year's totals.
///
/// Simulated trips (`Trip.isDemo`, left by older builds) never count.
class YearOnTape {
  YearOnTape._({
    required this.year,
    required this.bars,
    required this.priced,
    required this.km,
    required this.spent,
    required this.idleSpent,
  });

  final int year;

  /// Oldest first.
  final List<YearBar> bars;

  /// Whether the figures are rupees (any trip had a price) or litres.
  final bool priced;

  final double km;

  /// Rupees (or litres) spent, and of that on idling.
  final double spent;
  final double idleSpent;

  int get trips => bars.length;
  bool get isEmpty => bars.isEmpty;

  double get idleShare => spent <= 0 ? 0 : idleSpent / spent;

  /// The year with the most trips among those given, or the current year if
  /// there are none. A new year starts a new poster; the old one stays reachable.
  static int defaultYear(Iterable<Trip> trips, DateTime now) {
    final counts = <int, int>{};
    for (final t in trips) {
      if (!t.isDemo) {
        counts[t.startedAt.year] = (counts[t.startedAt.year] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return now.year;
    return counts.containsKey(now.year)
        ? now.year
        : (counts.keys.toList()..sort()).last;
  }

  factory YearOnTape.from(Iterable<Trip> trips, int year) {
    final mine = [
      for (final t in trips)
        if (!t.isDemo && t.startedAt.year == year && t.litres > 0) t,
    ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final priced = mine.any((t) => t.cost != null);
    final bars = <YearBar>[];
    var km = 0.0, spent = 0.0, idle = 0.0;
    for (final t in mine) {
      final value = priced ? (t.cost ?? 0) : t.litres;
      if (value <= 0) continue;
      final litres = t.bucketLitres.values.fold<double>(0, (a, b) => a + b);
      final shares = [
        for (final b in SpendBucket.values)
          litres <= 0
              ? (b == SpendBucket.normal ? 1.0 : 0.0)
              : (t.bucketLitres[b] ?? 0) / litres,
      ];
      bars.add(
        YearBar(
          at: t.startedAt,
          value: value,
          shares: shares,
          km: t.distanceKm,
        ),
      );
      km += t.distanceKm;
      spent += value;
      idle += value * shares[SpendBucket.idling.index];
    }
    return YearOnTape._(
      year: year,
      bars: bars,
      priced: priced,
      km: km,
      spent: spent,
      idleSpent: idle,
    );
  }
}
