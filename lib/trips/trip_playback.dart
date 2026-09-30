import 'dart:math' as math;

import 'trip.dart';

/// One moment of a replayed trip (see [TripPlayback.fill]): what the car was doing,
/// and the running totals up to it. It is one object, filled in place on every
/// frame, so that replaying a trip allocates nothing.
///
/// A channel the car did not report at that moment is NaN.
class PlaybackFrame {
  /// Seconds into the replay.
  double seconds = 0;

  /// The position in the trip's samples, fractional: 12.25 is a quarter of the
  /// way from sample 12 to sample 13.
  double sample = 0;

  double speedKmh = 0;
  double rpm = 0;
  double throttle = 0;
  double litresPerHour = 0;
  double load = double.nan;
  double coolantC = double.nan;
  double voltage = double.nan;

  /// Totals from the start of the trip to this moment. [cost] is NaN with no price.
  double distanceKm = 0;
  double litres = 0;
  double cost = double.nan;

  /// What each kilometre is costing now: NaN below 5 km/h or with no price.
  double costPerKm = double.nan;
}

/// A trip's samples as something to replay (DESIGN.md 6.12's replay): a line in
/// time, from 0 to [duration], on which any moment can be asked for in any order
/// and the values between two samples are the straight line between them.
///
/// **Time.** A trip's samples are a second apart, but a trip that was resumed after
/// the engine was off has a gap of minutes in it. A replay does not wait that out:
/// a gap longer than [maxGap] takes half a second of the replay, and no distance or
/// fuel is counted across it.
///
/// **Totals.** Distance is the speed integrated over the samples and fuel is the
/// calibrated fuel flow integrated, then scaled so that the last moment's totals are
/// exactly the trip's own (the receipt's): a replay must end on the figures the
/// receipt shows. The scale is about 1 (the trip's figures were made from the same
/// readings, a little more often). Cost is the litres at the price.
class TripPlayback {
  TripPlayback(
    List<TripSample> samples, {
    this.pricePerLitre,
    double? tripDistanceKm,
    double? tripLitres,
  }) : samples = List.unmodifiable(samples) {
    final n = samples.length;
    _t = List<double>.filled(n, 0);
    _km = List<double>.filled(n, 0);
    _litres = List<double>.filled(n, 0);
    for (var i = 1; i < n; i++) {
      final a = samples[i - 1];
      final b = samples[i];
      final real = b.seconds - a.seconds;
      final gap = real > maxGap || real <= 0;
      _t[i] = _t[i - 1] + (gap ? gapSeconds : real);
      final dt = gap ? 0.0 : real;
      _km[i] = _km[i - 1] + (a.speedKmh + b.speedKmh) / 2 * dt / 3600;
      _litres[i] =
          _litres[i - 1] + (a.litresPerHour + b.litresPerHour) / 2 * dt / 3600;
    }
    if (n > 0) {
      final km = _km[n - 1];
      if (tripDistanceKm != null && tripDistanceKm > 0 && km > 0) {
        final k = tripDistanceKm / km;
        for (var i = 0; i < n; i++) {
          _km[i] *= k;
        }
      }
      final litres = _litres[n - 1];
      if (tripLitres != null && tripLitres > 0 && litres > 0) {
        final k = tripLitres / litres;
        for (var i = 0; i < n; i++) {
          _litres[i] *= k;
        }
      }
    }
  }

  /// The samples, as recorded.
  final List<TripSample> samples;

  /// The price the trip was costed at, or null if none was set.
  final double? pricePerLitre;

  /// A gap between two samples longer than this is a stretch the engine was off
  /// for (or the recorder missed): it is skipped, not replayed.
  static const double maxGap = 3;

  /// How long a skipped gap takes to cross, in the replay's seconds.
  static const double gapSeconds = 0.5;

  late final List<double> _t;
  late final List<double> _km;
  late final List<double> _litres;

  /// A second of the replay, per index: the first search starts where the last
  /// one ended, so that replaying forward costs nothing.
  int _hint = 0;

  int get length => samples.length;

  /// How long the replay is, in seconds at 1 times.
  double get duration => length < 2 ? 0 : _t[length - 1];

  /// Whether there is anything to replay: two samples at least.
  bool get isReplayable => length >= 2;

  /// The replay time of sample [i].
  double timeOfSample(int i) => _t[i.clamp(0, length - 1)];

  /// The trip's odometer at a fractional sample, in kilometres.
  double kmAtSample(double sample) {
    final i = sample.floor().clamp(0, length - 1);
    if (i >= length - 1) return _km[length - 1];
    final f = (sample - i).clamp(0.0, 1.0);
    return _km[i] + (_km[i + 1] - _km[i]) * f;
  }

  /// The fractional sample at replay time [seconds].
  double sampleAt(double seconds) {
    final i = _indexAt(seconds);
    if (i >= length - 1) return (length - 1).toDouble();
    final span = _t[i + 1] - _t[i];
    return i + (span <= 0 ? 0 : ((seconds - _t[i]) / span).clamp(0.0, 1.0));
  }

  /// The replay time of a fractional sample: where a scrubber position is.
  double timeOfFractionalSample(double sample) {
    final i = sample.floor().clamp(0, length - 1);
    if (i >= length - 1) return duration;
    final f = (sample - i).clamp(0.0, 1.0);
    return _t[i] + (_t[i + 1] - _t[i]) * f;
  }

  /// The index of the sample at or before [seconds].
  int _indexAt(double seconds) {
    final last = length - 1;
    if (seconds <= 0) return 0;
    if (seconds >= _t[last]) return last;
    var i = _hint.clamp(0, last);
    if (_t[i] > seconds) {
      // Went back: search the part before.
      var lo = 0, hi = i;
      while (lo < hi) {
        final mid = (lo + hi + 1) >> 1;
        if (_t[mid] <= seconds) {
          lo = mid;
        } else {
          hi = mid - 1;
        }
      }
      i = lo;
    } else {
      while (i < last - 1 && _t[i + 1] <= seconds) {
        i++;
      }
    }
    _hint = i;
    return i;
  }

  /// Fills [out] with the moment [seconds] into the replay (clamped to its ends).
  void fill(PlaybackFrame out, double seconds) {
    if (length == 0) return;
    final s = seconds.clamp(0.0, duration).toDouble();
    final i = _indexAt(s);
    final j = math.min(i + 1, length - 1);
    final span = _t[j] - _t[i];
    final f = span <= 0 ? 0.0 : ((s - _t[i]) / span).clamp(0.0, 1.0);
    final a = samples[i];
    final b = samples[j];

    double lerp(double x, double y) => x + (y - x) * f;
    double channel(double? x, double? y) {
      if (x != null && y != null) return lerp(x, y);
      return (f < 0.5 ? x ?? y : y ?? x) ?? double.nan;
    }

    out
      ..seconds = s
      ..sample = i + f
      ..speedKmh = lerp(a.speedKmh, b.speedKmh)
      ..rpm = lerp(a.rpm, b.rpm)
      ..throttle = lerp(a.throttle, b.throttle)
      ..litresPerHour = lerp(a.litresPerHour, b.litresPerHour)
      ..load = channel(a.load, b.load)
      ..coolantC = channel(a.coolantC, b.coolantC)
      ..voltage = channel(a.voltage, b.voltage)
      ..distanceKm = lerp(_km[i], _km[j])
      ..litres = lerp(_litres[i], _litres[j]);
    final price = pricePerLitre;
    out.cost = price == null ? double.nan : out.litres * price;
    out.costPerKm = price == null || out.speedKmh < 5
        ? double.nan
        : out.litresPerHour * price / out.speedKmh;
  }
}
