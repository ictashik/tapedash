import 'dart:math' as math;

import '../trips/trip.dart';
import 'insight_constants.dart';

/// One moment of a drive, with the power it asked of the wheels.
class WheelMoment {
  const WheelMoment({
    required this.seconds,
    required this.dt,
    required this.speedKmh,
    required this.rpm,
    required this.throttle,
    required this.tractionKw,
    required this.rollingKw,
    required this.airKw,
    required this.brakingKw,
    required this.sample,
  });

  final double seconds;

  /// The seconds this moment stands for.
  final double dt;
  final double speedKmh;
  final double rpm;
  final double throttle;

  /// What the engine had to put into the wheels: positive when pulling, else 0.
  final double tractionKw;

  /// What the tyres and the air took at this speed.
  final double rollingKw;
  final double airKw;

  /// What the brakes took beyond that: the car slowing faster than the road and
  /// the air alone would slow it.
  final double brakingKw;

  final TripSample sample;
}

/// The wheel power of a drive, worked out from its speed trace (the car reports no
/// torque, and the City no fuel rate): the force to speed up, to roll and to push
/// the air aside, times the speed.
///
/// OBD speed is whole km/h and sometimes wrong for a reading (a real drive shows a
/// 46 to 95 km/h jump on a 40 km/h road), and an acceleration taken from noise is
/// rectified by counting only the pulling: noise alone would make the engine look
/// as if it did work. So the speed is first cleaned of one-reading spikes (the
/// median of three), the acceleration is the slope of a straight line through the
/// speeds within [halfWindow] seconds either side, and a moment that asks more than
/// a car can give ([maxAcceleration]) is dropped as a glitch. An estimate, and a
/// rough one: it knows nothing of hills.
abstract final class WheelPower {
  /// The longest gap between two samples that still counts as driving; a longer
  /// one is the engine being off or the link being out.
  static const double maxGap = 5;

  /// The seconds of speed either side the acceleration is fitted over.
  static const double halfWindow = 3;

  /// No small car accelerates or brakes harder than this (m/s2), in a road test or
  /// a panic stop; a reading that says so is a glitch.
  static const double maxAcceleration = 5;

  static List<WheelMoment> moments(
    List<TripSample> samples, {
    InsightConstants constants = const InsightConstants(),
  }) {
    final out = <WheelMoment>[];
    final n = samples.length;
    if (n < 3) return out;
    final m = constants.massKg;

    // The speeds in m/s, a spike of one reading taken out.
    final v = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final a = samples[math.max(0, i - 1)].speedKmh;
      final b = samples[i].speedKmh;
      final c = samples[math.min(n - 1, i + 1)].speedKmh;
      v[i] = (math.max(math.min(a, b), math.min(math.max(a, b), c))) / 3.6;
    }

    for (var i = 1; i < n; i++) {
      final s = samples[i];
      final dt = s.seconds - samples[i - 1].seconds;
      if (dt <= 0 || dt > maxGap) continue;
      // The straight line through the speeds near this moment.
      var lo = i, hi = i;
      while (lo > 0 &&
          s.seconds - samples[lo - 1].seconds <= halfWindow &&
          samples[lo].seconds - samples[lo - 1].seconds <= maxGap) {
        lo--;
      }
      while (hi < n - 1 &&
          samples[hi + 1].seconds - s.seconds <= halfWindow &&
          samples[hi + 1].seconds - samples[hi].seconds <= maxGap) {
        hi++;
      }
      double a;
      if (hi - lo >= 2) {
        var tm = 0.0, vm = 0.0;
        for (var k = lo; k <= hi; k++) {
          tm += samples[k].seconds;
          vm += v[k];
        }
        tm /= hi - lo + 1;
        vm /= hi - lo + 1;
        var num = 0.0, den = 0.0;
        for (var k = lo; k <= hi; k++) {
          final d = samples[k].seconds - tm;
          num += d * (v[k] - vm);
          den += d * d;
        }
        a = den <= 0 ? 0 : num / den;
      } else {
        a = (v[i] - v[i - 1]) / dt;
      }
      if (a.abs() > maxAcceleration) continue;
      final speed = v[i];
      final rolling = speed < 0.3
          ? 0.0
          : constants.rollingResistance * m * InsightConstants.gravity * speed;
      final air =
          0.5 *
          constants.airDensity *
          constants.dragArea *
          speed *
          speed *
          speed;
      final demand = m * a * speed + rolling + air;
      out.add(
        WheelMoment(
          seconds: s.seconds,
          dt: dt,
          speedKmh: speed * 3.6,
          rpm: s.rpm,
          throttle: s.throttle,
          tractionKw: math.max(0, demand) / 1000,
          rollingKw: rolling / 1000,
          airKw: air / 1000,
          brakingKw: math.max(0, -demand) / 1000,
          sample: s,
        ),
      );
    }
    return out;
  }
}
