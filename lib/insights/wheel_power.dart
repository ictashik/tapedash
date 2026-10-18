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

/// The wheel power of a drive, worked out from its speed trace (the car reports
/// no torque, and the City no fuel rate): the force to speed up, to roll and to
/// push the air aside, times the speed.
///
/// OBD speed is whole km/h and noisy, so the acceleration is taken over a window
/// of [window] seconds and not sample to sample. An estimate, and a rough one: it
/// knows nothing of hills.
abstract final class WheelPower {
  /// The longest gap between two samples that still counts as driving; a longer
  /// one is the engine being off or the link being out.
  static const double maxGap = 5;

  /// The seconds of speed the acceleration is taken over.
  static const double window = 3;

  static List<WheelMoment> moments(
    List<TripSample> samples, {
    InsightConstants constants = const InsightConstants(),
  }) {
    final out = <WheelMoment>[];
    if (samples.length < 2) return out;
    final m = constants.massKg;
    for (var i = 1; i < samples.length; i++) {
      final s = samples[i];
      final dt = s.seconds - samples[i - 1].seconds;
      if (dt <= 0 || dt > maxGap) continue;
      // The speed [window] seconds back, for a steadier acceleration.
      var j = i - 1;
      while (j > 0 && s.seconds - samples[j].seconds < window) {
        j--;
      }
      final span = s.seconds - samples[j].seconds;
      if (span <= 0 || span > window * 2 + maxGap) continue;
      final v = s.speedKmh / 3.6;
      final a = (v - samples[j].speedKmh / 3.6) / span;
      final rolling = v < 0.3
          ? 0.0
          : constants.rollingResistance * m * InsightConstants.gravity * v;
      final air = 0.5 * constants.airDensity * constants.dragArea * v * v * v;
      final inertia = m * a * v;
      final demand = inertia + rolling + air;
      out.add(
        WheelMoment(
          seconds: s.seconds,
          dt: dt,
          speedKmh: s.speedKmh,
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
