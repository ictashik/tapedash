import '../trips/trip.dart';

/// One 10 km/h band of the efficiency curve (DESIGN.md 6.13).
class SpeedBand {
  const SpeedBand({
    required this.fromKmh,
    required this.km,
    required this.litres,
  });

  final int fromKmh;

  /// The band's width: 10 km/h.
  int get toKmh => fromKmh + SweetSpot.bandWidthKmh;

  /// Distance and fuel over the steady samples in the band.
  final double km;
  final double litres;

  /// Kilometres a litre, or null while there is too little data (under
  /// [SweetSpot.minKmPerBand]) or no fuel.
  double? get kmPerLitre =>
      km >= SweetSpot.minKmPerBand && litres > 0 ? km / litres : null;
}

/// The car's own efficiency curve and its sweet spot (CLAUDE.md 8.9): from the
/// steady stretches of all real trips, how many kilometres a litre it does at
/// each speed, and which speed does best.
///
/// **Steady** means the speed is changing by less than 0.3 m/s² and the throttle
/// by less than 5% a second: cruising, not accelerating or braking, since those
/// say what the driving was and not what the car does at that speed. A band
/// reports a figure only once it has 3 km of steady data, so a few seconds at
/// 90 km/h never make a sweet spot.
class SweetSpot {
  const SweetSpot(this.bands);

  static const int bandWidthKmh = 10;
  static const double maxAccelerationMs2 = 0.3;
  static const double maxThrottleChangePerSecond = 5;
  static const double minKmPerBand = 3;

  /// The bands with any steady data, slowest first.
  final List<SpeedBand> bands;

  /// The bands that have enough data to report.
  List<SpeedBand> get reported => [
    for (final b in bands)
      if (b.kmPerLitre != null) b,
  ];

  /// The band that does the most kilometres a litre, among those reported, or
  /// null while there are none. With one band reported it is that one.
  SpeedBand? get best {
    SpeedBand? best;
    for (final b in reported) {
      if (best == null || b.kmPerLitre! > best.kmPerLitre!) best = b;
    }
    return best;
  }

  /// The sweet spot's range: the best band and the bands beside it that are within
  /// 3% of it (DESIGN.md 6.13), as (from, to) km/h, or null with no best.
  ({int from, int to})? get range {
    final b = best;
    if (b == null) return null;
    final floor = b.kmPerLitre! * 0.97;
    var from = b.fromKmh;
    var to = b.toKmh;
    final byFrom = {for (final x in reported) x.fromKmh: x};
    bool within(int fromKmh) {
      final n = byFrom[fromKmh];
      return n != null && n.kmPerLitre! >= floor;
    }

    while (within(from - bandWidthKmh)) {
      from -= bandWidthKmh;
    }
    while (within(to)) {
      to += bandWidthKmh;
    }
    return (from: from, to: to);
  }

  /// The car's overall average over the steady samples, km/L, or null with no data.
  double? get average {
    var km = 0.0, litres = 0.0;
    for (final b in bands) {
      km += b.km;
      litres += b.litres;
    }
    return litres > 0 && km >= minKmPerBand ? km / litres : null;
  }

  /// The curve from the samples of any number of trips (each in order, one a
  /// second, as the recorder takes them).
  static SweetSpot fromTrips(Iterable<List<TripSample>> trips) {
    final km = <int, double>{};
    final litres = <int, double>{};
    for (final samples in trips) {
      for (var i = 1; i < samples.length; i++) {
        final a = samples[i - 1];
        final b = samples[i];
        final dt = b.seconds - a.seconds;
        if (dt <= 0 || dt > 2.5) continue;
        final accel = (b.speedKmh - a.speedKmh) / 3.6 / dt;
        final throttle = (b.throttle - a.throttle).abs() / dt;
        if (accel.abs() >= maxAccelerationMs2 ||
            throttle >= maxThrottleChangePerSecond) {
          continue;
        }
        final speed = (a.speedKmh + b.speedKmh) / 2;
        if (speed < 5) continue;
        final band = (speed ~/ bandWidthKmh) * bandWidthKmh;
        km[band] = (km[band] ?? 0) + speed * dt / 3600;
        litres[band] =
            (litres[band] ?? 0) +
            (a.litresPerHour + b.litresPerHour) / 2 * dt / 3600;
      }
    }
    final keys = km.keys.toList()..sort();
    return SweetSpot([
      for (final k in keys)
        SpeedBand(fromKmh: k, km: km[k]!, litres: litres[k] ?? 0),
    ]);
  }
}

/// The curve from every real trip in [trips]: demo trips are left out by the
/// repository (CLAUDE.md 8.9: "from all real, non-demo trips").
Future<SweetSpot> sweetSpotFrom(TripRepository trips) async {
  final all = await trips.all();
  final samples = <List<TripSample>>[];
  for (final t in all) {
    if (t.id != null) samples.add(await trips.samples(t.id!));
  }
  return SweetSpot.fromTrips(samples);
}
