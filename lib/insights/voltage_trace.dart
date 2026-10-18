import 'dart:math' as math;

import '../trips/trip.dart';

/// A dip in the supply voltage while the engine ran: something took current from
/// the alternator, and the voltage sagged until it was done.
class VoltageDip {
  const VoltageDip({
    required this.startSeconds,
    required this.seconds,
    required this.depth,
    required this.lowest,
  });

  /// When it began, in seconds from the start of the trace.
  final double startSeconds;
  final double seconds;

  /// How far under the steady voltage it went, in volts.
  final double depth;
  final double lowest;
}

/// The module voltage of one stretch of driving (Current): where it sat, when it
/// dipped and how deep.
///
/// The car reports no battery current, so a load is known only by the dent it
/// leaves. A dip is a dent; what made it is not claimed (the survey drive's marks
/// are what name them).
class VoltageTrace {
  VoltageTrace._(this.points, this.dips, this.chargingShare, this.median);

  /// The voltage at which the alternator is charging; below it the battery is
  /// carrying the load.
  static const double chargingVolts = 13.6;

  /// A dip is this far under the steady voltage, and ends when it is back within
  /// [recoverVolts].
  static const double dipVolts = 0.35;
  static const double recoverVolts = 0.15;

  /// The least and most seconds a dip can last. Under it is noise in a reading
  /// that moves by 0.1 V; over it is the voltage settling, not a load.
  static const double minDipSeconds = 2;
  static const double maxDipSeconds = 60;

  /// The samples used, as (seconds, volts), where the car reported a voltage and
  /// the engine ran.
  final List<(double, double)> points;
  final List<VoltageDip> dips;

  /// The share of time at or above [chargingVolts], 0 to 1.
  final double chargingShare;

  /// The middle voltage, the steady one.
  final double median;

  bool get isEmpty => points.length < 10;

  factory VoltageTrace.from(List<TripSample> samples) {
    final pts = <(double, double)>[
      for (final s in samples)
        if (s.voltage != null && s.voltage! > 8 && s.rpm > 400)
          (s.seconds, s.voltage!),
    ];
    if (pts.length < 10) return VoltageTrace._(pts, const [], 0, 0);
    // The steady voltage at each point: a high percentile over a minute around
    // it, so that a dip does not drag its own baseline down.
    const half = 20;
    final base = <double>[];
    for (var i = 0; i < pts.length; i++) {
      final lo = math.max(0, i - half);
      final hi = math.min(pts.length, i + half + 1);
      final w = [for (var j = lo; j < hi; j++) pts[j].$2]..sort();
      base.add(w[math.min(w.length - 1, (w.length * 0.75).floor())]);
    }
    final dips = <VoltageDip>[];
    int? from;
    var steady = 0.0;
    var lowest = 99.0;
    for (var i = 0; i < pts.length; i++) {
      if (from == null) {
        if (base[i] - pts[i].$2 >= dipVolts) {
          from = i;
          steady = base[i];
          lowest = pts[i].$2;
        }
      } else {
        lowest = math.min(lowest, pts[i].$2);
        // A dip ends when the voltage is back to where it was before it, not to a
        // baseline that has itself sagged: a voltage that steps down and stays is
        // the regulator, not a load.
        if (pts[i].$2 >= steady - recoverVolts) {
          final start = pts[from].$1;
          final len = pts[i].$1 - start;
          if (len >= minDipSeconds && len <= maxDipSeconds) {
            dips.add(
              VoltageDip(
                startSeconds: start,
                seconds: len,
                depth: steady - lowest,
                lowest: lowest,
              ),
            );
          }
          from = null;
        }
      }
    }
    final volts = [for (final p in pts) p.$2]..sort();
    final charging = volts.where((v) => v >= chargingVolts).length;
    return VoltageTrace._(
      pts,
      dips,
      charging / volts.length,
      volts[volts.length ~/ 2],
    );
  }
}
