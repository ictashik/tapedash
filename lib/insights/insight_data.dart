import '../trips/trip.dart';
import 'cold_start.dart';
import 'gearbox.dart';
import 'ghost_commute.dart';
import 'insight_constants.dart';
import 'power_curve.dart';
import 'powerflow.dart';
import 'toll_map.dart';
import 'voltage_trace.dart';
import 'year_on_tape.dart';

/// The trips the insight pages read, with their samples, and each analysis made
/// once on demand. It is a snapshot: the page makes a new one when it opens.
///
/// Real drives and the demo are never mixed (CLAUDE.md 7.6): a real car's insights
/// are from its real trips, and Demo Mode's from the demo's.
class InsightData {
  InsightData._(this.trips, this._samples, this.fallbackPrice, this.constants);

  /// Trips read at most, newest first; a car driven daily for a year is under 800
  /// and an older one adds little to a picture of how the car is driven.
  static const int maxTrips = 400;

  /// Trips with fewer samples than this are a start and a stop, not driving.
  static const int minSamples = 30;

  final List<Trip> trips;
  final Map<int, List<TripSample>> _samples;
  final double? fallbackPrice;
  final InsightConstants constants;

  bool get isEmpty => trips.isEmpty;

  List<TripSample> samplesOf(Trip trip) => _samples[trip.id] ?? const [];

  /// Every trip with its samples, newest first.
  Iterable<(Trip, List<TripSample>)> get withSamples sync* {
    for (final t in trips) {
      yield (t, samplesOf(t));
    }
  }

  /// Reads the trips of one kind from [repository].
  static Future<InsightData> load(
    TripRepository repository, {
    required bool demo,
    double? fallbackPrice,
    InsightConstants constants = const InsightConstants(),
  }) async {
    final all = await repository.all(includeDemo: demo);
    final trips = <Trip>[];
    final samples = <int, List<TripSample>>{};
    for (final t in all) {
      if (t.isDemo != demo || t.id == null || t.endedAt == null) continue;
      if (trips.length >= maxTrips) break;
      final s = await repository.samples(t.id!);
      if (s.length < minSamples) continue;
      trips.add(t);
      samples[t.id!] = s;
    }
    return InsightData._(trips, samples, fallbackPrice, constants);
  }

  /// In memory, for a test.
  factory InsightData.of(
    Iterable<(Trip, List<TripSample>)> trips, {
    double? fallbackPrice,
    InsightConstants constants = const InsightConstants(),
  }) => InsightData._(
    [for (final (t, _) in trips) t],
    {for (final (t, s) in trips) t.id ?? -1: s},
    fallbackPrice,
    constants,
  );

  // ---------------------------------------------------------------- analyses

  late final PowerCurve powerCurve = PowerCurve.from([
    for (final (_, s) in withSamples) s,
  ], constants: constants);

  late final Gearbox gearbox = Gearbox.from([
    for (final (_, s) in withSamples) s,
  ]);

  late final TollMap tollMap = TollMap.from(
    withSamples,
    fallbackPrice: fallbackPrice,
  );

  /// The year with the most trips, or [now]'s when there are none.
  int yearFor(DateTime now) => YearOnTape.defaultYear(trips, now);

  YearOnTape year(int year) => YearOnTape.from(trips, year);

  /// Voltage over the whole of [trip].
  VoltageTrace voltageOf(Trip trip) => VoltageTrace.from(samplesOf(trip));

  Powerflow? powerflowOf(Trip trip) =>
      Powerflow.of(trip, samplesOf(trip), constants: constants);

  ColdStart? coldStartOf(Trip trip) =>
      ColdStart.of(trip, samplesOf(trip), fallbackPrice: fallbackPrice);

  GhostMatch? ghostOf(Trip trip) =>
      GhostMatch.find(trip, samplesOf(trip), withSamples);

  /// The cold-start bill of the trips in the month of [at], as (rupees, trips).
  (double, int) coldMonth(DateTime at) {
    var rupees = 0.0, n = 0;
    for (final (t, s) in withSamples) {
      if (t.startedAt.year != at.year || t.startedAt.month != at.month) {
        continue;
      }
      final c = ColdStart.of(t, s, fallbackPrice: fallbackPrice);
      if (c == null) continue;
      rupees += c.extraRupees;
      n++;
    }
    return (rupees, n);
  }
}
