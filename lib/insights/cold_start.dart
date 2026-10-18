import 'dart:math' as math;

import '../trips/trip.dart';

/// One stretch of a cold start: a window of driving, with what the coolant read
/// and what it cost a kilometre.
class ColdWindow {
  const ColdWindow(this.minutes, this.coolantC, this.perKm);
  final double minutes;
  final double coolantC;

  /// Rupees a kilometre in the window.
  final double perKm;
}

/// What the first minutes after a cold start cost over the warm engine (Cold-start
/// bill): rupees a kilometre while the coolant climbs, against what the same car
/// does once it is warm.
class ColdStart {
  ColdStart._({
    required this.windows,
    required this.warmPerKm,
    required this.warmAtMinutes,
    required this.extraRupees,
    required this.coldKm,
  });

  /// The seconds each window covers.
  static const double windowSeconds = 30;

  /// The coolant has to start under this for the trip to be a cold start, and the
  /// engine is warm from this.
  static const double coldBelowC = 65;
  static const double warmFromC = 80;

  /// Warm driving needed to know the warm cost, and the least distance a window
  /// needs to give a rupees-a-kilometre.
  static const double minWarmSeconds = 180;
  static const double minWindowKm = 0.08;

  /// The cold windows and the warm ones after, in order.
  final List<ColdWindow> windows;

  /// What a kilometre cost once the engine was warm.
  final double warmPerKm;

  /// How many minutes in the engine reached [warmFromC].
  final double warmAtMinutes;

  /// The rupees spent on the cold running beyond what warm running costs.
  final double extraRupees;

  /// The distance driven while the engine was cold.
  final double coldKm;

  /// Null for a trip that did not start cold, did not warm up, did not drive long
  /// enough warm to know the warm cost, or has no price or coolant.
  static ColdStart? of(
    Trip trip,
    List<TripSample> samples, {
    double? fallbackPrice,
  }) {
    final price = trip.pricePerLitre ?? fallbackPrice;
    if (price == null || samples.length < 60) return null;
    final first = samples.firstWhere(
      (s) => s.coolantC != null,
      orElse: () => samples.first,
    );
    if (first.coolantC == null || first.coolantC! >= coldBelowC) return null;

    // Windows of driving, each with its distance, rupees and last coolant.
    final raw = <(double minutes, double coolant, double km, double rupees)>[];
    var t0 = samples.first.seconds;
    var km = 0.0, rupees = 0.0;
    double? coolant;
    double? last;
    for (final s in samples) {
      final dt = last == null ? 0.0 : s.seconds - last;
      last = s.seconds;
      if (dt > 0 && dt <= 5) {
        km += s.speedKmh * dt / 3600;
        rupees += s.litresPerHour * dt / 3600 * price;
      }
      if (s.coolantC != null) coolant = s.coolantC;
      if (s.seconds - t0 >= windowSeconds) {
        if (coolant != null) {
          raw.add(((s.seconds - windowSeconds / 2) / 60, coolant, km, rupees));
        }
        t0 = s.seconds;
        km = 0;
        rupees = 0;
      }
    }
    final moving = [
      for (final w in raw)
        if (w.$3 >= minWindowKm) w,
    ];
    final warm = moving.where((w) => w.$2 >= warmFromC).toList();
    if (warm.length * windowSeconds < minWarmSeconds) return null;
    final perKm = [for (final w in warm) w.$4 / w.$3]..sort();
    final warmPerKm = perKm[perKm.length ~/ 2];
    final firstWarm = moving.firstWhere((w) => w.$2 >= warmFromC);

    var extra = 0.0, coldKm = 0.0;
    final windows = <ColdWindow>[];
    for (final w in moving) {
      windows.add(ColdWindow(w.$1, w.$2, w.$4 / w.$3));
      if (w.$1 < firstWarm.$1) {
        extra += math.max(0, w.$4 - warmPerKm * w.$3);
        coldKm += w.$3;
      }
    }
    if (coldKm <= 0) return null;
    return ColdStart._(
      windows: windows,
      warmPerKm: warmPerKm,
      warmAtMinutes: firstWarm.$1,
      extraRupees: extra,
      coldKm: coldKm,
    );
  }
}
